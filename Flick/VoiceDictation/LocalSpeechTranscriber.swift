import AVFoundation
import Foundation
import Speech

final class LocalSpeechTranscriber: @unchecked Sendable {
    enum LocalSpeechError: LocalizedError {
        case unavailable
        case timedOut
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .unavailable: return "本地语音识别不可用。"
            case .timedOut: return "等待本地语音识别结果超时。"
            case .emptyResult: return "本地语音识别没有返回文字。"
            }
        }
    }

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultStream: AsyncThrowingStream<String, Error>?
    private var resultContinuation: AsyncThrowingStream<String, Error>.Continuation?

    func start(localeIdentifier: String) async -> Bool {
        cancel()
        guard await requestAuthorization() else { return false }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else {
            print("[Flick] On-device Speech recognition unavailable for \(localeIdentifier)")
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        var continuation: AsyncThrowingStream<String, Error>.Continuation!
        let stream = AsyncThrowingStream<String, Error> { continuation = $0 }
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                }
            } else if let error {
                continuation.finish(throwing: error)
            }
        }

        lock.withLock {
            self.recognizer = recognizer
            self.request = request
            recognitionTask = task
            resultStream = stream
            resultContinuation = continuation
        }
        print("[Flick] Using Apple on-device Speech recognition (\(localeIdentifier))")
        return true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let currentRequest: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
            self.request
        }
        currentRequest?.append(buffer)
    }

    func finish() async throws -> String {
        let currentRequest: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
            self.request
        }
        let currentStream: AsyncThrowingStream<String, Error>? = lock.withLock {
            self.resultStream
        }
        guard let currentRequest, let currentStream else { throw LocalSpeechError.unavailable }
        currentRequest.endAudio()

        defer { cancel() }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var latest = ""
                for try await text in currentStream {
                    if !text.isEmpty { latest = text }
                }
                guard !latest.isEmpty else { throw LocalSpeechError.emptyResult }
                return latest
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw LocalSpeechError.timedOut
            }
            guard let result = try await group.next() else {
                throw LocalSpeechError.emptyResult
            }
            group.cancelAll()
            return result
        }
    }

    func cancel() {
        lock.withLock {
            recognitionTask?.cancel()
            resultContinuation?.finish()
            recognizer = nil
            request = nil
            recognitionTask = nil
            resultStream = nil
            resultContinuation = nil
        }
    }

    private func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
