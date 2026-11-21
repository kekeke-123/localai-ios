import ActivityKit
import WidgetKit
import SwiftUI

/// 小号的彩色光球（灵动岛里用，独立于 App 模块）
private struct MiniOrb: View {
    var size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.42, green: 0.36, blue: 1),
                    Color(red: 0.92, green: 0.36, blue: 0.78),
                    Color(red: 1, green: 0.58, blue: 0.32),
                    Color(red: 0.32, green: 0.86, blue: 0.96),
                    Color(red: 0.42, green: 0.36, blue: 1)
                ]),
                center: .center
            ))
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.92, green: 0.36, blue: 0.78).opacity(0.6), radius: size * 0.4)
    }
}

struct SiriLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SiriActivityAttributes.self) { context in
            // 锁屏 / 通知中心
            HStack(spacing: 14) {
                MiniOrb(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.phase)
                        .font(.headline)
                    Text(context.state.detail.isEmpty ? "在本机运行，不上传" : context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniOrb(size: 28).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phase)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("本机").font(.caption2).foregroundStyle(.secondary).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if context.state.detail.isEmpty {
                            Text("小模正在这台手机上思考…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(context.state.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                        if context.state.progress > 0 {
                            ProgressView(value: min(1, max(0, context.state.progress)))
                                .tint(Color(red: 0.92, green: 0.36, blue: 0.78))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                MiniOrb(size: 16)
            } compactTrailing: {
                Image(systemName: "waveform")
                    .foregroundStyle(Color(red: 0.92, green: 0.36, blue: 0.78))
            } minimal: {
                MiniOrb(size: 16)
            }
            .widgetURL(URL(string: "localai://chat"))
            .keylineTint(Color(red: 0.92, green: 0.36, blue: 0.78))
        }
    }
}
