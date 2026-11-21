import Foundation
import Combine

enum ModelKind {
    case vision
    case chat
}

struct CatalogModel: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let fileName: String
    let approxSize: String
    let kind: ModelKind
    let isBuiltin: Bool
    let downloadURL: String

    static func == (lhs: CatalogModel, rhs: CatalogModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ModelCatalog {
    /// 内置视觉模型：由系统 Apple Vision 提供，不占用户存储、不需要下载。
    static let visionModel = CatalogModel(
        id: "vision.builtin",
        name: "内置视觉模型",
        detail: "系统自带，负责图像分类、文字识别、条码识别。完全离线，不联网。",
        fileName: "",
        approxSize: "0 MB（系统内置）",
        kind: .vision,
        isBuiltin: true,
        downloadURL: ""
    )

    static let chatModels: [CatalogModel] = [
        CatalogModel(
            id: "chat.qwen2.5-0.5b.q4",
            name: "轻量对话模型",
            detail: "通义千问 2.5 0.5B，4 位量化。手机上好跑，回答问题简短直接。",
            fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            approxSize: "约 470 MB",
            kind: .chat,
            isBuiltin: false,
            downloadURL: "https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"
        ),
        CatalogModel(
            id: "chat.qwen2.5-1.5b.q4",
            name: "增强对话模型",
            detail: "通义千问 2.5 1.5B，4 位量化。更聪明，但更吃内存、速度略慢。",
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            approxSize: "约 1.0 GB",
            kind: .chat,
            isBuiltin: false,
            downloadURL: "https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf"
        )
    ]

    static var all: [CatalogModel] { [visionModel] + chatModels }

    static func model(withID id: String) -> CatalogModel? {
        all.first { $0.id == id }
    }
}

/// 模型文件的下载、导入、删除。
@MainActor
final class ModelStore: ObservableObject {

    @Published private(set) var available: [String: URL] = [:]
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var errorText: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        refresh()
    }

    func refresh() {
        var found: [String: URL] = [:]
        for model in ModelCatalog.chatModels {
            let url = modelsDirectory.appendingPathComponent(model.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                found[model.id] = url
            }
        }
        available = found
    }

    func fileURL(for model: CatalogModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    func isDownloaded(_ model: CatalogModel) -> Bool {
        if model.isBuiltin { return true }
        return available[model.id] != nil
    }

    func fileSizeText(_ model: CatalogModel) -> String {
        if model.isBuiltin { return "系统内置" }
        guard let url = available[model.id] else { return model.approxSize }
        var size: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let value = attributes[.size] as? Int64 {
            size = value
        }
        let mb = Double(size) / 1024.0 / 1024.0
        return String(format: "已就绪 %.0f MB", mb)
    }

    func isDownloading(_ model: CatalogModel) -> Bool {
        progress[model.id] != nil
    }

    func download(_ model: CatalogModel) {
        guard !model.isBuiltin, !isDownloaded(model), tasks[model.id] == nil else { return }
        guard let url = URL(string: model.downloadURL) else {
            errorText[model.id] = "下载地址无效。"
            return
        }

        errorText[model.id] = nil
        progress[model.id] = 0

        let target = fileURL(for: model)
        let temp = target.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: temp)

        tasks[model.id] = Task { [weak self] in
            do {
                try await ModelStore.streamDownload(from: url, to: temp) { fraction in
                    Task { @MainActor in
                        self?.progress[model.id] = fraction
                    }
                }
                guard let self else { return }
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temp, to: target)
                await MainActor.run {
                    self.progress[model.id] = nil
                    self.errorText[model.id] = nil
                    self.refresh()
                    self.tasks[model.id] = nil
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.progress[model.id] = nil
                    self.errorText[model.id] = "下载失败：\(error.localizedDescription)"
                    try? FileManager.default.removeItem(at: temp)
                    self.tasks[model.id] = nil
                }
            }
        }
    }

    func cancelDownload(_ model: CatalogModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        progress[model.id] = nil
    }

    func delete(_ model: CatalogModel) {
        guard !model.isBuiltin else { return }
        let url = fileURL(for: model)
        try? FileManager.default.removeItem(at: url)
        refresh()
    }

    /// 从「文件」App 里导入一个 gguf
    func importFile(from url: URL) -> String? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let dest = modelsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            return "导入失败：\(error.localizedDescription)"
        }
        refresh()
        return nil
    }

    /// 已导入的自定义模型（不在目录里的文件）
    func importedFiles() -> [String] {
        let known = Set(ModelCatalog.chatModels.map { $0.fileName })
        let items = (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
        return items.filter { $0.hasSuffix(".gguf") && !known.contains($0) }
    }

    nonisolated private static func streamDownload(
        from url: URL,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let delegate = ModelDownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await delegate.start(session: session, request: request)
    }
}

/// 用系统下载任务，边下边报进度，比逐字节读快得多。
final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {

    /// 便捷入口：直接给地址和目标文件，报进度
    static func download(url: URL,
                         to destination: URL,
                         progress: @escaping (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")

        let delegate = ModelDownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await delegate.start(session: session, request: request)
    }

    /// 探测地址是否存在（用于优先选压缩包、失败退回原文件）
    static func probe(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            return http.statusCode < 400
        }
        return false
    }

    private let destination: URL
    private let progress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastReport: Double = 0
    private var saved = false
    private var saveError: Error?

    init(destination: URL, progress: @escaping (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(session: URLSession, request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        if fraction > 0.02 && fraction - lastReport > 0.01 {
            lastReport = fraction
            progress(fraction)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            saved = true
        } catch {
            saveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil }
        guard let continuation else { return }

        if let error {
            continuation.resume(throwing: error)
            return
        }
        if let saveError {
            continuation.resume(throwing: saveError)
            return
        }
        if let http = task.response as? HTTPURLResponse, http.statusCode >= 400 {
            continuation.resume(throwing: NSError(domain: "ModelStore", code: http.statusCode,
                                                  userInfo: [NSLocalizedDescriptionKey: "服务器返回 \(http.statusCode)"]))
            return
        }
        if saved {
            progress(1.0)
            continuation.resume()
        } else {
            continuation.resume(throwing: NSError(domain: "ModelStore", code: 1,
                                                  userInfo: [NSLocalizedDescriptionKey: "下载没有写出文件"]))
        }
    }
}
