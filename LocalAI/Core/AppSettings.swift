import Foundation
import Combine

/// 搜索来源。国内网络下默认用必应。
enum SearchProvider: String, CaseIterable, Identifiable {
    case bing
    case duckduckgo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bing: return "必应（国内可直接访问）"
        case .duckduckgo: return "DuckDuckGo"
        }
    }
}

/// 全局设置。所有字段都写进 UserDefaults，重启后保留。
@MainActor
final class AppSettings: ObservableObject {

    @Published var searchProvider: SearchProvider {
        didSet { defaults.set(searchProvider.rawValue, forKey: Keys.provider) }
    }

    /// 生成温度：越低越稳，越高越发散
    @Published var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }

    /// 上下文窗口长度
    @Published var contextLength: Int {
        didSet { defaults.set(contextLength, forKey: Keys.context) }
    }

    /// 单次回答最多生成多少 token
    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: Keys.maxTokens) }
    }

    /// 默认对话模型 id
    @Published var selectedChatModelID: String {
        didSet { defaults.set(selectedChatModelID, forKey: Keys.selectedModel) }
    }

    /// 每次提问是否自动联网搜索
    @Published var autoSearch: Bool {
        didSet { defaults.set(autoSearch, forKey: Keys.autoSearch) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let provider = "search.provider"
        static let temperature = "llm.temperature"
        static let context = "llm.context"
        static let maxTokens = "llm.maxTokens"
        static let selectedModel = "llm.selectedModel"
        static let autoSearch = "web.autoSearch"
    }

    init() {
        let d = UserDefaults.standard
        searchProvider = SearchProvider(rawValue: d.string(forKey: Keys.provider) ?? "") ?? .bing
        let t = d.object(forKey: Keys.temperature) as? Double
        temperature = t ?? 0.7
        let c = d.object(forKey: Keys.context) as? Int
        contextLength = c ?? 4096
        let m = d.object(forKey: Keys.maxTokens) as? Int
        maxTokens = m ?? 512
        selectedChatModelID = d.string(forKey: Keys.selectedModel) ?? ModelCatalog.chatModels[0].id
        let a = d.object(forKey: Keys.autoSearch) as? Bool
        autoSearch = a ?? false
    }
}
