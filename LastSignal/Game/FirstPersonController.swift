import Foundation
import CoreGraphics

// First-person movement on the floor plane (x = world X, y = world Z,
// units are meters). Heading convention: the player rig node's
// eulerAngles.y == yaw, and the camera forward on the floor plane is
// (-sin(yaw), -cos(yaw)) — matching SceneKit's -Z camera direction.
//
// Same feel as the 2D build, re-scaled to meters:
// gentle joystick push = sneak (silent), full push = walk,
// sprint button held = run (loud).
final class FirstPersonController {
    private(set) var position: CGPoint // (x, z) in meters
    private(set) var yaw: CGFloat = .pi // facing +Z at spawn
    private(set) var pitch: CGFloat = 0
    private(set) var mode: MovementMode = .idle
    let radius: CGFloat = 0.35
    let eyeHeight: CGFloat = 1.62

    init(start: CGPoint) {
        position = start.isSafeFinite ? start : .zero
    }

    var forward: CGPoint {
        CGPoint(x: -sin(yaw), y: -cos(yaw))
    }

    var right: CGPoint {
        CGPoint(x: cos(yaw), y: -sin(yaw))
    }

    // Instant reposition (entering/leaving a locker). Guarded like all
    // movement in this controller.
    func teleport(to point: CGPoint) {
        guard point.isSafeFinite else { return }
        position = point
        mode = .idle
    }

    // Faces the rig along a floor-plane direction.
    func face(direction: CGPoint) {
        let unit = direction.normalizedOrZero()
        guard unit != .zero else { return }
        yaw = atan2(-unit.x, -unit.y)
        pitch = 0
    }

    // Look input: accumulated drag deltas in points.
    func applyLook(dx: CGFloat, dy: CGFloat) {
        guard dx.isSafeFinite, dy.isSafeFinite else { return }
        let step = 0.0045 * GameSettings.lookSensitivity
        yaw -= dx * step
        pitch -= dy * step
        pitch = min(max(pitch, -1.1), 1.1)
    }

    // move: (x = strafe right +, y = forward +), magnitude 0...1.
    // walls: solid rects on the floor plane. Axis-separated collision:
    // try X, then Z, so the player slides along walls instead of sticking.
    func update(dt: TimeInterval, move: CGPoint, sprint: Bool,
                walls: [CGRect], worldBounds: CGRect) {
        guard dt > 0, dt.isFinite else { return }
        let magnitude = min(move.length(), 1)
        guard magnitude > 0.12 else {
            mode = .idle
            return
        }
        let input = move.normalizedOrZero()
        guard input != .zero else {
            mode = .idle
            return
        }

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

        let speed = mode.speedMeters * speedFactor
        let delta = CGPoint(
            x: (right.x * input.x + forward.x * input.y) * speed * CGFloat(dt),
            y: (right.y * input.x + forward.y * input.y) * speed * CGFloat(dt)
        )

        // Axis-separated move with circle-vs-rect collision.
        var next = position
        let tryX = CGPoint(x: position.x + delta.x, y: position.y)
        if !collides(at: tryX, walls: walls) {
            next = tryX
        }
        let tryZ = CGPoint(x: next.x, y: position.y + delta.y)
        if !collides(at: tryZ, walls: walls) {
            next = tryZ
        }
        let inset = worldBounds.insetBy(dx: radius, dy: radius)
        position = next.isSafeFinite ? next.clamped(to: inset) : position
    }

    private func collides(at point: CGPoint, walls: [CGRect]) -> Bool {
        for wall in walls {
            // Closest point on the rect to the circle center.
            let closestX = min(max(point.x, wall.minX), wall.maxX)
            let closestY = min(max(point.y, wall.minY), wall.maxY)
            let d = SafeMath.distance(point, CGPoint(x: closestX, y: closestY))
            if d < radius {
                return true
            }
        }
        return false
    }

    // Noise radius (meters) for one footstep burst on a surface.
    // Glass is dangerous even when sneaking.
    func noiseRadius(on surface: SurfaceType) -> CGFloat {
        switch (mode, surface) {
        case (.idle, _):
            return 0
        case (.sneak, .carpet):
            return 0
        case (.sneak, .concrete):
            return 1.0
        case (.sneak, .metal):
            return 2.0
        case (.sneak, .glass):
            return 9
        case (.walk, .carpet):
            return 3
        case (.walk, .concrete):
            return 5
        case (.walk, .metal):
            return 8
        case (.walk, .glass):
            return 12
        case (.run, .carpet):
            return 8
        case (.run, .concrete):
            return 11
        case (.run, .metal):
            return 15
        case (.run, .glass):
            return 18
        }
    }

    var noiseInterval: TimeInterval {
        switch mode {
        case .idle: return 999
        case .sneak: return 0.5
        case .walk: return 0.38
        case .run: return 0.3
        }
    }
}
