import Foundation
import SceneKit
import CoreGraphics

// The SOUND hunter (first-person build). Blind: it reacts ONLY to
// NoiseEvents whose radius reaches it. Starts DORMANT in storage, wakes
// on a loud noise, hunts the noise origin, searches around the last known
// position, and returns to dormant after losing the player for 20s.
// Same state machine as the 2D build, re-scaled to meters.
// Its body is an original design (see MonsterModels.soundHunter()).
final class DeathAngel3D: MonsterBase3D {
    let spawnPosition: CGPoint
    var waypoints: [CGPoint]

    private var waypointIndex = 0
    private var lastHeardTime: TimeInterval = -10_000
    private var lastOrigin: CGPoint?
    private var heardStreak = 0
    private var lastStreakTime: TimeInterval = -10_000
    private var searchPoints: [CGPoint] = []
    private var searchIndex = 0

    // Speeds (m/s). Fast and violent, but a sprint barely outruns it.
    private let patrolSpeed: CGFloat = 1.05
    private let investigateSpeed: CGFloat = 2.1
    private let chaseSpeed: CGFloat = 2.92
    private let searchSpeed: CGFloat = 1.3
    private let returnSpeed: CGFloat = 2.3

    init(spawn: CGPoint, waypoints: [CGPoint]) {
        self.spawnPosition = spawn.isSafeFinite ? spawn : .zero
        self.waypoints = waypoints.filter { $0.isSafeFinite }
        super.init(node: MonsterModels.soundHunter())
        setFloorPosition(self.spawnPosition)
        state = .dormant
    }

    // Some sound hunters patrol awake from the start (only the storage
    // one sleeps). Used by the scene factory for hunters 2 and 3.
    func wakeToPatrol() {
        if state == .dormant {
            state = .patrol
        }
    }

    // MARK: - Hearing

    override func onNoise(_ event: NoiseEvent) {
        let heard = SafeMath.isWithin(floorPosition, event.position, radius: event.radius)
        guard heard else { return }

        lastKnownPosition = event.position
        lastHeardTime = event.time

        switch state {
        case .dormant:
            if event.level >= .loud {
                state = .investigate
                AudioManager.shared.play(.deathAngelScreech, at: floorPosition)
                HapticsManager.shared.pulse(intensity: 0.7, sharpness: 0.8)
            }
        case .patrol, .search, .investigate:
            if let last = lastOrigin,
               SafeMath.distance(last, event.position) < 2.5,
               event.time - lastStreakTime < 3.0 {
                heardStreak += 1
            } else {
                heardStreak = 1
            }
            lastOrigin = event.position
            lastStreakTime = event.time
            state = heardStreak >= 2 ? .chase : .investigate
        case .chase:
            break
        }
    }

    // MARK: - Behaviour

    override func updateAI(dt: TimeInterval, now: TimeInterval) {
        guard dt > 0, dt.isFinite else { return }

        // Lost the player for 20s: go home and sleep again.
        if state != .dormant, now - lastHeardTime > 20 {
            moveToward(spawnPosition, speed: returnSpeed, dt: dt)
            if SafeMath.distance(floorPosition, spawnPosition) < 0.3 {
                state = .dormant
                lastKnownPosition = nil
                heardStreak = 0
            }
            return
        }

        switch state {
        case .dormant:
            break

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
            }

        case .chase:
            guard let target = lastKnownPosition else {
                state = .search
                return
            }
            moveToward(target, speed: chaseSpeed, dt: dt)
            if now - lastHeardTime > 4 {
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

    // Search: the last known position, then the points around it
    // (Batch C' adds real locker positions to this list).
    private func beginSearch(around center: CGPoint) {
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: -1.6, y: 0),
            CGPoint(x: 1.6, y: 0),
            CGPoint(x: 0, y: -1.6),
            CGPoint(x: 0, y: 1.6),
            CGPoint(x: -1.1, y: -1.1),
            CGPoint(x: 1.1, y: 1.1)
        ]
        searchPoints = offsets.map { CGPoint(x: center.x + $0.x, y: center.y + $0.y) }
        searchIndex = 0
        state = .search
    }
}
