import AppKit
import Foundation

@MainActor
final class VoiceDictationCoordinator {
    private enum Prompt {
        static let polish = """
        你是语音听写整理助手。请把用户的口语转写整理成可直接使用的书面文本：
        - 删除无意义的口头禅、语气词和重复内容；
        - 正确处理说话者的自我纠正，只保留最终表达；
        - 修正明显的转写错误、标点和基本格式；
        - 保持原意、语言和语气，不添加解释或新信息；
        - 只输出整理后的正文。
        """
    }

    private let recorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let overlay = VoiceStatusOverlayController()
    private var processingTask: Task<Void, Never>?
    private var targetApplication: NSRunningApplication?
    private var isHotkeyHeld = false

    func startRecording() {
        guard processingTask == nil else { return }
        isHotkeyHeld = true
        targetApplication = NSWorkspace.shared.frontmostApplication
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.start()
                if isHotkeyHeld {
                    overlay.show(.recording)
                } else {
                    let audioURL = try recorder.stop()
                    processingTask = Task { [weak self] in
                        await self?.process(audioURL: audioURL)
                    }
                }
            } catch {
                showError(error.localizedDescription)
                processingTask = nil
            }
        }
    }

    func stopRecording() {
        isHotkeyHeld = false
        guard recorder.state == .recording else { return }
        do {
            let audioURL = try recorder.stop()
            processingTask = Task { [weak self] in
                await self?.process(audioURL: audioURL)
            }
        } catch {
            showError(error.localizedDescription)
            processingTask = nil
        }
    }

    private func process(audioURL: URL) async {
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let settings = SettingsManager.shared
        guard !settings.apiKey.isEmpty else {
            showError("请先在设置中填写 API Key。")
            processingTask = nil
            return
        }
        do {
            overlay.show(.transcribing)
            let transcript = try await transcriptionService.transcribe(
                audioURL: audioURL,
                baseURL: settings.apiBaseURL,
                apiKey: settings.apiKey,
                model: settings.transcriptionModel
            )
            overlay.show(.polishing)
            let polished = try await AIService.streamChat(
                baseURL: settings.apiBaseURL,
                apiKey: settings.apiKey,
                model: settings.voicePolishingModel,
                systemPrompt: Prompt.polish,
                userContent: transcript,
                enableReasoning: false
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !polished.isEmpty else {
                throw TranscriptionService.TranscriptionError.emptyTranscript
            }
            if settings.voicePreviewEnabled {
                showPreview(polished)
            } else {
                insert(polished)
            }
        } catch is CancellationError {
            overlay.close()
            processingTask = nil
        } catch {
            showError(error.localizedDescription)
            processingTask = nil
        }
    }

    private func showPreview(_ text: String) {
        overlay.show(
            .preview(text),
            onConfirm: { [weak self] in self?.insert(text) },
            onCancel: { [weak self] in
                self?.overlay.close()
                self?.processingTask = nil
            }
        )
    }

    private func insert(_ text: String) {
        overlay.show(.inserting)
        targetApplication?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            do {
                try TextInjector.inject(text)
                self?.overlay.close()
            } catch {
                self?.showError(error.localizedDescription)
            }
            self?.processingTask = nil
        }
    }

    private func showError(_ message: String) {
        overlay.show(.error(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.overlay.close()
        }
    }
}
