import Foundation
import CoreGraphics

// How the player is moving, decided by joystick push + sprint button:
// gentle push = sneak (silent), full push = walk, sprint button = run.
enum MovementMode: String {
    case idle
    case sneak
    case walk
    case run

    var speed: CGFloat {
        switch self {
        case .idle: return 0
        case .sneak: return 72
        case .walk: return 152
        case .run: return 268
        }
    }

    var arabicName: String {
        switch self {
        case .idle: return "واقف"
        case .sneak: return "تسلل"
        case .walk: return "مشي"
        case .run: return "ركض"
        }
    }
}

// Pure movement + noise model for the player. No SpriteKit here, so the
// numbers are easy to tune and can never crash on view state.
final class PlayerController {
    private(set) var position: CGPoint
    private(set) var mode: MovementMode = .idle
    private(set) var facing: CGPoint = CGPoint(x: 1, y: 0)
    let radius: CGFloat = 16

    init(start: CGPoint) {
        position = start.isSafeFinite ? start : .zero
    }

    // input: joystick vector, magnitude 0...1 (already clamped by the scene).
    func update(dt: TimeInterval, input: CGPoint, sprint: Bool, worldBounds: CGRect) {
        guard dt > 0, dt.isFinite else { return }
        let magnitude = min(input.length(), 1)
        guard magnitude > 0.12 else {
            mode = .idle
            return
        }
        let direction = input.normalizedOrZero()
        guard direction != .zero else {
            mode = .idle
            return
        }
        facing = direction

        if sprint {
            mode = .run
        } else if magnitude < 0.45 {
            mode = .sneak
        } else {
            mode = .walk
        }

        let speedFactor: CGFloat
        switch mode {
        case .sneak: speedFactor = min(magnitude / 0.45, 1)
        case .walk: speedFactor = magnitude
        case .run: speedFactor = 1
        case .idle: speedFactor = 0
        }

        let step = mode.speed * speedFactor * CGFloat(dt)
        let next = CGPoint(
            x: position.x + direction.x * step,
            y: position.y + direction.y * step
        )
        let inset = worldBounds.insetBy(dx: radius, dy: radius)
        position = next.isSafeFinite ? next.clamped(to: inset) : position
    }

    // Noise radius (in points) for one footstep burst on a surface.
    // 0 = completely silent. Glass is dangerous even when sneaking.
    func noiseRadius(on surface: SurfaceType) -> CGFloat {
        switch (mode, surface) {
        case (.idle, _):
            return 0
        case (.sneak, .carpet):
            return 0
        case (.sneak, .concrete):
            return 25
        case (.sneak, .metal):
            return 45
        case (.sneak, .glass):
            return 175
        case (.walk, .carpet):
            return 55
        case (.walk, .concrete):
            return 90
        case (.walk, .metal):
            return 150
        case (.walk, .glass):
            return 230
        case (.run, .carpet):
            return 150
        case (.run, .concrete):
            return 210
        case (.run, .metal):
            return 280
        case (.run, .glass):
            return 340
        }
    }

    // Seconds between footstep noise bursts per mode.
    var noiseInterval: TimeInterval {
        switch mode {
        case .idle: return 999
        case .sneak: return 0.45
        case .walk: return 0.35
        case .run: return 0.28
        }
    }
}
