import Foundation
import SceneKit
import CoreGraphics

// The SIGHT hunter (first-person build). It detects the player ONLY via
// light: while the player's flashlight is on, being inside the light's
// detection range betrays him. In total darkness it detects only a player
// directly adjacent (< 1.2m). It ignores noise completely.
// Slow and confident — slower than the sound hunter, but relentless.
// Its body is an original design (see MonsterModels.sightHunter()).
final class LightHunter3D: MonsterBase3D {
    var waypoints: [CGPoint]

    private var waypointIndex = 0
    private var lastSeenTime: TimeInterval = -10_000
    private var searchPoints: [CGPoint] = []
    private var searchIndex = 0

    // Detection range while the player's light is on (steady level).
    // Batch B' scales this by light level: flash small, strong large.
    var lightDetectionRange: CGFloat = 9
    let darkDetectionRange: CGFloat = 1.2

    private let patrolSpeed: CGFloat = 0.9
    private let investigateSpeed: CGFloat = 1.55
    private let chaseSpeed: CGFloat = 2.35
    private let searchSpeed: CGFloat = 1.1

    init(spawn: CGPoint, waypoints: [CGPoint]) {
        self.waypoints = waypoints.filter { $0.isSafeFinite }
        super.init(node: MonsterModels.sightHunter())
        setFloorPosition(spawn.isSafeFinite ? spawn : .zero)
        state = .patrol
    }

    // Noise means nothing to this hunter (base onNoise stays empty).

    // Called every frame by the scene controller with the player's truth —
    // the hunter itself only ever stores the last SEEN position.
    func sense(playerPosition: CGPoint, lightOn: Bool, now: TimeInterval) {
        let distance = SafeMath.distance(floorPosition, playerPosition)
        let seen = (lightOn && distance <= lightDetectionRange)
            || distance <= darkDetectionRange
        guard seen else { return }

        let firstSight = state != .chase && state != .investigate
        lastKnownPosition = playerPosition
        lastSeenTime = now
        state = distance < 4 ? .chase : .investigate
        if firstSight {
            AudioManager.shared.play(.sightHunterScreech, at: floorPosition)
        }
    }

    override func updateAI(dt: TimeInterval, now: TimeInterval) {
        guard dt > 0, dt.isFinite else { return }

        switch state {
        case .dormant:
            state = .patrol // Sight hunters never sleep in this design.

        case .patrol:
            guard !waypoints.isEmpty else { return }
            let target = waypoints[waypointIndex % waypoints.count]
            moveToward(target, speed: patrolSpeed, dt: dt)
            if SafeMath.distance(floorPosition, target) < 0.35 {
                waypointIndex += 1
            }

        case .investigate:
            guard let target = lastKnownPosition else {
                state = .patrol
                return
            }
            moveToward(target, speed: investigateSpeed, dt: dt)
            if SafeMath.distance(floorPosition, target) < 0.35 {
                beginSearch(around: target)
            } else if now - lastSeenTime > 5 {
                beginSearch(around: target)
            }

        case .chase:
            guard let target = lastKnownPosition else {
                state = .search
                return
            }
            moveToward(target, speed: chaseSpeed, dt: dt)
            if now - lastSeenTime > 5 {
                beginSearch(around: target)
            }

        case .search:
            guard searchIndex < searchPoints.count else {
                state = .patrol
                return
            }
            let target = searchPoints[searchIndex]
            moveToward(target, speed: searchSpeed, dt: dt)
            if SafeMath.distance(floorPosition, target) < 0.35 {
                searchIndex += 1
            }
        }
    }

    private func beginSearch(around center: CGPoint) {
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: -1.8, y: 0),
            CGPoint(x: 1.8, y: 0),
            CGPoint(x: 0, y: -1.8),
            CGPoint(x: 0, y: 1.8)
        ]
        searchPoints = offsets.map { CGPoint(x: center.x + $0.x, y: center.y + $0.y) }
        searchIndex = 0
        state = .search
    }
}
