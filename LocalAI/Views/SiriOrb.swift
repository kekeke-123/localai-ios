import SwiftUI

/// 仿 iOS 26 Siri 的彩色光球：彩色光带缓慢旋转 + 内部光斑游动
struct SiriOrb: View {

    var active: Bool = false

    private static let colors: [Color] = [
        Color(red: 0.42, green: 0.36, blue: 1.00),
        Color(red: 0.92, green: 0.36, blue: 0.78),
        Color(red: 1.00, green: 0.58, blue: 0.32),
        Color(red: 0.32, green: 0.86, blue: 0.96),
        Color(red: 0.42, green: 0.36, blue: 1.00)
    ]

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle()
                        .fill(Color.black)

                    Circle()
                        .fill(AngularGradient(gradient: Gradient(colors: Self.colors),
                                              center: .center,
                                              angle: .degrees(t * 22)))
                        .blur(radius: d * 0.05)

                    ForEach(0..<4, id: \.self) { i in
                        let phase = t * 0.5 + Double(i) * 1.7
                        Circle()
                            .fill(Self.colors[i].opacity(0.9))
                            .frame(width: d * 0.62, height: d * 0.62)
                            .offset(x: cos(phase) * d * 0.15,
                                    y: sin(phase * 1.2) * d * 0.15)
                            .blur(radius: d * 0.16)
                    }

                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.35), Color.clear],
                                             center: UnitPoint(x: 0.38, y: 0.30),
                                             startRadius: 0,
                                             endRadius: d * 0.55))
                        .blendMode(.plusLighter)
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .frame(width: d, height: d)
                .scaleEffect(scale(t))
                .shadow(color: Self.colors[0].opacity(0.45), radius: d * 0.18)
                .shadow(color: Self.colors[1].opacity(0.35), radius: d * 0.10)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    private func scale(_ t: TimeInterval) -> CGFloat {
        if active {
            return 1.0 + CGFloat(sin(t * 3.2)) * 0.035
        }
        return 0.94 + CGFloat(sin(t * 1.1)) * 0.025
    }
}

/// 底部的液态玻璃条（iOS 26 Liquid Glass 风）
struct GlassBar<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(7)
            .glassEffect(.regular, in: .capsule)
    }
}
