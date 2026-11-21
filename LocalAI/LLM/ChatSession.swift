import Foundation
import Combine

struct ChatMessage: Identifiable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    var role: Role
    var text: String
    var sources: [WebResult] = []
}

@MainActor
final class ChatSession: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var statusText: String = ""
    @Published var lastError: String?

    private var runner: LlamaRunner?
    private var loadedSignature: String?

    var hasModel: Bool { runner != nil }

    var currentModelName: String? {
        guard let signature = loadedSignature else { return nil }
        let id = signature.split(separator: "#").first.map(String.init) ?? ""
        return ModelCatalog.model(withID: id)?.name
    }

    func unload() {
        runner?.cancel()
        runner = nil
        loadedSignature = nil
    }

    func stop() {
        runner?.cancel()
        statusText = "已停止"
    }

    private func loadIfNeeded(model: CatalogModel, url: URL, settings: AppSettings) throws {
        let signature = "\(model.id)#\(settings.contextLength)"
        if loadedSignature == signature, runner != nil { return }

        runner = nil
        loadedSignature = nil
        statusText = "正在加载模型，请稍候…"
        defer { statusText = "" }

        runner = try LlamaRunner(modelURL: url, contextLength: settings.contextLength, threadCount: 0)
        loadedSignature = signature
    }

    func send(_ text: String, settings: AppSettings, store: ModelStore) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        guard let model = ModelCatalog.model(withID: settings.selectedChatModelID),
              let url = store.available[model.id] else {
            lastError = "还没有可用的对话模型，先去「模型」页下载一个。"
            return
        }

        do {
            try loadIfNeeded(model: model, url: url, settings: settings)
        } catch {
            lastError = error.localizedDescription
            return
        }

        guard let runner else {
            lastError = "模型没有加载成功。"
            return
        }

        lastError = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        draft = ""

        var sources: [WebResult] = []
        if settings.autoSearch {
            statusText = "正在联网搜索…"
            do {
                sources = try await WebSearcher.search(trimmed, provider: settings.searchProvider)
            } catch {
                lastError = "搜索没成功：\(error.localizedDescription)"
            }
            statusText = ""
        }

        let answerIndex = messages.count
        messages.append(ChatMessage(role: .assistant, text: "", sources: sources))

        let prompt = buildPrompt(sources: sources)
        isGenerating = true
        defer {
            isGenerating = false
            statusText = ""
        }

        do {
            let answer = try await runner.generate(messages: prompt,
                                                   maxTokens: settings.maxTokens,
                                                   temperature: settings.temperature) { piece in
                Task { @MainActor in
                    guard answerIndex < self.messages.count else { return }
                    self.messages[answerIndex].text += piece
                }
            }
            if answerIndex < messages.count {
                messages[answerIndex].text = answer
                messages[answerIndex].sources = sources
            }
        } catch {
            if answerIndex < messages.count, messages[answerIndex].text.isEmpty {
                messages.remove(at: answerIndex)
            }
            lastError = error.localizedDescription
        }
    }

    /// 用一段「图片分析结果」去问模型
    func askAboutImage(description: String, settings: AppSettings, store: ModelStore) async {
        let question = "我用本地的识图模型分析了这张图片，结果是：\n\n\(description)\n\n请用通俗的话告诉我这张图大概是什么、有什么值得注意的地方。"
        await send(question, settings: settings, store: store)
    }

    func clear() {
        unload()
        messages.removeAll()
        lastError = nil
        statusText = ""
    }

    private func buildPrompt(sources: [WebResult]) -> [(role: String, content: String)] {
        var system = "你叫「小模」，一个完全跑在这台 iPhone 本地的中文助手。"
        system += "回答要简短、口语化、分点清楚，一般不超过 120 字。不确定就直说不知道，不要编造事实。"

        if !sources.isEmpty {
            system += "\n\n下面是从网上搜到的资料，只依据这些资料回答，并在最后用「来源：[序号]」标出用到的条目：\n"
            for (index, item) in sources.enumerated() {
                system += "\n[\(index + 1)] \(item.title)\n\(item.snippet)\n\(item.url)\n"
            }
        }

        var prompt: [(role: String, content: String)] = [("system", system)]
        let history = messages.filter { !$0.text.isEmpty }
        for message in history.suffix(6) {
            prompt.append((message.role == .user ? "user" : "assistant", message.text))
        }
        return prompt
    }
}
