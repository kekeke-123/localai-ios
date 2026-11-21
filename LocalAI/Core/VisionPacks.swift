import Foundation
import Combine

struct PackFile: Hashable {
    let fileName: String      // 解出来的文件名
    let gzURL: String         // 压缩包直链（可为空）
    let rawURL: String        // 未压缩直链（兜底）
    let bytes: Int64
}

struct VisionPack: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let sizeText: String
    let modelFileName: String
    let mmprojFileName: String
    let files: [PackFile]

    static func == (lhs: VisionPack, rhs: VisionPack) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum VisionPacks {

    private static let release = "https://github.com/kekeke-123/localai-ios/releases/download/models"
    private static let mirror = "https://hf-mirror.com/ggml-org"

    /// 小号：看着快、内存压力小，但描述比较简单
    static let small = VisionPack(
        id: "vlm.smolvlm-256m",
        name: "视觉模型·小",
        detail: "SmolVLM 256M（8 位量化）。能看懂画面在讲什么、认字、数个数，回答比较简短。",
        sizeText: "约 279 MB",
        modelFileName: "SmolVLM-256M-Instruct-Q8_0.gguf",
        mmprojFileName: "mmproj-SmolVLM-256M-Instruct-Q8_0.gguf",
        files: [
            PackFile(fileName: "SmolVLM-256M-Instruct-Q8_0.gguf",
                     gzURL: "\(release)/SmolVLM-256M-Instruct-Q8_0.gguf.gz",
                     rawURL: "\(mirror)/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf",
                     bytes: 175_054_528),
            PackFile(fileName: "mmproj-SmolVLM-256M-Instruct-Q8_0.gguf",
                     gzURL: "\(release)/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf.gz",
                     rawURL: "\(mirror)/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf",
                     bytes: 103_769_856)
        ]
    )

    /// 中号：描述更细，占内存更多
    static let medium = VisionPack(
        id: "vlm.smolvlm-500m",
        name: "视觉模型·中",
        detail: "SmolVLM 500M（8 位量化）。细节更多、句子更连贯，代价是更吃内存、更慢一点。",
        sizeText: "约 546 MB",
        modelFileName: "SmolVLM-500M-Instruct-Q8_0.gguf",
        mmprojFileName: "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf",
        files: [
            PackFile(fileName: "SmolVLM-500M-Instruct-Q8_0.gguf",
                     gzURL: "\(release)/SmolVLM-500M-Instruct-Q8_0.gguf.gz",
                     rawURL: "\(mirror)/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf",
                     bytes: 436_806_912),
            PackFile(fileName: "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf",
                     gzURL: "\(release)/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf.gz",
                     rawURL: "\(mirror)/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf",
                     bytes: 108_783_360)
        ]
    )

    static var all: [VisionPack] { [small, medium] }
}

/// 视觉模型包的下载 → 后台解压 → 注册
@MainActor
final class VisionPackStore: ObservableObject {

    struct Installed {
        let modelURL: URL
        let mmprojURL: URL
    }

    @Published private(set) var installed: [String: Installed] = [:]
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var statusText: [String: String] = [:]
    @Published private(set) var errorText: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    var packsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VisionModels", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() { refresh() }

    func refresh() {
        var found: [String: Installed] = [:]
        for pack in VisionPacks.all {
            let model = packsDirectory.appendingPathComponent(pack.modelFileName)
            let mmproj = packsDirectory.appendingPathComponent(pack.mmprojFileName)
            if FileManager.default.fileExists(atPath: model.path),
               FileManager.default.fileExists(atPath: mmproj.path) {
                found[pack.id] = Installed(modelURL: model, mmprojURL: mmproj)
            }
        }
        installed = found
    }

    func isInstalled(_ pack: VisionPack) -> Bool { installed[pack.id] != nil }
    func isWorking(_ pack: VisionPack) -> Bool { tasks[pack.id] != nil }

