import Foundation
import CoreGraphics

// Zero/NaN-safe vector helpers. Every movement and AI calculation in the
// game goes through these so a zero-length vector can never produce NaN
// positions (a classic SpriteKit crash/corruption source).

extension CGFloat {
    var isSafeFinite: Bool { isFinite && !isNaN }
}

extension CGPoint {
    var isSafeFinite: Bool { x.isSafeFinite && y.isSafeFinite }

    func length() -> CGFloat {
        let l = sqrt(x * x + y * y)
        return l.isSafeFinite ? l : 0
    }

    // Returns .zero for zero-length or non-finite vectors instead of NaN.
    func normalizedOrZero() -> CGPoint {
        let l = length()
        guard l > 0.0001 else { return .zero }
        let result = CGPoint(x: x / l, y: y / l)
        return result.isSafeFinite ? result : .zero
    }

    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

enum SafeMath {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let d = sqrt(dx * dx + dy * dy)
        return d.isSafeFinite ? d : 0
    }

    // Moves `point` toward `target` by at most `maxStep`, never overshooting
    // and never producing NaN. Returns the new point.
    static func move(_ point: CGPoint, toward target: CGPoint, maxStep: CGFloat) -> CGPoint {
        guard maxStep > 0, point.isSafeFinite, target.isSafeFinite else { return point }
        let delta = CGPoint(x: target.x - point.x, y: target.y - point.y)
        let dist = delta.length()
        if dist <= maxStep || dist <= 0.0001 { return target }
        let unit = delta.normalizedOrZero()
        return CGPoint(x: point.x + unit.x * maxStep, y: point.y + unit.y * maxStep)
    }

    // True when `a` is within `radius` of `b` (safe for any input).
    static func isWithin(_ a: CGPoint, _ b: CGPoint, radius: CGFloat) -> Bool {
        guard radius >= 0 else { return false }
        return distance(a, b) <= radius
    }
}
