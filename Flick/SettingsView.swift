//
//  SettingsView.swift
//  Flick
//

import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?
    @State private var editingPrompt: CustomPrompt?
    @State private var isModelLibraryPresented = false
    @State private var fetchModelsTask: Task<Void, Never>?
    @State private var fetchGeneration = 0
    @State private var hotkeyError: String?
    @State private var balanceText = "未读取"
    @State private var isFetchingBalance = false
    @State private var balanceTask: Task<Void, Never>?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gear") }
            selectionTab
                .tabItem { Label("划词", systemImage: "text.cursor") }
            voiceTab
                .tabItem { Label("听写", systemImage: "waveform") }
        }
        .frame(width: 520, height: 460)
        .onDisappear {
            fetchModelsTask?.cancel()
            balanceTask?.cancel()
        }
        .onAppear {
            scheduleBalanceLoad(immediately: true)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditorSheet(
                prompt: prompt,
                onSave: { updated in
                    if let idx = settings.customPrompts.firstIndex(where: { $0.id == updated.id }) {
                        settings.customPrompts[idx] = updated
                    } else {
                        settings.customPrompts.append(updated)
                    }
                    editingPrompt = nil
                },
                onCancel: {
                    editingPrompt = nil
                }
            )
        }
        .sheet(isPresented: $isModelLibraryPresented) {
            ModelLibrarySheet(
                models: availableModels,
                favoriteModels: settings.favoriteModels,
                isLoading: isFetchingModels,
                errorMessage: fetchError,
                onRefresh: fetchModels,
                onAdd: { model in
                    settings.addFavoriteModel(model)
                    if settings.modelName.isEmpty || !settings.favoriteModels.contains(settings.modelName) {
                        settings.modelName = model
                    }
                }
            )
        }
    }

    private var voiceTab: some View {
        Form {
            Section("模型") {
                TextField("转写模型", text: $settings.transcriptionModel)
                    .textFieldStyle(.roundedBorder)
                TextField("润色模型", text: $settings.voicePolishingModel)
                    .textFieldStyle(.roundedBorder)
            }

            Section("快捷键") {
                HStack {
                    Text("按住说话")
                    Spacer()
                    HotkeyRecorderButton(config: settings.voiceHotkeyConfig) { config in
                        updateHotkey(config, forVoice: true)
                    }
                    Button("恢复默认") {
                        updateHotkey(.voiceDefault, forVoice: true)
                    }
                    .controlSize(.small)
                }
                if let hotkeyError {
                    Text(hotkeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("输入") {
                Toggle("插入前预览并确认", isOn: $settings.voicePreviewEnabled)
            }

            Section("说明") {
                Text("听写使用上方通用设置中的 API Key 和基础地址。松开快捷键后，Flick 会转写、整理并把文字输入到原来的光标位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("API 配置") {
                SecureField("API 密钥", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.apiKey) {
                        invalidateModelLibrary()
                        scheduleBalanceLoad()
                    }

                TextField("API 基础地址", text: $settings.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.apiBaseURL) {
                        invalidateModelLibrary()
                        scheduleBalanceLoad()
                    }
            }

            Section("账户余额") {
                HStack {
                    Text("OpenRouter")
                    Spacer()
                    if isFetchingBalance {
                        ProgressView().controlSize(.small)
                    }
                    Text(balanceText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("刷新") {
                        scheduleBalanceLoad(immediately: true)
                    }
                    .disabled(
                        isFetchingBalance || settings.apiKey.isEmpty ||
                        !settings.apiBaseURL.localizedCaseInsensitiveContains("openrouter.ai")
                    )
                }
            }

        }
        .formStyle(.grouped)
    }

    private func updateHotkey(_ config: HotkeyConfig, forVoice: Bool) {
        let other = forVoice ? settings.selectionHotkeyConfig : settings.voiceHotkeyConfig
        guard config.keyCode != other.keyCode || config.modifiers != other.modifiers else {
            hotkeyError = "两个功能不能使用相同的快捷键。"
            return
        }
        hotkeyError = nil
        if forVoice {
            settings.voiceHotkeyConfig = config
        } else {
            settings.selectionHotkeyConfig = config
        }
    }

    // MARK: - Selection Tab

    private var selectionTab: some View {
        Form {
            Section("划词模型") {
                HStack {
                    Text("当前模型")
                    Spacer()
                    Text(settings.modelName.isEmpty ? "未选择" : displayModelName(settings.modelName))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if settings.favoriteModels.isEmpty {
                    Text("还没有添加模型。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.favoriteModels, id: \.self) { model in
                        addedModelRow(for: model)
                    }
                    .onMove { source, destination in
                        settings.moveFavoriteModels(fromOffsets: source, toOffset: destination)
                    }
                }

                HStack {
                    Button(action: openModelLibrary) {
                        Label("添加模型", systemImage: "plus")
                    }
                    .disabled(settings.apiKey.isEmpty || settings.apiBaseURL.isEmpty)
                    if isFetchingModels { ProgressView().controlSize(.small) }
                }
                if let error = fetchError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("快捷键") {
                HStack {
                    Text("划词处理")
                    Spacer()
                    HotkeyRecorderButton(config: settings.selectionHotkeyConfig) { config in
                        updateHotkey(config, forVoice: false)
                    }
                    Button("恢复默认") {
                        updateHotkey(.selectionDefault, forVoice: false)
                    }
                    .controlSize(.small)
                }
                if let hotkeyError {
                    Text(hotkeyError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("提示词") {
                ForEach(settings.customPrompts) { prompt in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: prompt.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title)
                                .font(.body)
                            Text(prompt.systemPrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: {
                            editingPrompt = prompt
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            settings.customPrompts.removeAll { $0.id == prompt.id }
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    settings.customPrompts.move(fromOffsets: source, toOffset: destination)
                }

                HStack {
                    Button(action: {
                        editingPrompt = CustomPrompt(icon: "star", title: "", systemPrompt: "{{text}}")
                    }) {
                        Label("添加提示词", systemImage: "plus")
                    }

                    Spacer()

                    Button("恢复默认") {
                        settings.customPrompts = CustomPrompt.defaults
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func fetchModels() {
        guard !settings.apiKey.isEmpty, !settings.apiBaseURL.isEmpty else { return }
        fetchModelsTask?.cancel()
        fetchGeneration += 1
        let currentGeneration = fetchGeneration
        isFetchingModels = true
        fetchError = nil

        let baseURL = settings.apiBaseURL
        let apiKey = settings.apiKey
        let normalizedURL = AIService.normalizedBaseURL(baseURL)
        print("[Flick] Fetching models from: \(normalizedURL)/models")

        fetchModelsTask = Task {
            do {
                let models = try await AIService.fetchModels(
                    baseURL: baseURL,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                print("[Flick] Fetched \(models.count) models")
                await MainActor.run {
                    guard currentGeneration == fetchGeneration else { return }
                    availableModels = settings.orderedModels(from: models)
                    isFetchingModels = false
                    if settings.modelName.isEmpty, let firstFavorite = settings.favoriteModels.first {
                        settings.modelName = firstFavorite
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[Flick] Fetch models error: \(error)")
                await MainActor.run {
                    guard currentGeneration == fetchGeneration else { return }
                    fetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }

    private func openModelLibrary() {
        isModelLibraryPresented = true
        fetchModels()
    }

    private func invalidateModelLibrary() {
        availableModels = []
        fetchError = nil
        fetchModelsTask?.cancel()
        isFetchingModels = false
    }

    private func scheduleBalanceLoad(immediately: Bool = false) {
        balanceTask?.cancel()
        guard !settings.apiKey.isEmpty else {
            balanceText = "未配置 API Key"
            isFetchingBalance = false
            return
        }
        guard settings.apiBaseURL.localizedCaseInsensitiveContains("openrouter.ai") else {
            balanceText = "当前渠道不支持查询"
            isFetchingBalance = false
            return
        }

        let baseURL = settings.apiBaseURL
        let apiKey = settings.apiKey
        isFetchingBalance = true
        balanceTask = Task {
            do {
                if !immediately {
                    try await Task.sleep(for: .milliseconds(500))
                }
                let balance = try await AIService.fetchBalance(baseURL: baseURL, apiKey: apiKey)
                try Task.checkCancellation()
                await MainActor.run {
                    balanceText = String(format: "$%.2f", balance)
                    isFetchingBalance = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    balanceText = "读取失败"
                    isFetchingBalance = false
                }
            }
        }
    }

    private func displayModelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slashIndex = trimmed.firstIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slashIndex)...])
    }

    @ViewBuilder
    private func addedModelRow(for model: String) -> some View {
        HStack(spacing: 10) {
            Text(displayModelName(model))
                .lineLimit(1)

            Spacer()

            if settings.modelName == model {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }

            Button(action: {
                settings.removeFavoriteModel(model)
                if settings.modelName == model {
                    settings.modelName = settings.favoriteModels.first ?? ""
                }
            }) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settings.modelName = model
        }
    }
}

private struct HotkeyRecorderButton: View {
    let config: HotkeyConfig
    let onRecord: (HotkeyConfig) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "请按组合键…" : config.displayName) {
            beginRecording()
        }
        .frame(minWidth: 96)
        .onDisappear { stopRecording() }
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { stopRecording() }
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifiers = carbonModifiers(from: flags)
            guard modifiers != 0, let key = keyLabel(for: event) else { return nil }
            let displayName = modifierLabel(from: flags) + key
            let newConfig = HotkeyConfig(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                displayName: displayName
            )
            DispatchQueue.main.async {
                onRecord(newConfig)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func modifierLabel(from flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.command) { result += "⌘" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.shift) { result += "⇧" }
        return result
    }

    private func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            guard let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty
            else { return nil }
            return characters.uppercased()
        }
    }
}

struct ModelLibrarySheet: View {
    let models: [String]
    let favoriteModels: [String]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredModels: [String] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return models }
        return models.filter {
            $0.localizedCaseInsensitiveContains(normalizedQuery) ||
            displayModelName($0).localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private func displayModelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slashIndex = trimmed.firstIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slashIndex)...])
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("添加模型")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }

            TextField("搜索模型", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isLoading && models.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在获取模型列表...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredModels, id: \.self) { model in
                    HStack(spacing: 10) {
                        Text(displayModelName(model))
                            .lineLimit(1)

                        Spacer()

                        if favoriteModels.contains(model) {
                            Label("已添加", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("添加") {
                                onAdd(model)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Button(action: onRefresh) {
                    Label("刷新列表", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)

                Spacer()

                Text("\(models.count) 个模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 520, height: 520)
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {
    @State var prompt: CustomPrompt
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    private let iconOptions = [
        "star", "book", "doc.text", "globe", "pencil.line", "lightbulb",
        "text.magnifyingglass", "text.quote", "checkmark.circle",
        "arrow.triangle.2.circlepath", "wand.and.stars", "brain",
        "character.bubble", "translate", "doc.plaintext"
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text(prompt.title.isEmpty ? "新建提示词" : "编辑提示词")
                .font(.headline)

            ScrollView {
                Form {
                    Section("基本信息") {
                        Picker("图标", selection: $prompt.icon) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Label(icon, systemImage: icon).tag(icon)
                            }
                        }

                        TextField("名称", text: $prompt.title)
                            .textFieldStyle(.roundedBorder)

                        VStack(alignment: .leading) {
                            Text("提示词内容（使用 {{text}} 表示选中的文本）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $prompt.systemPrompt)
                                .font(.body)
                                .frame(height: 100)
                                .border(Color.secondary.opacity(0.2))
                        }
                    }


                }
                .formStyle(.grouped)
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    onSave(prompt)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.title.isEmpty || prompt.systemPrompt.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 420, height: 380)
    }
}
