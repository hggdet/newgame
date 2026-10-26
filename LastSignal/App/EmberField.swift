import SwiftUI

// Ambient flying sparks over the main menu (his request): small
// glowing embers that rise, drift and flicker above the key art.
// Pure SwiftUI Canvas on a timeline — cheap, deterministic, and it
// can never fail: no assets, no timers to leak, no state.
struct EmberField: View {
    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                let t = context.date.timeIntervalSinceReferenceDate
                guard size.width > 10, size.height > 10 else { return }
                for i in 0..<44 {
                    let seed = Double(i + 1) * 137.508
                    let r1 = frac(sin(seed) * 43758.5453)
                    let r2 = frac(sin(seed * 1.7) * 28001.8384)
                    let r3 = frac(sin(seed * 2.3) * 12543.1234)

                    // Rise from bottom to top, looping per particle.
                    let speed = 16 + r2 * 26                    // points per second
                    let travel = size.height + 48
                    let risen = (t * speed + r1 * travel).truncatingRemainder(dividingBy: travel)
                    let y = size.height + 24 - risen
                    let sway = sin(t * (0.4 + r3 * 0.5) + seed) * (10 + r3 * 16)
                    let x = r1 * size.width + sway

                    // Flicker: sparks pulse as they fly.
                    let flicker = 0.35 + 0.65 * abs(sin(t * (1.6 + r2 * 2.4) + seed * 3))
                    let core = 1.3 + r3 * 2.1
                    let hue = 0.07 + r2 * 0.035                  // orange range

                    let glowRect = CGRect(x: x - core * 3, y: y - core * 3,
                                          width: core * 6, height: core * 6)
                    graphics.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(Color(hue: hue, saturation: 0.95,
                                           brightness: 0.9, opacity: 0.10 * flicker)))
                    let coreRect = CGRect(x: x - core, y: y - core,
                                          width: core * 2, height: core * 2)
                    graphics.fill(
                        Path(ellipseIn: coreRect),
                        with: .color(Color(hue: hue, saturation: 0.9,
                                           brightness: 1.0, opacity: 0.85 * flicker)))
                }
            }
        }
    }

    private func frac(_ value: Double) -> Double {
        value - floor(value)
    }
}
