//
//  AIService.swift
//  Flick
//

import Foundation
import Combine

class AIService: ObservableObject {
    @Published var responseText: String = ""
    @Published var reasoningText: String = ""
    @Published var isLoading: Bool = false
    @Published var isReasoning: Bool = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    /// Normalizes the base URL to ensure it ends with /v1
    static func normalizedBaseURL(_ baseURL: String) -> String {
        var url = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !url.hasSuffix("/v1") {
            url += "/v1"
        }
        return url
    }

    func sendRequest(systemPrompt: String, userContent: String) {
        let settings = SettingsManager.shared
        guard !settings.apiKey.isEmpty else {
            errorMessage = "请先在设置中填写 API Key。"
            return
        }

        cancel()
        responseText = ""
        reasoningText = ""
        errorMessage = nil
        isLoading = true
        isReasoning = false

        currentTask = Task { [weak self] in
            do {
                _ = try await Self.streamChat(
                    baseURL: settings.apiBaseURL,
                    apiKey: settings.apiKey,
                    model: settings.modelName,
                    systemPrompt: systemPrompt,
                    userContent: userContent,
                    enableReasoning: settings.enableReasoning,
                    onReasoningDelta: { [weak self] reasoning in
                        guard let service = self else { return }
                        await MainActor.run {
                            service.isReasoning = true
                            service.reasoningText += reasoning
                        }
                    },
                    onContentDelta: { [weak self] content in
                        guard let service = self else { return }
                        await MainActor.run {
                            service.isReasoning = false
                            service.responseText += content
                        }
                    }
                )
                guard let service = self else { return }
                await MainActor.run {
                    service.isReasoning = false
                    service.isLoading = false
                }
            } catch is CancellationError {
                // cancelled
            } catch {
                let weakSelf = self
                await MainActor.run {
                    weakSelf?.errorMessage = error.localizedDescription
                    weakSelf?.isLoading = false
                    weakSelf?.isReasoning = false
                }
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        isReasoning = false
    }

    /// A URLSession that bypasses system proxy to avoid auth header stripping
    static let directSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    static func makeAuthorizedRequest(
        url: URL,
        apiKey: String,
        contentType: String? = "application/json"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Streams a chat completion independently from any view state and returns
    /// the complete content accumulated from the stream.
    static func streamChat(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: String,
        enableReasoning: Bool,
        onReasoningDelta: ((String) async -> Void)? = nil,
        onContentDelta: ((String) async -> Void)? = nil
    ) async throws -> String {
        let url = URL(string: "\(Self.normalizedBaseURL(baseURL))/chat/completions")!
        var request = makeAuthorizedRequest(url: url, apiKey: apiKey)
        request.httpMethod = "POST"
        print("[Flick] Chat request: reasoning=\(enableReasoning), model=\(model)")

        var messages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": userContent])

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages
        ]

        if enableReasoning {
            body["include_reasoning"] = true
            body["reasoning"] = ["effort": "medium"]
        } else {
            // Explicitly disable reasoning for models that default to thinking
            body["include_reasoning"] = false
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await Self.directSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw AIError.httpError(httpResponse.statusCode, errorBody)
        }

        // Track if we've seen any reasoning tokens
        var result = ""

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" { break }

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { continue }

            // Handle reasoning tokens (from delta.reasoning field)
            if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                await onReasoningDelta?(reasoning)
            }

            // Handle content tokens
            if let content = delta["content"] as? String, !content.isEmpty {
                result += content
                await onContentDelta?(content)
            }
        }
        return result
    }

    // Fetch available models from API
    static func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let url = URL(string: "\(normalizedBaseURL(baseURL))/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await directSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.httpError(httpResponse.statusCode, message)
            }
            throw AIError.httpError(httpResponse.statusCode, "Request failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { return [] }

        return models.compactMap { $0["id"] as? String }.sorted()
    }

    static func fetchBalance(baseURL: String, apiKey: String) async throws -> Double {
        let url = URL(string: "\(normalizedBaseURL(baseURL))/credits")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await directSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.httpError(httpResponse.statusCode, message)
            }
            throw AIError.httpError(httpResponse.statusCode, "Request failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let totalCredits = data["total_credits"] as? Double,
              let totalUsage = data["total_usage"] as? Double
        else {
            throw AIError.invalidResponse
        }

        return totalCredits - totalUsage
    }
}

enum AIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}
