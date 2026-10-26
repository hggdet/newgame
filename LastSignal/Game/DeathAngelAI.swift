import Foundation
import SpriteKit
import CoreGraphics

// Death Angel — the SOUND hunter. Blind: it reacts ONLY to NoiseEvents
// whose radius reaches it. It starts DORMANT in storage, wakes on a loud
// noise, hunts the noise origin, searches around the last known position,
// and returns to dormant after losing the player for 20 seconds.
//
// Placeholder look: a dark red triangle. `makePlaceholderNode()` is the
// single hook to replace with real art later.
final class DeathAngelAI: MonsterBase {
    let spawnPosition: CGPoint
    var waypoints: [CGPoint]

    private var waypointIndex = 0
    private var lastHeardTime: TimeInterval = -10_000
    private var lastOrigin: CGPoint?
    private var heardStreak = 0
    private var lastStreakTime: TimeInterval = -10_000
    private var searchPoints: [CGPoint] = []
    private var searchIndex = 0

    // Speeds (points/sec). Fast and violent, but a sprint barely outruns it.
    private let patrolSpeed: CGFloat = 95
    private let investigateSpeed: CGFloat = 185
    private let chaseSpeed: CGFloat = 256
    private let searchSpeed: CGFloat = 118
    private let returnSpeed: CGFloat = 205

    init(spawn: CGPoint, waypoints: [CGPoint]) {
        self.spawnPosition = spawn.isSafeFinite ? spawn : .zero
        self.waypoints = waypoints.filter { $0.isSafeFinite }
        super.init(node: DeathAngelAI.makePlaceholderNode())
        node.position = self.spawnPosition
        state = .dormant
    }

    // PLACEHOLDER NODE — DeathAngelAI.swift
    static func makePlaceholderNode() -> SKNode {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 22),
            CGPoint(x: -17, y: -16),
            CGPoint(x: 17, y: -16)
        ]
        // A path needs at least 3 points; the literal above always has 3,
        // but we still build it defensively.
        guard points.count >= 3 else { return SKNode() }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = SKColor(red: 0.55, green: 0.05, blue: 0.08, alpha: 1)
        shape.strokeColor = SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 1)
        shape.lineWidth = 2
        shape.zPosition = 9
        shape.name = "deathAngel"
        return shape
    }

    // MARK: - Hearing

    override func onNoise(_ event: NoiseEvent) {
        // Heard only if the angel stands inside the noise radius.
        let heard = SafeMath.isWithin(node.position, event.position, radius: event.radius)
        guard heard else { return }

        lastKnownPosition = event.position
        lastHeardTime = event.time

        switch state {
        case .dormant:
            // Wakes only on a noise above the threshold (loud or worse).
            if event.level >= .loud {
                setState(.investigate)
                AudioManager.shared.play(.deathAngelScreech, at: node.position)
                HapticsManager.shared.pulse(intensity: 0.7, sharpness: 0.8)
            }
        case .patrol, .search, .investigate:
            // Repeated noises from nearly the same place escalate to a chase.
            if let last = lastOrigin,
               SafeMath.distance(last, event.position) < 150,
               event.time - lastStreakTime < 3.0 {
                heardStreak += 1
            } else {
                heardStreak = 1
            }
            lastOrigin = event.position
            lastStreakTime = event.time
            setState(heardStreak >= 2 ? .chase : .investigate)
        case .chase:
            // Target already updated above; keep chasing the newest origin.
            break
        }
    }

    // MARK: - Behaviour

    override func updateAI(dt: TimeInterval, now: TimeInterval) {
        guard dt > 0, dt.isFinite, node.position.isSafeFinite else { return }

        // Lost the player for 20s: go home and sleep again.
        if state != .dormant, now - lastHeardTime > 20 {
            moveToward(spawnPosition, speed: returnSpeed, dt: dt)
            if SafeMath.distance(node.position, spawnPosition) < 10 {
                setState(.dormant)
                lastKnownPosition = nil
                heardStreak = 0
            }
            return
        }

        switch state {
        case .dormant:
            break // Sleeps in storage until a loud noise wakes it.

        case .patrol:
            guard !waypoints.isEmpty else { return }
            let target = waypoints[waypointIndex % waypoints.count]
            moveToward(target, speed: patrolSpeed, dt: dt)
            if SafeMath.distance(node.position, target) < 12 {
                waypointIndex += 1
            }

        case .investigate:
            guard let target = lastKnownPosition else {
                setState(.patrol)
                return
            }
            moveToward(target, speed: investigateSpeed, dt: dt)
            if SafeMath.distance(node.position, target) < 12 {
                beginSearch(around: target)
            }

        case .chase:
            guard let target = lastKnownPosition else {
                setState(.search)
                return
            }
            moveToward(target, speed: chaseSpeed, dt: dt)
            // Chasing silence for 4s means the trail went cold.
            if now - lastHeardTime > 4 {
                beginSearch(around: target)
            }

        case .search:
            guard searchIndex < searchPoints.count else {
                setState(.patrol)
                return
            }
            let target = searchPoints[searchIndex]
            moveToward(target, speed: searchSpeed, dt: dt)
            if SafeMath.distance(node.position, target) < 12 {
                searchIndex += 1
            }
        }
    }

    // Search pattern: the last known position, then the points around it
    // (Batch C adds real locker positions to this list).
    private func beginSearch(around center: CGPoint) {
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: -95, y: 0),
            CGPoint(x: 95, y: 0),
            CGPoint(x: 0, y: -95),
            CGPoint(x: 0, y: 95),
            CGPoint(x: -65, y: -65),
            CGPoint(x: 65, y: 65)
        ]
        searchPoints = offsets.map { CGPoint(x: center.x + $0.x, y: center.y + $0.y) }
        searchIndex = 0
        setState(.search)
    }

    private func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let step = speed * CGFloat(dt)
        node.position = SafeMath.move(node.position, toward: target, maxStep: step)
    }

    private func setState(_ newState: MonsterState) {
        state = newState
    }
}
