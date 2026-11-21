import Foundation

/// Swift 侧的模型运行器：把阻塞的 C++ 推理放到后台队列。
final class LlamaRunner {

    private let bridge: LlamaBridge

    init(modelURL: URL, contextLength: Int, threadCount: Int) throws {
        var errorText: NSString?
        let cpu = max(2, min(6, Int(ProcessInfo.processInfo.activeProcessorCount)))
        let threads = threadCount > 0 ? threadCount : cpu

        guard let created = LlamaBridge(modelPath: modelURL.path,
                                        contextLength: contextLength,
                                        threadCount: threads,
                                        errorText: &errorText) else {
            let message = errorText.map { $0 as String } ?? "模型加载失败。"
            throw NSError(domain: "LlamaRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        bridge = created
    }

    func cancel() {
        bridge.cancel()
    }

    func countTokens(_ messages: [(role: String, content: String)]) -> Int {
        let array = messages.map { ["role": $0.role, "content": $0.content] }
        return bridge.countTokensForMessages(array)
    }

    /// 同步生成，必须在后台线程调用。
    private func generateSync(messages: [(role: String, content: String)],
                              maxTokens: Int,
                              temperature: Double,
                              onToken: @escaping (String) -> Void) throws -> String {
        var errorText: NSString?
        let array = messages.map { ["role": $0.role, "content": $0.content] }
        let result = bridge.generate(withMessages: array,
                                     maxTokens: maxTokens,
                                     temperature: Float(temperature),
                                     onToken: { piece in onToken(piece) },
                                     errorText: &errorText)
        if let result, !result.isEmpty {
            return result
        }
        let message = errorText.map { $0 as String } ?? "模型没有输出内容。"
        throw NSError(domain: "LlamaRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func generate(messages: [(role: String, content: String)],
                  maxTokens: Int,
                  temperature: Double,
                  onToken: @escaping (String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try self.generateSync(messages: messages,
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
