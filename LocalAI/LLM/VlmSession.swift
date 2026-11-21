import Foundation
import UIKit
import Combine

@MainActor
final class VlmSession: ObservableObject {

    @Published var answer: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusText: String = ""
    @Published var lastError: String?
    @Published private(set) var loadedPackID: String?

    private var runner: VlmRunner?

    var hasModel: Bool { runner != nil }

    func unload() {
        runner?.cancel()
        runner = nil
        loadedPackID = nil
    }

    func stop() {
        runner?.cancel()
        statusText = "已停止"
    }

    /// 图片先降采样再送进模型，省内存也更快
    private static func prepareImageData(_ image: UIImage, maxSide: CGFloat = 1024) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: 0.8) }
        let scale = min(1, maxSide / max(size.width, size.height))
        if scale >= 1 {
            return image.jpegData(compressionQuality: 0.85)
        }
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    func describe(image: UIImage,
                  question: String,
                  pack: VisionPack,
                  packStore: VisionPackStore,
                  settings: AppSettings) async {
        guard !isRunning else { return }
        guard let installed = packStore.installed[pack.id] else {
            lastError = "这个视觉模型还没装好，先去「模型」页下载。"
            return
        }

        lastError = nil
        answer = ""
        isRunning = true
        statusText = ""

        defer {
            isRunning = false
            statusText = ""
        }

        do {
            if loadedPackID != pack.id || runner == nil {
                unload()
                statusText = "正在加载视觉模型…"
                runner = try VlmRunner(modelURL: installed.modelURL,
                                       mmprojURL: installed.mmprojURL,
                                       contextLength: max(2048, settings.contextLength),
                                       threadCount: 0)
                loadedPackID = pack.id
                statusText = ""
            }

            guard let runner else {
                lastError = "视觉模型没有加载成功。"
                return
            }

            guard let data = VlmSession.prepareImageData(image) else {
                lastError = "这张图片转换失败。"
                return
            }

            let prompt = question.isEmpty ? "简单描述这张图里有什么，要具体一点。" : question
            let result = try await runner.describe(imageData: data,
                                                   question: prompt,
                                                   maxTokens: min(settings.maxTokens, 400),
                                                   temperature: settings.temperature) { piece in
                Task { @MainActor in
                    self.answer += piece
                }
            }
            answer = result
        } catch {
            lastError = error.localizedDescription
        }
    }
}
