import Foundation
import SpriteKit
import CoreGraphics

// Shared monster states: Patrol -> Investigate (last known position) ->
// Chase -> Search (last position, then nearby points) -> Patrol.
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

// The contract both hunters follow. Batch A ships the Death Angel;
// Batch B adds the Demogorgon (sight) on this same protocol.
protocol MonsterAI: AnyObject {
    var state: MonsterState { get }
    var lastKnownPosition: CGPoint? { get }
    var node: SKNode { get }
    func onNoise(_ event: NoiseEvent)
    func updateAI(dt: TimeInterval, now: TimeInterval)
    func recordHabit(zone: String)
}

// Base class carrying the shared state and the habit tracking:
// if the player makes loud noise / uses strong light in the same zone
// 3+ times, that zone becomes "favored" — monsters bias their patrol
// toward it (used by Batch B/C patrol logic).
class MonsterBase: MonsterAI {
    var state: MonsterState = .patrol
    var lastKnownPosition: CGPoint?
    let node: SKNode

    private(set) var habitCounts: [String: Int] = [:]

    init(node: SKNode) {
        self.node = node
    }

    func recordHabit(zone: String) {
        guard !zone.isEmpty else { return }
        habitCounts[zone, default: 0] += 1
    }

    // Zones the player has been careless in 3 or more times.
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
}
