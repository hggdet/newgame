import SpriteKit
import Foundation

// Batch A scene: a test station (surface zones + storage) the player walks
// with a left joystick + sprint button, footsteps publish noise, and the
// Death Angel hunts by sound. Batch B replaces the test floor with the
// data-driven level, light and fog.
//
// STEP 0 safety rules applied throughout:
// - didMove refuses to build on a zero/invalid size and reports instead.
// - No force unwraps, no unchecked indexing, all movement via SafeMath.
// - No physics bodies in this batch (nothing to build with empty paths).
final class GameScene: SKScene {
    var onPlayerCaught: (() -> Void)?

    private let worldRect = CGRect(x: 0, y: 0, width: 2600, height: 1700)

    private var isBuilt = false
    private let worldNode = SKNode()
    private let cam = SKCameraNode()

    private var player: PlayerController?
    private var playerNode: SKShapeNode?
    private var angel: DeathAngelAI?
    private var zones: [SurfaceZone] = []
    private var noiseListenerID: UUID?

    private var sceneTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var noiseTimer: TimeInterval = 0
    private var lastSurface: SurfaceType = .carpet
    private var caughtFired = false
    private var heartbeatTimer: TimeInterval = 0

    // Touch input
    private var joystickTouch: UITouch?
    private var joystickVector = CGPoint.zero
    private var sprintTouch: UITouch?
    private var isSprinting = false

    // HUD (children of the camera, so they stay fixed on screen)
    private var joystickBase: SKShapeNode?
    private var joystickKnob: SKShapeNode?
    private var sprintButton: SKShapeNode?
    private var modeLabel: SKLabelNode?
    private var debugLabel: SKLabelNode?
    private var lastKnownMarker: SKShapeNode?

    // Debug overlay: hidden triple-tap in the top-left corner.
    private var debugEnabled = false
    private var cornerTapTimes: [TimeInterval] = []

    deinit {
        if let id = noiseListenerID {
            NoiseBus.shared.removeListener(id)
        }
    }

