//
//  PresetPromptView.swift
//  Flick
//

import SwiftUI

private enum FloatingStyle {
    static let accent = Color(red: 0.72, green: 1.0, blue: 0.0)
    static let canvas = Color(red: 0.035, green: 0.039, blue: 0.037)
    static let panel = Color(red: 0.075, green: 0.082, blue: 0.078)
    static let border = Color.white.opacity(0.1)
}

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
            topToolbar
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
        .background(FloatingStyle.canvas)
        .tint(FloatingStyle.accent)
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FloatingStyle.border, lineWidth: 1)
        )
    }

    private var isShowingResponse: Bool { activePrompt != nil || isCustomMode }

    private var topToolbar: some View {
        ZStack {
            if isShowingResponse {
                Group {
                    if let prompt = activePrompt {
                        Label(prompt.title, systemImage: prompt.icon)
                    } else {
                        Label("自定义", systemImage: "text.cursor")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FloatingStyle.accent)
                .lineLimit(1)
            } else {
                modelSwitcher
            }

            HStack(spacing: 8) {
                if isShowingResponse {
                    Button(action: returnToPromptList) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: { settings.enableReasoning.toggle() }) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settings.enableReasoning ? .black : Color.white.opacity(0.48))
                        .frame(width: 26, height: 26)
                        .background(
                            settings.enableReasoning ? FloatingStyle.accent : Color.white.opacity(0.06),
                            in: Circle()
                        )
                        .overlay { Circle().stroke(FloatingStyle.border, lineWidth: 0.7) }
                }
                .buttonStyle(.plain)
                .help(settings.enableReasoning ? "推理已开启" : "推理已关闭")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 28)
    }

    private func returnToPromptList() {
        aiService.cancel()
        activePrompt = nil
        isCustomMode = false
        let listHeight = CGFloat(50 + prompts.count * 38 + 64)
        onResize(NSSize(width: 320, height: min(listHeight, 360)))
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
        onResize(NSSize(width: 400, height: 380))
    }

    private var promptList: some View {
        VStack(spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                FloatingPromptButton(index: index + 1, prompt: prompt) { triggerPrompt(prompt) }
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
                        .foregroundColor(customInput.isEmpty ? .gray : FloatingStyle.accent)
                }
                .buttonStyle(.plain)
                .disabled(customInput.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(FloatingStyle.panel, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
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
        onResize(NSSize(width: 400, height: 380))
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
                        .foregroundStyle(FloatingStyle.accent)
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
                        .foregroundStyle(FloatingStyle.accent)
                }
            }
        }
        .padding(8)
        .background(FloatingStyle.accent.opacity(0.07))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(FloatingStyle.accent.opacity(0.18)) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .fontWeight(.semibold)
        .foregroundStyle(FloatingStyle.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(FloatingStyle.accent.opacity(0.08))
        .overlay { Capsule().stroke(FloatingStyle.accent.opacity(0.18), lineWidth: 0.7) }
        .clipShape(Capsule())
        .frame(maxWidth: 110)
    }

    @ViewBuilder
    private func markdownContent(_ text: String) -> some View {
        FloatingMarkdownView(text: text)
    }
}

private struct FloatingMarkdownView: View {
    let text: String

    private enum Block: Identifiable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case quote(String)
        case code(String, String?)
        case divider

        var id: UUID { UUID() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inlineMarkdown(content))
                .font(headingFont(level))
                .foregroundStyle(level == 1 ? FloatingStyle.accent : .primary)
                .padding(.top, level == 1 ? 3 : 1)
        case .paragraph(let content):
            Text(inlineMarkdown(content))
                .font(.callout)
                .lineSpacing(3)
        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(FloatingStyle.accent)
                    .frame(width: 5, height: 5)
                Text(inlineMarkdown(content))
                    .font(.callout)
            }
        case .numbered(let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(number)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(FloatingStyle.accent)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(inlineMarkdown(content))
                    .font(.callout)
            }
        case .quote(let content):
            Text(inlineMarkdown(content))
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.68))
                .padding(.leading, 11)
                .overlay(alignment: .leading) {
                    Capsule().fill(FloatingStyle.accent).frame(width: 3)
                }
        case .code(let content, let language):
            VStack(alignment: .leading, spacing: 7) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(FloatingStyle.accent)
                }
                ScrollView(.horizontal) {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.hidden)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(FloatingStyle.border) }
        case .divider:
            Divider().overlay(FloatingStyle.border)
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushCode() {
            result.append(.code(codeLines.joined(separator: "\n"), codeLanguage))
            codeLines.removeAll()
            codeLanguage = nil
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if isInCode { flushCode() } else {
                    flushParagraph()
                    let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                }
                isInCode.toggle()
                continue
            }
            if isInCode {
                codeLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flushParagraph(); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(); result.append(.divider); continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph(); result.append(.heading(heading.0, heading.1)); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph(); result.append(.bullet(String(trimmed.dropFirst(2)))); continue
            }
            if let numbered = numberedItem(from: trimmed) {
                flushParagraph(); result.append(.numbered(numbered.0, numbered.1)); continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph(); result.append(.quote(String(trimmed.dropFirst(2)))); continue
            }
            paragraph.append(line)
        }
        if isInCode || !codeLines.isEmpty { flushCode() }
        flushParagraph()
        return result
    }

    private func heading(from line: String) -> (Int, String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private func numberedItem(from line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: "."), dot < line.endIndex else { return nil }
        let number = String(line[..<dot])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let contentStart = line.index(after: dot)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return (number + ".", String(line[line.index(after: contentStart)...]))
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.bold()
        case 2: .headline.bold()
        default: .callout.bold()
        }
    }
}

private struct FloatingPromptButton: View {
    let index: Int
    let prompt: CustomPrompt
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHovering ? Color.black : FloatingStyle.accent)
                    .frame(width: 20, height: 20)
                    .background(
                        isHovering ? FloatingStyle.accent : FloatingStyle.accent.opacity(0.09),
                        in: Circle()
                    )
                Image(systemName: prompt.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHovering ? FloatingStyle.accent : Color.white.opacity(0.58))
                    .frame(width: 18)
                Text(prompt.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovering ? FloatingStyle.accent : Color.white.opacity(0.18))
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(isHovering ? FloatingStyle.panel : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) { isHovering = hovering }
        }
    }
}
