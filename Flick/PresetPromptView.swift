//
//  PresetPromptView.swift
//  Flick
//

import SwiftUI

struct PresetPromptView: View {
    let selectedText: String
    @ObservedObject var aiService: AIService
    @ObservedObject private var settings = SettingsManager.shared
    let onClose: () -> Void
    let onResize: (NSSize) -> Void

    @State private var activePrompt: CustomPrompt?
    @State private var customInput: String = ""
    @State private var isCustomMode = false
    private var prompts: [CustomPrompt] { settings.customPrompts }
    private var favoriteModels: [String] {
        settings.favoriteModels.filter { !$0.isEmpty }
    }

    private func displayModelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slashIndex = trimmed.firstIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slashIndex)...])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer(minLength: 8)

                modelSwitcher

                Button(action: {
                    settings.enableReasoning.toggle()
                }) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(settings.enableReasoning ? .orange : .secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(settings.enableReasoning ? "推理已开启" : "推理已关闭")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            if activePrompt == nil && !isCustomMode {
                promptList
            } else {
                responseView
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Compact Prompt List

    private func triggerPrompt(_ prompt: CustomPrompt) {
        activePrompt = prompt
        let promptText = prompt.systemPrompt
        if promptText.contains("{{text}}") {
            let userMessage = promptText.replacingOccurrences(of: "{{text}}", with: selectedText)
            aiService.sendRequest(systemPrompt: "", userContent: userMessage)
        } else {
            aiService.sendRequest(systemPrompt: promptText, userContent: selectedText)
        }
        onResize(NSSize(width: 380, height: 360))
    }

    private var promptList: some View {
        VStack(spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                Button(action: { triggerPrompt(prompt) }) {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        Image(systemName: prompt.icon)
                            .font(.caption)
                            .frame(width: 16)
                        Text(prompt.title)
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: 6) {
                TextField("输入自定义 Prompt...", text: $customInput)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { sendCustomPrompt() }

                Button(action: sendCustomPrompt) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption)
                        .foregroundColor(customInput.isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(customInput.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
                .padding(.bottom, 6)
        }
        .padding(.vertical, 4)
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
    }

    private func sendCustomPrompt() {
        guard !customInput.isEmpty else { return }
        isCustomMode = true
        let userMessage = customInput + "\n\n" + selectedText
        aiService.sendRequest(systemPrompt: "", userContent: userMessage)
        onResize(NSSize(width: 380, height: 360))
    }

    @State private var keyMonitor: Any?

    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard activePrompt == nil else { return event }
            guard let char = event.charactersIgnoringModifiers,
                  let digit = Int(char),
                  digit >= 1 && digit <= min(9, prompts.count)
            else { return event }
            triggerPrompt(prompts[digit - 1])
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Response View

    @State private var reasoningExpanded = false

    private var responseView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: {
                    aiService.cancel()
                    activePrompt = nil
                    isCustomMode = false
                    let listHeight = CGFloat(32 + prompts.count * 30 + 8 + 54)
                    onResize(NSSize(width: 280, height: listHeight))
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

                Spacer()

                if let prompt = activePrompt {
                    Label(prompt.title, systemImage: prompt.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isCustomMode {
                    Label("自定义", systemImage: "text.cursor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = aiService.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
                        } else {
                            // Reasoning section
                            if !aiService.reasoningText.isEmpty {
                                reasoningSection
                            }

                            // Loading indicator
                            if aiService.isLoading && aiService.responseText.isEmpty && aiService.reasoningText.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("处理中...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Final result with Markdown
                            if !aiService.responseText.isEmpty {
                                markdownContent(aiService.responseText)
                            }
                        }

                        // Scroll anchor
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                }
                .onChange(of: aiService.reasoningText) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: aiService.responseText) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            if !aiService.responseText.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(aiService.responseText, forType: .string)
                    }) {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Reasoning Section

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if aiService.isReasoning {
                // Reasoning in progress - show live
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("思考中...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(aiService.reasoningText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                // Reasoning done - collapsed by default
                DisclosureGroup(isExpanded: $reasoningExpanded) {
                    Text(aiService.reasoningText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    Text("思考过程")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Markdown Rendering

    @ViewBuilder
    private var modelSwitcher: some View {
        if favoriteModels.isEmpty {
            modelChip(settings.modelName)
        } else {
            Menu {
                ForEach(favoriteModels, id: \.self) { model in
                    Button(action: {
                        settings.modelName = model
                    }) {
                        if settings.modelName == model {
                            Label(displayModelName(model), systemImage: "checkmark")
                        } else {
                            Text(displayModelName(model))
                        }
                    }
                }
            } label: {
                modelChip(settings.modelName)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func modelChip(_ model: String) -> some View {
        Text(displayModelName(model))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 110)
    }

    @ViewBuilder
    private func markdownContent(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .textSelection(.enabled)
    }
}
