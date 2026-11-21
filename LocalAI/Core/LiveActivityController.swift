import Foundation
import ActivityKit

/// 灵动岛 / 锁屏实时活动：模型在思考时显示进度，结束就收起
@MainActor
final class LiveActivityController {

    static let shared = LiveActivityController()

    private var activity: Activity<SiriActivityAttributes>?
    private var updateCount = 0

    private init() {}

    func start(title: String = "小模正在想") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil {
            update(phase: "正在思考", detail: "本地模型推理中", progress: 0.06)
            return
        }
        let attributes = SiriActivityAttributes(title: title)
        let content = ActivityContent(
            state: SiriActivityAttributes.ContentState(phase: "正在思考", detail: "本地模型推理中", progress: 0.06),
            staleDate: nil
        )
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(phase: String, detail: String, progress: Double) {
        guard let activity else { return }
        updateCount += 1
        let state = SiriActivityAttributes.ContentState(phase: phase, detail: detail, progress: progress)
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    /// 每出几个字更新一次，太频繁会被系统限流
    func streamTick(text: String, tokens: Int, total: Int) {
        guard activity != nil, tokens % 6 == 0 else { return }
        let tail = String(text.suffix(40))
        let ratio = total > 0 ? min(0.95, Double(tokens) / Double(total)) : 0.3
        update(phase: "正在回答", detail: tail, progress: ratio)
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(
            state: SiriActivityAttributes.ContentState(phase: "已完成", detail: "", progress: 1),
            staleDate: nil
        )
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }
}
