//
//  SettingsView.swift
//  Flick
//

import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?
    @State private var editingPrompt: CustomPrompt?
    @State private var editingVoiceProfile: VoiceDictationProfile?
    @State private var isModelLibraryPresented = false
    @State private var fetchModelsTask: Task<Void, Never>?
    @State private var fetchGeneration = 0
    @State private var hotkeyError: String?
    @State private var balanceText = "未读取"
    @State private var isFetchingBalance = false
    @State private var balanceTask: Task<Void, Never>?
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var draggingPromptID: UUID?

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "通用"
        case selection = "划词"
        case voice = "听写"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .selection: "text.cursor"
            case .voice: "waveform"
            }
        }
    }

    private enum ConnectionStatus: Equatable {
        case idle, testing, success, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(FlickStyle.accent)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.black)
                }
                .frame(width: 28, height: 28)

                Text("FLICK")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.8)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { selectedTab = tab }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 15, height: 15)
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(selectedTab == tab ? Color.black : Color.white.opacity(0.64))
                            .padding(.horizontal, 14)
                            .frame(minWidth: 82, minHeight: 32, maxHeight: 32)
                            .background(
                                selectedTab == tab
                                    ? FlickStyle.accent
                                    : (hoveredTab == tab ? Color.white.opacity(0.09) : Color.clear),
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                            }
                        }
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1) }
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
            .background(Color.black.opacity(0.34))
            .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.08)) }

            Group {
                switch selectedTab {
                case .general: generalTab
                case .selection: selectionTab
                case .voice: voiceTab
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .tint(FlickStyle.accent)
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 600)
        .background(SettingsBackdrop())
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
        .sheet(item: $editingVoiceProfile) { profile in
            VoiceProfileEditorSheet(
                profile: profile,
                reservedHotkeys: [settings.selectionHotkeyConfig] + settings.voiceDictationProfiles
                    .filter { $0.id != profile.id }
                    .map(\.hotkey),
                onSave: { updated in
                    if let index = settings.voiceDictationProfiles.firstIndex(where: { $0.id == updated.id }) {
                        settings.voiceDictationProfiles[index] = updated
                    } else {
                        settings.voiceDictationProfiles.append(updated)
                    }
                    editingVoiceProfile = nil
                },
                onCancel: { editingVoiceProfile = nil }
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
        SettingsPage(
            title: "听写",
            subtitle: "为不同场景创建独立的语音输入工作流",
            symbol: "waveform"
        ) {
            GlassSettingsCard(title: "听写功能", symbol: "slider.horizontal.3") {
                ForEach(settings.voiceDictationProfiles) { profile in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).fontWeight(.medium)
                            Text("\(displayModelName(profile.transcriptionModel)) → \(displayModelName(profile.polishingModel))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(profile.hotkey.displayName)
                            .keyboardCapsule()
                        IconActionButton(symbol: "square.and.pencil", kind: .edit, help: "编辑听写功能") {
                            editingVoiceProfile = profile
                        }
                        IconActionButton(symbol: "trash", kind: .delete, help: "删除听写功能") {
                            settings.voiceDictationProfiles.removeAll { $0.id == profile.id }
                        }
                        .disabled(settings.voiceDictationProfiles.count == 1)
                    }
                    .padding(.vertical, 5)
                    if profile.id != settings.voiceDictationProfiles.last?.id { Divider().opacity(0.45) }
                }
                .onMove { source, destination in
                    settings.voiceDictationProfiles.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    editingVoiceProfile = VoiceDictationProfile(
                        name: "",
                        hotkey: .voiceDefault,
                        transcriptionModel: "openai/whisper-large-v3",
                        polishingModel: settings.modelName,
                        polishingPrompt: VoiceDictationProfile.defaultPolishingPrompt
                    )
                } label: {
                    Label("添加听写功能", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            GlassSettingsCard(title: "输入", symbol: "text.cursor") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("插入前预览并确认")
                            .fontWeight(.medium)
                        Text("在写入当前应用前检查润色结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.voicePreviewEnabled)
                        .labelsHidden()
                }
            }

            GlassSettingsCard(title: "使用说明", symbol: "info.circle") {
                Text("每个听写功能拥有独立的按住说话快捷键、语音转写模型、文本润色模型和润色提示词，并共用通用页面中的 API 配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.voiceDictationProfiles.count == 1 {
                    Text("至少需要保留一个听写功能。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        SettingsPage(
            title: "通用",
            subtitle: "连接你的 AI 服务，所有功能共用这套配置",
            symbol: "gearshape.fill"
        ) {
            GlassSettingsCard(title: "API 配置", symbol: "key.horizontal") {
                SettingsField(title: "API Key", hint: "用于验证 API 请求") {
                    SecureField("sk-…", text: $settings.apiKey)
                        .textFieldStyle(.plain)
                        .padding(9)
                        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                }
                    .onChange(of: settings.apiKey) {
                        connectionStatus = .idle
                        invalidateModelLibrary()
                        scheduleBalanceLoad()
                    }

                Divider().opacity(0.45)

                SettingsField(title: "API Base URL", hint: "OpenAI 兼容接口地址") {
                    TextField("https://openrouter.ai/api/v1", text: $settings.apiBaseURL)
                        .textFieldStyle(.plain)
                        .padding(9)
                        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                }
                    .onChange(of: settings.apiBaseURL) {
                        connectionStatus = .idle
                        invalidateModelLibrary()
                        scheduleBalanceLoad()
                    }

                Divider().opacity(0.45)

                HStack(spacing: 8) {
                    connectionStatusView
                    Spacer()
                    Button("测试连接") { testAPIConnection() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(
                            settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            connectionStatus == .testing
                        )
                }
            }

            GlassSettingsCard(title: "账户余额", symbol: "creditcard") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenRouter").fontWeight(.medium)
                        Text("当前 API Key 的可用余额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isFetchingBalance {
                        ProgressView().controlSize(.small)
                    }
                    Text(balanceText)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Button {
                        scheduleBalanceLoad(immediately: true)
                    } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(
                        isFetchingBalance || settings.apiKey.isEmpty ||
                        !settings.apiBaseURL.localizedCaseInsensitiveContains("openrouter.ai")
                    )
                }
            }
        }
    }

    private func updateSelectionHotkey(_ config: HotkeyConfig) {
        guard !settings.voiceDictationProfiles.contains(where: {
            $0.hotkey.keyCode == config.keyCode && $0.hotkey.modifiers == config.modifiers
        }) else {
            hotkeyError = "划词与听写功能不能使用相同的快捷键。"
            return
        }
        hotkeyError = nil
        settings.selectionHotkeyConfig = config
    }

    // MARK: - Selection Tab

    private var selectionTab: some View {
        SettingsPage(
            title: "划词",
            subtitle: "选择文本后，使用 AI 快速理解与改写",
            symbol: "text.cursor"
        ) {
            GlassSettingsCard(title: "划词模型", symbol: "sparkles") {
                HStack {
                    Text("当前模型").fontWeight(.medium)
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

            GlassSettingsCard(title: "快捷键", symbol: "keyboard") {
                HStack {
                    Text("划词处理")
                    Spacer()
                    HotkeyRecorderButton(config: settings.selectionHotkeyConfig) { config in
                        updateSelectionHotkey(config)
                    }
                    Button("恢复默认") {
                        updateSelectionHotkey(.selectionDefault)
                    }
                    .controlSize(.small)
                }
                if let hotkeyError {
                    Text(hotkeyError).font(.caption).foregroundStyle(.red)
                }
            }

            GlassSettingsCard(title: "提示词", symbol: "wand.and.stars") {
                ForEach(settings.customPrompts) { prompt in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggingPromptID = prompt.id
                                return NSItemProvider(object: prompt.id.uuidString as NSString)
                            }
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
                        IconActionButton(symbol: "square.and.pencil", kind: .edit, help: "编辑提示词") {
                            editingPrompt = prompt
                        }

                        IconActionButton(symbol: "trash", kind: .delete, help: "删除提示词") {
                            settings.customPrompts.removeAll { $0.id == prompt.id }
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.text],
                        delegate: PromptDropDelegate(
                            targetID: prompt.id,
                            prompts: $settings.customPrompts,
                            draggingID: $draggingPromptID
                        )
                    )
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

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle:
            Label("尚未测试", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("正在连接…")
            }
            .foregroundStyle(.secondary)
        case .success:
            Label("连接成功", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(message)
        }
    }

    private func testAPIConnection() {
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !baseURL.isEmpty else { return }
        connectionStatus = .testing
        Task {
            do {
                let models = try await AIService.fetchModels(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    availableModels = settings.orderedModels(from: models)
                    connectionStatus = .success
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
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

private struct PromptDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let sourceIndex = prompts.firstIndex(where: { $0.id == draggingID }),
              let targetIndex = prompts.firstIndex(where: { $0.id == targetID })
        else { return }

        withAnimation(.snappy(duration: 0.18)) {
            prompts.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private enum FlickStyle {
    static let accent = Color(red: 0.72, green: 1.0, blue: 0.0)
    static let canvas = Color(red: 0.035, green: 0.039, blue: 0.037)
    static let panel = Color(red: 0.075, green: 0.082, blue: 0.078)
    static let field = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.085)
}

private struct SettingsBackdrop: View {
    var body: some View {
        ZStack {
            FlickStyle.canvas
            RadialGradient(
                colors: [FlickStyle.accent.opacity(0.075), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 38, height: 38)
                        .background(FlickStyle.accent, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 2)

                content
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GlassSettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlickStyle.accent)
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlickStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(FlickStyle.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

private struct SettingsField<Field: View>: View {
    let title: String
    let hint: String
    @ViewBuilder let field: Field

    init(title: String, hint: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.hint = hint
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.medium)
                Spacer()
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            field
        }
    }
}

private extension View {
    func keyboardCapsule() -> some View {
        self
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(FlickStyle.accent)
            .background(FlickStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlickStyle.accent.opacity(0.22), lineWidth: 0.7)
            }
    }
}

private struct IconActionButton: View {
    enum Kind { case edit, delete }

    let symbol: String
    let kind: Kind
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    private var color: Color {
        switch kind {
        case .edit: FlickStyle.accent
        case .delete: Color(red: 1.0, green: 0.35, blue: 0.32)
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isHovering ? Color.black : color)
                .background(isHovering ? color : color.opacity(0.09), in: Circle())
                .overlay {
                    Circle().stroke(color.opacity(isHovering ? 0 : 0.2), lineWidth: 0.8)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
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
        .buttonStyle(.bordered)
        .controlSize(.small)
        .onDisappear { stopRecording() }
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.type == .flagsChanged,
               flags.contains(.function),
               flags.intersection([.command, .option, .control, .shift]).isEmpty {
                DispatchQueue.main.async {
                    onRecord(.functionKey)
                    stopRecording()
                }
                return nil
            }

            guard event.type == .keyDown else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { stopRecording() }
                return nil
            }

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

private struct VoiceProfileEditorSheet: View {
    @State private var profile: VoiceDictationProfile
    let reservedHotkeys: [HotkeyConfig]
    let onSave: (VoiceDictationProfile) -> Void
    let onCancel: () -> Void

    init(
        profile: VoiceDictationProfile,
        reservedHotkeys: [HotkeyConfig],
        onSave: @escaping (VoiceDictationProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _profile = State(initialValue: profile)
        self.reservedHotkeys = reservedHotkeys
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var hotkeyConflicts: Bool {
        reservedHotkeys.contains {
            $0.keyCode == profile.hotkey.keyCode && $0.modifiers == profile.hotkey.modifiers
        }
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.polishingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.polishingPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hotkeyConflicts
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("基本信息") {
                    TextField("功能名称", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("自定义按键") {
                    HStack {
                        Text("按住说话")
                        Spacer()
                        HotkeyRecorderButton(config: profile.hotkey) { config in
                            profile.hotkey = config
                        }
                    }
                    if hotkeyConflicts {
                        Text("该快捷键已被划词或其他听写功能使用。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("模型选择") {
                    TextField("语音转写模型", text: $profile.transcriptionModel)
                        .textFieldStyle(.roundedBorder)
                    TextField("文本润色模型", text: $profile.polishingModel)
                        .textFieldStyle(.roundedBorder)
                }

                Section("润色提示词") {
                    TextEditor(text: $profile.polishingPrompt)
                        .font(.body)
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.2))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.transcriptionModel = profile.transcriptionModel
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.polishingModel = profile.polishingModel
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(profile)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 480, height: 480)
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
