import Foundation

/// 视觉语言模型运行器
final class VlmRunner {

    private let bridge: MtmdBridge

    init(modelURL: URL, mmprojURL: URL, contextLength: Int, threadCount: Int) throws {
        var errorText: NSString?
        let cpu = max(2, min(6, Int(ProcessInfo.processInfo.activeProcessorCount)))
        let threads = threadCount > 0 ? threadCount : cpu

        guard let created = MtmdBridge(modelPath: modelURL.path,
                                       mmprojPath: mmprojURL.path,
                                       contextLength: contextLength,
                                       threadCount: threads,
                                       errorText: &errorText) else {
            let message = errorText.map { $0 as String } ?? "视觉模型加载失败。"
            throw NSError(domain: "VlmRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        bridge = created
    }

    func cancel() { bridge.cancel() }

    private func runSync(imageData: Data,
                         question: String,
                         maxTokens: Int,
                         temperature: Double,
                         onToken: @escaping (String) -> Void) throws -> String {
        var errorText: NSString?
        let result = bridge.describeImageData(imageData,
                                              question: question,
                                              maxTokens: maxTokens,
                                              temperature: Float(temperature),
                                              onToken: { piece in onToken(piece) },
                                              errorText: &errorText)
        if let result, !result.isEmpty { return result }
        let message = errorText.map { $0 as String } ?? "模型没有输出内容。"
        throw NSError(domain: "VlmRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func describe(imageData: Data,
                  question: String,
                  maxTokens: Int,
                  temperature: Double,
                  onToken: @escaping (String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try self.runSync(imageData: imageData,
                                                question: question,
                                                maxTokens: maxTokens,
                                                temperature: temperature,
                                                onToken: onToken)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
