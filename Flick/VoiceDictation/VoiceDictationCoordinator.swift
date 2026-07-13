import AppKit
import Foundation

@MainActor
final class VoiceDictationCoordinator {
    private let recorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let localSpeechTranscriber = LocalSpeechTranscriber()
    private let overlay = VoiceStatusOverlayController()
    private var processingTask: Task<Void, Never>?
    private var targetApplication: NSRunningApplication?
    private var isHotkeyHeld = false
    private var activeProfile: VoiceDictationProfile?
    private var isUsingLocalSpeech = false

    func startRecording(profile: VoiceDictationProfile) {
        guard processingTask == nil else { return }
        isHotkeyHeld = true
        activeProfile = profile
        targetApplication = NSWorkspace.shared.frontmostApplication
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                isUsingLocalSpeech = await localSpeechTranscriber.start(localeIdentifier: "zh-CN")
                recorder.onAudioBuffer = isUsingLocalSpeech ? { [weak transcriber = localSpeechTranscriber] buffer in
                    transcriber?.append(buffer)
                } : nil
                try await recorder.start()
                if isHotkeyHeld {
                    overlay.show(.recording)
                } else {
                    let audioURL = try recorder.stop()
                    recorder.onAudioBuffer = nil
                    let useLocalSpeech = isUsingLocalSpeech
                    processingTask = Task { [weak self] in
                        await self?.process(
                            audioURL: audioURL,
                            profile: profile,
                            useLocalSpeech: useLocalSpeech
                        )
                    }
                }
            } catch {
                showError(error.localizedDescription)
                processingTask = nil
                activeProfile = nil
                recorder.onAudioBuffer = nil
                localSpeechTranscriber.cancel()
            }
        }
    }

    func stopRecording(profileID: UUID) {
        isHotkeyHeld = false
        guard activeProfile?.id == profileID, recorder.state == .recording,
              let profile = activeProfile else { return }
        do {
            let audioURL = try recorder.stop()
            recorder.onAudioBuffer = nil
            let useLocalSpeech = isUsingLocalSpeech
            processingTask = Task { [weak self] in
                await self?.process(
                    audioURL: audioURL,
                    profile: profile,
                    useLocalSpeech: useLocalSpeech
                )
            }
        } catch {
            showError(error.localizedDescription)
            processingTask = nil
            activeProfile = nil
            recorder.onAudioBuffer = nil
            localSpeechTranscriber.cancel()
        }
    }

    private func process(
        audioURL: URL,
        profile: VoiceDictationProfile,
        useLocalSpeech: Bool
    ) async {
        defer {
            localSpeechTranscriber.cancel()
            try? FileManager.default.removeItem(at: audioURL)
        }
        let settings = SettingsManager.shared
        guard !settings.apiKey.isEmpty else {
            showError("请先在设置中填写 API Key。")
            processingTask = nil
            activeProfile = nil
            return
        }
        do {
            overlay.show(.transcribing)
            let transcript = try await transcript(
                audioURL: audioURL,
                profile: profile,
                settings: settings,
                preferLocal: useLocalSpeech
            )
            overlay.show(.polishing)
            let polished = try await AIService.streamChat(
                baseURL: settings.apiBaseURL,
                apiKey: settings.apiKey,
                model: profile.polishingModel,
                systemPrompt: profile.polishingPrompt,
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
            activeProfile = nil
        } catch {
            showError(error.localizedDescription)
            processingTask = nil
            activeProfile = nil
        }
    }

    private func transcript(
        audioURL: URL,
        profile: VoiceDictationProfile,
        settings: SettingsManager,
        preferLocal: Bool
    ) async throws -> String {
        if preferLocal {
            do {
                let text = try await localSpeechTranscriber.finish()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {
                print("[Flick] Local Speech failed, falling back to OpenRouter: \(error)")
            }
        }

        return try await transcriptionService.transcribe(
            audioURL: audioURL,
            baseURL: settings.apiBaseURL,
            apiKey: settings.apiKey,
            model: profile.transcriptionModel
        )
    }

    private func showPreview(_ text: String) {
        overlay.show(
            .preview(text),
            onConfirm: { [weak self] in self?.insert(text) },
            onCancel: { [weak self] in
                self?.overlay.close()
                self?.processingTask = nil
                self?.activeProfile = nil
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
            self?.activeProfile = nil
        }
    }

    private func showError(_ message: String) {
        overlay.show(.error(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.overlay.close()
        }
    }
}