    // MARK: - Setup (crash-safe)

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // The original crash path: scene used before real bounds existed.
        // If our size is still zero, adopt the view's bounds; if even that
        // is not ready, report and bail out — never build on zero.
        if size.width <= 0 || size.height <= 0 {
            size = view.bounds.size
        }
        guard size.width > 10, size.height > 10 else {
            reportError("حجم المشهد غير جاهز، تم تأجيل البناء بأمان")
            return
        }
        guard !isBuilt else { return }
        isBuilt = true
        buildWorld()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isBuilt else { return }
        layoutHUD()
    }

    private func buildWorld() {
        backgroundColor = SKColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1)
        addChild(worldNode)

        // Test floor — glass first so it wins the surface lookup where it
        // overlaps the metal corridor.
        zones = [
            SurfaceZone(rect: CGRect(x: 1000, y: 640, width: 520, height: 300),
                        surface: .glass, name: "زجاج الممر"),
            SurfaceZone(rect: CGRect(x: 0, y: 0, width: 720, height: 620),
                        surface: .carpet, name: "المدخل"),
            SurfaceZone(rect: CGRect(x: 720, y: 0, width: 1880, height: 620),
                        surface: .concrete, name: "قاعة"),
            SurfaceZone(rect: CGRect(x: 0, y: 620, width: 2600, height: 380),
                        surface: .metal, name: "ممر معدني"),
            SurfaceZone(rect: CGRect(x: 0, y: 1000, width: 760, height: 700),
                        surface: .metal, name: "المخزن"),
            SurfaceZone(rect: CGRect(x: 760, y: 1000, width: 1840, height: 700),
                        surface: .concrete, name: "المختبرات")
        ]
        for zone in zones {
            drawZone(zone)
        }

        // Player (PLACEHOLDER NODE — GameScene.swift): plain cyan circle.
        let controller = PlayerController(start: CGPoint(x: 220, y: 220))
        player = controller
        let circle = SKShapeNode(circleOfRadius: controller.radius)
        circle.fillColor = SKColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1)
        circle.strokeColor = .white
        circle.lineWidth = 2
        circle.position = controller.position
        circle.zPosition = 10
        circle.name = "player"
        playerNode = circle
        worldNode.addChild(circle)

        // Death Angel, dormant in storage (top-left room).
        let angelSpawn = CGPoint(x: 380, y: 1350)
        let patrolPoints: [CGPoint] = [
            CGPoint(x: 380, y: 1350),
            CGPoint(x: 1300, y: 810),
            CGPoint(x: 2200, y: 810),
            CGPoint(x: 1300, y: 300),
            CGPoint(x: 400, y: 810)
        ]
        let deathAngel = DeathAngelAI(spawn: angelSpawn, waypoints: patrolPoints)
        angel = deathAngel
        worldNode.addChild(deathAngel.node)

        // The angel hears through the bus; the token is removed in deinit.
        noiseListenerID = NoiseBus.shared.addListener { [weak deathAngel] event in
            deathAngel?.onNoise(event)
        }

        // Last-known-position marker (debug only).
        let marker = SKShapeNode(circleOfRadius: 12)
        marker.strokeColor = .red
        marker.lineWidth = 2
        marker.fillColor = SKColor.red.withAlphaComponent(0.25)
        marker.zPosition = 8
        marker.isHidden = true
        lastKnownMarker = marker
        worldNode.addChild(marker)

        // Camera.
        addChild(cam)
        camera = cam
        cam.position = controller.position

        buildHUD()
        AudioManager.shared.updateListener(position: controller.position)
    }

    private func drawZone(_ zone: SurfaceZone) {
        guard zone.rect.width > 4, zone.rect.height > 4 else { return }
        let shape = SKShapeNode(rectOf: zone.rect.size)
        shape.position = CGPoint(x: zone.rect.midX, y: zone.rect.midY)
        shape.zPosition = 0
        switch zone.surface {
        case .carpet:
            shape.fillColor = SKColor(red: 0.13, green: 0.16, blue: 0.13, alpha: 1)
        case .concrete:
            shape.fillColor = SKColor(red: 0.16, green: 0.16, blue: 0.19, alpha: 1)
        case .metal:
            shape.fillColor = SKColor(red: 0.2, green: 0.21, blue: 0.26, alpha: 1)
        case .glass:
            shape.fillColor = SKColor(red: 0.35, green: 0.42, blue: 0.5, alpha: 1)
        }
        shape.strokeColor = SKColor.white.withAlphaComponent(0.12)
        shape.lineWidth = 2
        shape.name = "zone_\(zone.name)"
        worldNode.addChild(shape)

        let label = SKLabelNode(text: zone.name)
        label.fontSize = 30
        label.fontColor = SKColor.white.withAlphaComponent(0.35)
        label.position = CGPoint(x: zone.rect.midX, y: zone.rect.midY)
        label.zPosition = 1
        worldNode.addChild(label)
    }

    // MARK: - HUD

    private func buildHUD() {
        let base = SKShapeNode(circleOfRadius: 56)
        base.fillColor = SKColor.white.withAlphaComponent(0.07)
        base.strokeColor = SKColor.white.withAlphaComponent(0.25)
        base.lineWidth = 2
        base.zPosition = 50
        joystickBase = base
        cam.addChild(base)

        let knob = SKShapeNode(circleOfRadius: 26)
        knob.fillColor = SKColor.white.withAlphaComponent(0.3)
        knob.strokeColor = SKColor.white.withAlphaComponent(0.5)
        knob.lineWidth = 1
        knob.zPosition = 51
        joystickKnob = knob
        cam.addChild(knob)

        let sprint = SKShapeNode(circleOfRadius: 42)
        sprint.fillColor = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 0.25)
        sprint.strokeColor = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 0.8)
        sprint.lineWidth = 2
        sprint.zPosition = 50
        sprintButton = sprint
        cam.addChild(sprint)

        let sprintLabel = SKLabelNode(text: "اركض")
        sprintLabel.fontSize = 19
        sprintLabel.fontColor = .white
        sprintLabel.verticalAlignmentMode = .center
        sprint.addChild(sprintLabel)

        let mode = SKLabelNode(text: "")
        mode.fontSize = 18
        mode.fontColor = SKColor.white.withAlphaComponent(0.75)
        mode.zPosition = 50
        modeLabel = mode
        cam.addChild(mode)

        let debug = SKLabelNode(text: "")
        debug.fontSize = 17
        debug.fontColor = .yellow
        debug.zPosition = 50
        debug.isHidden = true
        debugLabel = debug
        cam.addChild(debug)

        layoutHUD()
    }

    private func layoutHUD() {
        let halfW = size.width / 2
        let halfH = size.height / 2
        guard halfW > 0, halfH > 0 else { return }
        joystickBase?.position = CGPoint(x: -halfW + 104, y: -halfH + 104)
        joystickKnob?.position = joystickBase?.position ?? .zero
        sprintButton?.position = CGPoint(x: halfW - 88, y: -halfH + 88)
        modeLabel?.position = CGPoint(x: 0, y: -halfH + 26)
        debugLabel?.position = CGPoint(x: 0, y: halfH - 30)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let loc = touch.location(in: cam)
            if let sprint = sprintButton,
               SafeMath.distance(loc, sprint.position) < 52 {
                sprintTouch = touch
                isSprinting = true
            } else if loc.x < 0, joystickTouch == nil {
                joystickTouch = touch
                updateJoystick(with: loc)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch == joystickTouch {
            updateJoystick(with: touch.location(in: cam))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == joystickTouch {
                joystickTouch = nil
                joystickVector = .zero
                joystickKnob?.position = joystickBase?.position ?? .zero
            }
            if touch == sprintTouch {
                sprintTouch = nil
                isSprinting = false
            }
            registerCornerTap(touch.location(in: cam))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func updateJoystick(with loc: CGPoint) {
        guard let base = joystickBase else { return }
        let delta = CGPoint(x: loc.x - base.position.x, y: loc.y - base.position.y)
        let length = delta.length()
        let maxRadius: CGFloat = 56
        let clampedLength = min(length, maxRadius)
        let unit = delta.normalizedOrZero()
        joystickVector = CGPoint(
            x: unit.x * (clampedLength / maxRadius),
            y: unit.y * (clampedLength / maxRadius)
        )
        joystickKnob?.position = CGPoint(
            x: base.position.x + unit.x * clampedLength,
            y: base.position.y + unit.y * clampedLength
        )
    }

    // Hidden debug toggle: 3 taps in the top-left corner within 1.2s.
    private func registerCornerTap(_ loc: CGPoint) {
        let halfW = size.width / 2
        let halfH = size.height / 2
        guard loc.x < -halfW + 120, loc.y > halfH - 120 else { return }
        cornerTapTimes.append(sceneTime)
        cornerTapTimes = cornerTapTimes.filter { sceneTime - $0 < 1.2 }
        if cornerTapTimes.count >= 3 {
            cornerTapTimes = []
            debugEnabled.toggle()
            debugLabel?.isHidden = !debugEnabled
            lastKnownMarker?.isHidden = !debugEnabled
        }
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt, let player = player, let angel = angel else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        var dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        guard dt > 0 else { return }
        dt = min(dt, 0.05)
        sceneTime += dt

        // Movement
        player.update(dt: dt, input: joystickVector, sprint: isSprinting,
                      worldBounds: worldRect)
        playerNode?.position = player.position
        modeLabel?.text = player.mode.arabicName

        // Noise from footsteps
        let surface = surfaceAt(player.position)
        if surface == .glass, lastSurface != .glass, player.mode != .idle {
            emitNoise(radiusOverride: 200)
        }
        if player.mode != .idle {
            noiseTimer += dt
            if noiseTimer >= player.noiseInterval {
                noiseTimer = 0
                emitNoise(radiusOverride: nil)
            }
        } else {
            noiseTimer = 0
        }
        lastSurface = surface

        // Monster
        angel.updateAI(dt: dt, now: sceneTime)

        // Physical contact = caught (fair even without knowledge).
        if !caughtFired, angel.state != .dormant,
           SafeMath.distance(angel.node.position, player.position) < 30 {
            caughtFired = true
            onPlayerCaught?()
        }

        // Camera follows, clamped inside the world when possible.
        let target = cameraTarget(for: player.position)
        let dist = SafeMath.distance(cam.position, target)
        let step = dist * min(1, CGFloat(dt) * 6)
        cam.position = SafeMath.move(cam.position, toward: target, maxStep: max(step, 0.01))

        // Directional audio listener = the player.
        AudioManager.shared.updateListener(position: player.position)

        // Heartbeat haptics speed up as the angel closes in.
        let angelDistance = SafeMath.distance(angel.node.position, player.position)
        if angel.state != .dormant, angelDistance < 430 {
            heartbeatTimer += dt
            let proximity = 1 - angelDistance / 430
            let interval = 1.1 - 0.75 * TimeInterval(proximity)
            if heartbeatTimer >= interval {
                heartbeatTimer = 0
                HapticsManager.shared.heartbeat(proximity: Float(proximity))
            }
        } else {
            heartbeatTimer = 0
        }

        updateDebug(angelDistance: angelDistance)
    }

    private func cameraTarget(for point: CGPoint) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        var x = point.x
        var y = point.y
        if worldRect.width > size.width {
            x = min(max(point.x, worldRect.minX + halfW), worldRect.maxX - halfW)
        } else {
            x = worldRect.midX
        }
        if worldRect.height > size.height {
            y = min(max(point.y, worldRect.minY + halfH), worldRect.maxY - halfH)
        } else {
            y = worldRect.midY
        }
        return CGPoint(x: x, y: y)
    }

    private func surfaceAt(_ point: CGPoint) -> SurfaceType {
        for zone in zones where zone.rect.contains(point) {
            return zone.surface
        }
        return .concrete
    }

    private func zoneNameAt(_ point: CGPoint) -> String {
        for zone in zones where zone.rect.contains(point) {
            return zone.name
        }
        return "خارج المناطق"
    }

    private func emitNoise(radiusOverride: CGFloat?) {
        guard let player = player, let angel = angel else { return }
        let radius = radiusOverride ?? player.noiseRadius(on: surfaceAt(player.position))
        guard radius > 0 else { return }
        let event = NoiseEvent(position: player.position, radius: radius, time: sceneTime)
        NoiseBus.shared.publish(event)

        // Habit tracking: loud behaviour in a zone is remembered.
        if event.level >= .loud {
            angel.recordHabit(zone: zoneNameAt(player.position))
        }
        if debugEnabled {
            showNoiseRipple(event)
        }
    }

    private func showNoiseRipple(_ event: NoiseEvent) {
        guard event.radius > 1 else { return }
        let ripple = SKShapeNode(circleOfRadius: 10)
        ripple.position = event.position
        ripple.strokeColor = SKColor.orange.withAlphaComponent(0.8)
        ripple.lineWidth = 2
        ripple.fillColor = .clear
        ripple.zPosition = 7
        worldNode.addChild(ripple)
        let scale = SKAction.scale(to: event.radius / 10, duration: 0.45)
        let fade = SKAction.fadeOut(withDuration: 0.45)
        ripple.run(SKAction.group([scale, fade])) {
            ripple.removeFromParent()
        }
    }

    private func updateDebug(angelDistance: CGFloat) {
        guard debugEnabled, let angel = angel else { return }
        let known: String
        if let pos = angel.lastKnownPosition {
            known = "(\(Int(pos.x)), \(Int(pos.y)))"
            lastKnownMarker?.position = pos
            lastKnownMarker?.isHidden = false
        } else {
            known = "لا يوجد"
            lastKnownMarker?.isHidden = true
        }
        debugLabel?.text = "ملاك الموت: \(angel.state.arabicName) | آخر موقع معروف: \(known) | المسافة: \(Int(angelDistance))"
    }
}
