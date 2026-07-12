//
//  SettingsManager.swift
//  Flick
//

import Foundation
import Combine
import Carbon

struct CustomPrompt: Identifiable, Codable, Equatable {
    var id: UUID
    var icon: String
    var title: String
    var systemPrompt: String

    init(id: UUID = UUID(), icon: String, title: String, systemPrompt: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.systemPrompt = systemPrompt
    }

    static let defaults: [CustomPrompt] = [
        CustomPrompt(icon: "book", title: "解释", systemPrompt: "请清晰简洁地解释以下内容。如果是词语或短语，请给出定义和用法。\n\n{{text}}"),
        CustomPrompt(icon: "doc.text", title: "总结", systemPrompt: "请简洁地总结以下内容，提炼关键要点。\n\n{{text}}"),
        CustomPrompt(icon: "globe", title: "翻译为中文", systemPrompt: "请将以下内容翻译为中文。只输出翻译结果，不需要解释。\n\n{{text}}"),
        CustomPrompt(icon: "pencil.line", title: "润色", systemPrompt: "请润色和改进以下内容，保持原意不变，使其更流畅、更专业。\n\n{{text}}"),
        CustomPrompt(icon: "lightbulb", title: "续写", systemPrompt: "请根据以下内容继续写作，保持一致的风格和语气。\n\n{{text}}")
    ]
}

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayName: String

    static let selectionDefault = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_E),
        modifiers: UInt32(cmdKey),
        displayName: "⌘E"
    )
    static let voiceDefault = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(cmdKey | shiftKey),
        displayName: "⌘⇧D"
    )
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let apiBaseURL = "apiBaseURL"
        static let modelName = "modelName"
        static let apiKey = "apiKey"
        static let customPrompts = "customPrompts"
        static let selectionHotkeyConfig = "selectionHotkeyConfig"
        static let voiceHotkeyConfig = "voiceHotkeyConfig"
        static let enableReasoning = "enableReasoning"
        static let favoriteModels = "favoriteModels"
        static let transcriptionModel = "transcriptionModel"
        static let voicePreviewEnabled = "voicePreviewEnabled"
    }

    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: Keys.modelName) }
    }

    @Published var apiKey: String {
        didSet { KeychainHelper.save(key: Keys.apiKey, value: apiKey) }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let data = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(data, forKey: Keys.customPrompts)
            }
        }
    }

    @Published var enableReasoning: Bool {
        didSet { UserDefaults.standard.set(enableReasoning, forKey: Keys.enableReasoning) }
    }

    @Published var favoriteModels: [String] {
        didSet {
            UserDefaults.standard.set(favoriteModels, forKey: Keys.favoriteModels)
        }
    }

    @Published var selectionHotkeyConfig: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(selectionHotkeyConfig) {
                UserDefaults.standard.set(data, forKey: Keys.selectionHotkeyConfig)
            }
        }
    }

    @Published var voiceHotkeyConfig: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(voiceHotkeyConfig) {
                UserDefaults.standard.set(data, forKey: Keys.voiceHotkeyConfig)
            }
        }
    }

    @Published var transcriptionModel: String {
        didSet { UserDefaults.standard.set(transcriptionModel, forKey: Keys.transcriptionModel) }
    }

    @Published var voicePreviewEnabled: Bool {
        didSet { UserDefaults.standard.set(voicePreviewEnabled, forKey: Keys.voicePreviewEnabled) }
    }

    private init() {
        self.apiBaseURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL) ?? "https://api.openai.com/v1"
        self.modelName = UserDefaults.standard.string(forKey: Keys.modelName) ?? "gpt-4o"
        self.apiKey = KeychainHelper.read(key: Keys.apiKey) ?? ""
        self.enableReasoning = UserDefaults.standard.bool(forKey: Keys.enableReasoning)
        self.favoriteModels = UserDefaults.standard.stringArray(forKey: Keys.favoriteModels) ?? []
        self.transcriptionModel = UserDefaults.standard.string(forKey: Keys.transcriptionModel)
            ?? "openai/whisper-large-v3"
        self.voicePreviewEnabled = UserDefaults.standard.bool(forKey: Keys.voicePreviewEnabled)

        if let data = UserDefaults.standard.data(forKey: Keys.customPrompts),
           let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: data) {
            self.customPrompts = prompts
        } else {
            self.customPrompts = CustomPrompt.defaults
        }

        if let data = UserDefaults.standard.data(forKey: Keys.selectionHotkeyConfig),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.selectionHotkeyConfig = config
        } else {
            self.selectionHotkeyConfig = HotkeyConfig.selectionDefault
        }

        if let data = UserDefaults.standard.data(forKey: Keys.voiceHotkeyConfig),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.voiceHotkeyConfig = config
        } else {
            self.voiceHotkeyConfig = HotkeyConfig.voiceDefault
        }
    }

    func isFavoriteModel(_ model: String) -> Bool {
        favoriteModels.contains(model)
    }

    func toggleFavoriteModel(_ model: String) {
        if let index = favoriteModels.firstIndex(of: model) {
            favoriteModels.remove(at: index)
        } else {
            favoriteModels.append(model)
        }
    }

    func addFavoriteModel(_ model: String) {
        guard !model.isEmpty, !favoriteModels.contains(model) else { return }
        favoriteModels.append(model)
    }

    func removeFavoriteModel(_ model: String) {
        favoriteModels.removeAll { $0 == model }
    }

    func moveFavoriteModels(visibleFavorites: [String], fromOffsets source: IndexSet, toOffset destination: Int) {
        var reorderedVisibleFavorites = visibleFavorites
        reorderedVisibleFavorites.move(fromOffsets: source, toOffset: destination)

        let hiddenFavorites = favoriteModels.filter { !visibleFavorites.contains($0) }
        favoriteModels = reorderedVisibleFavorites + hiddenFavorites
    }

    func moveFavoriteModels(fromOffsets source: IndexSet, toOffset destination: Int) {
        favoriteModels.move(fromOffsets: source, toOffset: destination)
    }

    func orderedModels(from models: [String]) -> [String] {
        let availableSet = Set(models)
        let favorites = favoriteModels.filter { availableSet.contains($0) }
        let others = models.filter { !favorites.contains($0) }
        return favorites + others
    }
}
