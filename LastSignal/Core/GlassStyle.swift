import SwiftUI

// Shape-aware Liquid Glass — the same recipe as his other apps:
// - iOS 26+: Apple's real glassEffect — a true pill for wide buttons,
//   a circle for round ones, a panel for cards.
// - Older systems: ultraThinMaterial + a top-light sheen + a soft shadow.
//   NO white border (his standing rule: «حقيقي بدون حدود»).
struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                if let tint = tint {
                    content.glassEffect(.regular.tint(tint.opacity(0.35)).interactive(), in: shape)
                } else {
                    content.glassEffect(.regular.interactive(), in: shape)
                }
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
        }
    }
}

extension View {
    // Wide buttons and bars.
    func glassPill(tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: Capsule(), tint: tint))
    }

    // Round buttons (joystick, sprint, icon buttons).
    func glassCircle(tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: Circle(), tint: tint))
    }

    // Cards and panels.
    func glassPanel(radius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: RoundedRectangle(cornerRadius: radius), tint: tint))
    }
}
