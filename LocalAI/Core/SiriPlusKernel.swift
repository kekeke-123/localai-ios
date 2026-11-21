import Foundation

/// App 里对外展示的推理内核信息。
/// 说明：底层是在 MIT 协议的 llama.cpp 上做的深度改造版——
/// 加了 KV 前缀复用、加载预热、批处理与采样链精简，
/// 并统一按「Siri Plus 内核」这个名字展示。
enum SiriPlusKernel {
    static let name = "Siri Plus 内核"
    static let version = "1.0"
    static let tagline = "前缀复用 · 预热 · Metal 全量卸载"
    static let base = "基于 llama.cpp（MIT 协议）深度改造"
    static let summary = "\(name) \(version)：\(base)。自带 KV 前缀复用，长对话只算新增内容，第二句起明显更快。"
}
