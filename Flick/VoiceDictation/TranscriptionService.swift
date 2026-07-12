import Foundation

struct TranscriptionService {
    enum TranscriptionError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case emptyTranscript
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "API 基础地址无效。"
            case .invalidResponse:
                return "转写服务返回了无法识别的数据。"
            case .emptyTranscript:
                return "没有识别到语音内容。"
            case .httpError(let code, let message):
                return "转写失败（HTTP \(code)）：\(message)"
            }
        }
    }

    func transcribe(
        audioURL: URL,
        baseURL: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let url = URL(
            string: "\(AIService.normalizedBaseURL(baseURL))/audio/transcriptions"
        ) else {
            throw TranscriptionError.invalidBaseURL
        }

        let audioData = try Data(contentsOf: audioURL)
        let payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": audioData.base64EncodedString(),
                "format": "wav"
            ]
        ]

        var request = AIService.makeAuthorizedRequest(url: url, apiKey: apiKey)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await AIService.directSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data)
            throw TranscriptionError.httpError(httpResponse.statusCode, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw TranscriptionError.invalidResponse
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyTranscript }
        return trimmed
    }

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "未知错误"
    }
}
