import Foundation
import SceneKit
import CoreGraphics

// Shared monster states (same design as the 2D build):
// Patrol -> Investigate (last known position) -> Chase ->
// Search (last position, then nearby points) -> Patrol.
// Monsters remember a LAST KNOWN position only — never the player's
// true position.
enum MonsterState: String {
    case dormant
    case patrol
    case investigate
    case chase
    case search

    var arabicName: String {
        switch self {
        case .dormant: return "نائم"
        case .patrol: return "دورية"
        case .investigate: return "يتحقق"
        case .chase: return "مطاردة"
        case .search: return "يبحث"
        }
    }
}

// The contract both hunters follow in the first-person build.
// Positions are floor-plane points (x = world X, y = world Z, meters).
protocol MonsterAI3D: AnyObject {
    var state: MonsterState { get }
    var lastKnownPosition: CGPoint? { get }
    var node: SCNNode { get }
    var floorPosition: CGPoint { get }
    func onNoise(_ event: NoiseEvent)
    func updateAI(dt: TimeInterval, now: TimeInterval)
    func recordHabit(zone: String)
}

// Base class: shared state + habit tracking (a zone where the player is
// loud 3+ times becomes favored and biases later patrols).
class MonsterBase3D: MonsterAI3D {
    var state: MonsterState = .patrol
    var lastKnownPosition: CGPoint?
    // Difficulty scaling per floor (set by the scene factory).
    var speedScale: CGFloat = 1
    let node: SCNNode

    private(set) var habitCounts: [String: Int] = [:]

    init(node: SCNNode) {
        self.node = node
    }

    var floorPosition: CGPoint {
        CGPoint(x: CGFloat(node.position.x), y: CGFloat(node.position.z))
    }

    func setFloorPosition(_ point: CGPoint) {
        node.position = SCNVector3(Float(point.x), node.position.y, Float(point.y))
    }

    func recordHabit(zone: String) {
        guard !zone.isEmpty else { return }
        habitCounts[zone, default: 0] += 1
    }

    func favoredZones() -> [String] {
        habitCounts.filter { $0.value >= 3 }.map { $0.key }
    }

    func habitCount(zone: String) -> Int {
        habitCounts[zone] ?? 0
    }

    func onNoise(_ event: NoiseEvent) {
        // Overridden by each hunter with its own sense.
    }

    func updateAI(dt: TimeInterval, now: TimeInterval) {
        // Overridden by each hunter.
    }

    // MARK: - Path-following movement (shared by both hunters)

    // Pathfinding grid for this floor, set by the scene factory.
    // Monsters route around walls to reach their target — they
    // track the player through rooms and corridors, never through
    // a wall (his explicit rule).
    var pathfinder: PathGrid?
    private var path: [CGPoint] = []
    private var pathGoal: CGPoint?

    func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let current = floorPosition
        var destination = target

        if let grid = pathfinder {
            let goalMoved = pathGoal.map { SafeMath.distance($0, target) > 1.2 } ?? true
            if goalMoved || path.isEmpty {
                let found = grid.findPath(from: current, to: target)
                if !found.isEmpty {
                    path = found
                    pathGoal = target
                }
            }
            if let next = path.first {
                destination = next
                if SafeMath.distance(current, next) < 0.3 {
                    path.removeFirst()
                }
            }
        }

        let step = speed * speedScale * CGFloat(dt)
        var next = SafeMath.move(current, toward: destination, maxStep: step)

        // Never clip through a wall, even on a direct step: slide
        // along one axis, and force a repath next frame.
        if let grid = pathfinder, grid.isBlocked(next) {
            let xOnly = CGPoint(x: next.x, y: current.y)
            let yOnly = CGPoint(x: current.x, y: next.y)
            if !grid.isBlocked(xOnly) {
                next = xOnly
            } else if !grid.isBlocked(yOnly) {
                next = yOnly
            } else {
                next = current
            }
            path = []
        }

        setFloorPosition(next)
        // Face the movement direction (the model's forward on the
        // floor plane is (-sin(y), -cos(y))).
        let delta = CGPoint(x: next.x - current.x, y: next.y - current.y)
        if delta.length() > 0.001 {
            node.eulerAngles.y = Float(atan2(-delta.x, -delta.y))
        }
    }
}