    func install(_ pack: VisionPack) {
        guard tasks[pack.id] == nil, !isInstalled(pack) else { return }
        errorText[pack.id] = nil
        progress[pack.id] = 0

        tasks[pack.id] = Task { [weak self] in
            guard let self else { return }
            var doneBytes: Int64 = 0
            let totalBytes = max(1, pack.files.reduce(Int64(0)) { $0 + $1.bytes })

            for file in pack.files {
                let final = self.packsDirectory.appendingPathComponent(file.fileName)
                if FileManager.default.fileExists(atPath: final.path) {
                    doneBytes += file.bytes
                    continue
                }

                let temp = self.packsDirectory.appendingPathComponent(file.fileName + ".part")
                try? FileManager.default.removeItem(at: temp)

                await MainActor.run { self.statusText[pack.id] = "下载 \(file.fileName)…" }

                let url = await self.pickURL(for: file)
                guard let url else {
                    await MainActor.run {
                        self.errorText[pack.id] = "找不到 \(file.fileName) 的下载地址。"
                        self.progress[pack.id] = nil
                        self.statusText[pack.id] = nil
                        self.tasks[pack.id] = nil
                    }
                    return
                }

                do {
                    try await ModelDownloadDelegate.download(url: url, to: temp) { fraction in
                        let base = Double(doneBytes) / Double(totalBytes)
                        let span = Double(file.bytes) / Double(totalBytes)
                        let value = base + span * fraction
                        Task { @MainActor in self.progress[pack.id] = min(0.98, value) }
                    }
                } catch {
                    await MainActor.run {
                        self.errorText[pack.id] = "下载失败：\(error.localizedDescription)"
                        self.progress[pack.id] = nil
                        self.statusText[pack.id] = nil
                        self.tasks[pack.id] = nil
                    }
                    return
                }

                // 后台解压（如果是压缩包）
                if url.pathExtension == "gz" {
                    await MainActor.run { self.statusText[pack.id] = "后台解压 \(file.fileName)…" }
                    let ok = await Task.detached(priority: .utility) { () -> (Bool, String?) in
                        var err: NSString?
                        let success = GzHelper.gunzipFile(atPath: temp.path,
                                                          toPath: final.path,
                                                          progress: { fraction in
                            let base = Double(doneBytes) / Double(totalBytes)
                            let span = Double(file.bytes) / Double(totalBytes)
                            let value = base + span * (0.3 + 0.7 * fraction)
                            Task { @MainActor in self.progress[pack.id] = min(0.99, value) }
                        },
                                                          errorText: &err)
                        return (success, err.map { $0 as String })
                    }.value

                    try? FileManager.default.removeItem(at: temp)

                    if !ok.0 {
                        await MainActor.run {
                            self.errorText[pack.id] = ok.1 ?? "解压失败。"
                            self.progress[pack.id] = nil
                            self.statusText[pack.id] = nil
                            self.tasks[pack.id] = nil
                        }
                        return
                    }
                } else {
                    try? FileManager.default.removeItem(at: final)
                    try? FileManager.default.moveItem(at: temp, to: final)
                }

                doneBytes += file.bytes
            }

            await MainActor.run {
                self.progress[pack.id] = nil
                self.statusText[pack.id] = nil
                self.refresh()
                self.tasks[pack.id] = nil
            }
        }
    }

    private func pickURL(for file: PackFile) async -> URL? {
        if !file.gzURL.isEmpty {
            if let probe = URL(string: file.gzURL),
               let head = try? await ModelDownloadDelegate.probe(probe), head {
                return probe
            }
        }
        return URL(string: file.rawURL)
    }

    func cancel(_ pack: VisionPack) {
        tasks[pack.id]?.cancel()
        tasks[pack.id] = nil
        progress[pack.id] = nil
        statusText[pack.id] = nil
    }

    func remove(_ pack: VisionPack) {
        for file in pack.files {
            try? FileManager.default.removeItem(at: packsDirectory.appendingPathComponent(file.fileName))
        }
        refresh()
    }
}
