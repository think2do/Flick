import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording
        case failed(String)
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case noRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "没有麦克风权限，请在系统设置的隐私与安全性中允许 Flick 使用麦克风。"
            case .alreadyRecording:
                return "录音已经开始。"
            case .noRecording:
                return "当前没有正在进行的录音。"
            }
        }
    }

    var onStateChange: ((State) -> Void)?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    func start() async throws {
        guard state != .recording else { throw RecorderError.alreadyRecording }
        guard await requestMicrophoneAccess() else {
            state = .failed(RecorderError.permissionDenied.localizedDescription)
            throw RecorderError.permissionDenied
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            let error = NSError(
                domain: "Flick.AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "没有检测到可用的麦克风输入设备。"]
            )
            state = .failed(error.localizedDescription)
            throw error
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flick-dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            audioFile = file
            recordingURL = url
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                do {
                    try self?.audioFile?.write(from: buffer)
                } catch {
                    print("[Flick] Failed to write audio buffer: \(error)")
                }
            }
            engine.prepare()
            try engine.start()
            state = .recording
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() throws -> URL {
        guard state == .recording, let recordingURL else {
            throw RecorderError.noRecording
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        self.recordingURL = nil
        state = .idle
        return recordingURL
    }

    func cancel() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        state = .idle
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
