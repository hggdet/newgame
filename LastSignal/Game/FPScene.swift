import Foundation
import SceneKit
import CoreGraphics
import UIKit

// Thread-safe touch input shared between the SwiftUI HUD (main thread)
// and the SceneKit render loop (render thread).
final class FPInputState {
    private let lock = NSLock()
    private var move = CGPoint.zero
    private var sprint = false
    private var lookDX: CGFloat = 0
    private var lookDY: CGFloat = 0

    func setMove(_ value: CGPoint) {
        lock.lock(); move = value; lock.unlock()
    }

    func setSprint(_ value: Bool) {
        lock.lock(); sprint = value; lock.unlock()
    }

    func addLook(dx: CGFloat, dy: CGFloat) {
        guard dx.isSafeFinite, dy.isSafeFinite else { return }
        lock.lock(); lookDX += dx; lookDY += dy; lock.unlock()
    }

    func moveVector() -> CGPoint {
        lock.lock(); defer { lock.unlock() }
        return move
    }

    func isSprinting() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sprint
    }

    func consumeLookDelta() -> (dx: CGFloat, dy: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        let delta = (dx: lookDX, dy: lookDY)
        lookDX = 0
        lookDY = 0
        return delta
    }

    // One-shot action requests, consumed by the render loop exactly once.
    private var throwRequests = 0
    private var flashlightRequests = 0
    private var swingRequests = 0

    func requestThrow() {
        lock.lock(); throwRequests += 1; lock.unlock()
    }

    func requestFlashlightToggle() {
        lock.lock(); flashlightRequests += 1; lock.unlock()
    }

    func requestSwing() {
        lock.lock(); swingRequests += 1; lock.unlock()
    }

    func consumeThrow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard throwRequests > 0 else { return false }
        throwRequests -= 1
        return true
    }

    func consumeFlashlightToggle() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard flashlightRequests > 0 else { return false }
        flashlightRequests -= 1
        return true
    }

    func consumeSwing() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard swingRequests > 0 else { return false }
        swingRequests -= 1
        return true
    }

    private var interactRequests = 0
    private var holdingBreath = false

    func requestInteract() {
        lock.lock(); interactRequests += 1; lock.unlock()
    }

    func consumeInteract() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard interactRequests > 0 else { return false }
        interactRequests -= 1
        return true
    }

    func setHoldBreath(_ value: Bool) {
        lock.lock(); holdingBreath = value; lock.unlock()
    }

    private var lightCycleRequests = 0

    func requestLightCycle() {
        lock.lock(); lightCycleRequests += 1; lock.unlock()
    }

    func consumeLightCycle() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard lightCycleRequests > 0 else { return false }
        lightCycleRequests -= 1
        return true
    }

    func isHoldingBreath() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return holdingBreath
    }
}

// Everything one playable scene needs, built in one place.
final class FPSceneBundle {
    let scene: SCNScene
    let cameraNode: SCNNode
    let controller: FPSceneController

    init(scene: SCNScene, cameraNode: SCNNode, controller: FPSceneController) {
        self.scene = scene
        self.cameraNode = cameraNode
        self.controller = controller
    }
}

// Darkness escalates per floor (his design): each floor a bit darker.
// Percent is the design language; the profile translates it into the two
// numbers that actually make darkness in SceneKit — ambient light level
// and how far the fog lets you see.
struct DarknessProfile {
    let percent: Int
    let ambientIntensity: CGFloat
    let fogStart: CGFloat
    let fogEnd: CGFloat

    static func forFloor(_ floor: Int) -> DarknessProfile {
        switch floor {
        case 1:
            return DarknessProfile(percent: 80, ambientIntensity: 42, fogStart: 3.0, fogEnd: 18)
        case 2:
            return DarknessProfile(percent: 87, ambientIntensity: 26, fogStart: 2.5, fogEnd: 13.5)
        case 3:
            return DarknessProfile(percent: 94, ambientIntensity: 12, fogStart: 2.0, fogEnd: 9.5)
        case 4: // the roof at dawn — you can finally see
            return DarknessProfile(percent: 25, ambientIntensity: 210, fogStart: 10, fogEnd: 55)
        default:
            return DarknessProfile(percent: 80, ambientIntensity: 42, fogStart: 3.0, fogEnd: 18)
        }
    }
}

// Flashlight levels (long-press the flashlight button to cycle).
// Strong sees farther — and so does the sight hunter. Flash strobes:
// cheap on battery, and the hunter only catches the lit instants.
enum FlashLevel {
    case steady, strong, flash

    var next: FlashLevel {
        switch self {
        case .steady: return .strong
        case .strong: return .flash
        case .flash: return .steady
        }
    }

    var arabicName: String {
        switch self {
        case .steady: return "ثابت"
        case .strong: return "قوي"
        case .flash: return "وامض"
        }
    }

    var drainPerSecond: CGFloat {
        switch self {
        case .steady: return 0.42
        case .strong: return 1.05
        case .flash: return 0.22
        }
    }

    var detectionRange: CGFloat {
        switch self {
        case .steady: return 9
        case .strong: return 13.5
        case .flash: return 9
        }
    }
}

// Builds floor 1 of the station building. All geometry is code-built with
// PBR materials; every size is guarded before a node is created.
enum FPSceneFactory {
    static func make(floor: Int,
                     input: FPInputState,
                     onCaught: @escaping () -> Void,
                     onModeChange: @escaping (MovementMode) -> Void,
                     onLightChange: @escaping (Bool, Int) -> Void,
                     onLightLevelChange: @escaping (String) -> Void,
                     onStonesChange: @escaping (Int) -> Void,
                     onObjective: @escaping (String) -> Void,
                     onCodeChange: @escaping ([Int?]) -> Void,
                     onStickChange: @escaping (Bool) -> Void,
                     onFloorComplete: @escaping () -> Void,
                     onInteractPrompt: @escaping (String?) -> Void,
                     onBreath: @escaping (Int, Bool) -> Void,
                     onHidden: @escaping (Bool) -> Void,
                     onSendProgress: @escaping (Int, Bool) -> Void,
                     onGameWin: @escaping () -> Void) -> FPSceneBundle {
        let level = LevelData3D.level(forFloor: floor)
        let darkness = DarknessProfile.forFloor(level.floorNumber)
        let isRoof = level.transmitterPosition != nil
        let scene = SCNScene()
        if isRoof {
            // Dawn sky on the roof.
            scene.background.contents = UIColor(red: 0.16, green: 0.2, blue: 0.3, alpha: 1)
            scene.fogColor = UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1)
        } else {
            scene.background.contents = UIColor.black
            scene.fogColor = UIColor.black
        }
        scene.fogStartDistance = darkness.fogStart
        scene.fogEndDistance = darkness.fogEnd
        scene.fogDensityExponent = 1.0

        buildFloorsAndCeiling(scene: scene, level: level)
        buildWalls(scene: scene, level: level)
        buildLights(scene: scene, level: level, ambientIntensity: darkness.ambientIntensity)
        buildDust(scene: scene, level: level)

        // Player rig: root at floor position, camera at eye height,
        // flashlight spot (steady level; levels arrive in Batch B').
        let rig = SCNNode()
        rig.position = SCNVector3(Float(level.playerSpawn.x), 0, Float(level.playerSpawn.y))
        scene.rootNode.addChildNode(rig)

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 60
        camera.fieldOfView = 68
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.62, 0)
        rig.addChildNode(cameraNode)

        let spotNode = SCNNode()
        let spot = SCNLight()
        spot.type = .spot
        spot.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        spot.intensity = 450
        spot.attenuationStartDistance = 0.5
        spot.attenuationEndDistance = 18
        spot.spotAngle = 38
        spot.spotPenumbra = 0.7
        spot.castsShadow = true
        spot.shadowMapSize = CGSize(width: 1024, height: 1024)
        spot.shadowColor = UIColor.black.withAlphaComponent(0.9)
        spotNode.light = spot
        spotNode.position = SCNVector3(0.12, -0.08, 0.05)
        cameraNode.addChildNode(spotNode)

        // One pathfinding grid per floor: monsters route around the
        // walls (plus the locked entry door) to track the player.
        let pathGrid = PathGrid(worldBounds: level.worldBounds,
                                walls: level.walls + [level.entryDoorRect])

        // Monsters: THREE of each type per floor (his standing design),
        // placed by the level data; speed scales with the floor.
        var soundHunters: [DeathAngel3D] = []
        for placement in level.soundHunters {
            let hunter = DeathAngel3D(spawn: placement.spawn, waypoints: placement.waypoints)
            hunter.speedScale = level.monsterSpeedScale
            hunter.pathfinder = pathGrid
            if placement.startsAwake {
                hunter.wakeToPatrol()
            }
            scene.rootNode.addChildNode(hunter.node)
            soundHunters.append(hunter)
        }

        var sightHunters: [LightHunter3D] = []
        for placement in level.sightHunters {
            let hunter = LightHunter3D(spawn: placement.spawn, waypoints: placement.waypoints)
            hunter.speedScale = level.monsterSpeedScale
            hunter.pathfinder = pathGrid
            scene.rootNode.addChildNode(hunter.node)
            sightHunters.append(hunter)
        }

        // Throwable pebbles scattered on the floor.
        var stoneNodes: [SCNNode] = []
        let stoneMaterial = SCNMaterial()
        stoneMaterial.lightingModel = .physicallyBased
        stoneMaterial.diffuse.contents = UIColor(red: 0.42, green: 0.4, blue: 0.38, alpha: 1)
        stoneMaterial.roughness.contents = 0.9
        for (index, point) in level.stones.enumerated() {
            let stone = SCNNode(geometry: SCNSphere(radius: 0.09))
            stone.geometry?.materials = [stoneMaterial]
            stone.scale = SCNVector3(1, 0.6, 1)
            stone.position = SCNVector3(Float(point.x), 0.05, Float(point.y))
            stone.name = "stone_\(index)"
            scene.rootNode.addChildNode(stone)
            stoneNodes.append(stone)
        }

        // Flashlight battery pickups (+40% each).
        var batteryNodes: [SCNNode] = []
        let batteryMaterial = SCNMaterial()
        batteryMaterial.lightingModel = .physicallyBased
        batteryMaterial.diffuse.contents = UIColor(red: 0.15, green: 0.35, blue: 0.18, alpha: 1)
        batteryMaterial.emission.contents = UIColor(red: 0.05, green: 0.3, blue: 0.08, alpha: 1)
        batteryMaterial.roughness.contents = 0.4
        for point in level.batteries {
            let node = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.24))
            node.geometry?.materials = [batteryMaterial]
            node.position = SCNVector3(Float(point.x), 0.12, Float(point.y))
            node.name = "battery"
            scene.rootNode.addChildNode(node)
            batteryNodes.append(node)
        }

        // The stick: a wooden club lying by the entrance.
        let stickNode = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 1.15))
        let woodMaterial = SCNMaterial()
        woodMaterial.lightingModel = .physicallyBased
        woodMaterial.diffuse.contents = UIColor(red: 0.4, green: 0.28, blue: 0.16, alpha: 1)
        woodMaterial.roughness.contents = 0.85
        stickNode.geometry?.materials = [woodMaterial]
        stickNode.position = SCNVector3(Float(level.stickSpawn.x), 0.06, Float(level.stickSpawn.y))
        stickNode.eulerAngles = SCNVector3(0, 0.6, Float.pi / 2.15)
        stickNode.name = "stick"
        scene.rootNode.addChildNode(stickNode)

        // Breakable props.
        var breakables: [(prop: BreakableProp, node: SCNNode)] = []
        for prop in level.breakables {
            let node: SCNNode
            switch prop.kind {
            case .crate:
                node = SCNNode(geometry: SCNBox(width: 0.7, height: 0.7, length: 0.7, chamferRadius: 0.02))
                node.geometry?.materials = [woodMaterial]
                node.position = SCNVector3(Float(prop.position.x), 0.35, Float(prop.position.y))
            case .glassPanel:
                node = SCNNode(geometry: SCNBox(width: 1.3, height: 1.9, length: 0.06, chamferRadius: 0))
                let glassMaterial = SCNMaterial()
                glassMaterial.lightingModel = .physicallyBased
                glassMaterial.diffuse.contents = UIColor(red: 0.6, green: 0.75, blue: 0.85, alpha: 1)
                glassMaterial.roughness.contents = 0.1
                glassMaterial.metalness.contents = 0.1
                glassMaterial.transparency = 0.55
                node.geometry?.materials = [glassMaterial]
                node.position = SCNVector3(Float(prop.position.x), 0.95, Float(prop.position.y))
            }
            node.name = "breakable"
            scene.rootNode.addChildNode(node)
            breakables.append((prop: prop, node: node))
        }

        // Entry door: a sliding panel, open (tucked into the west wall
        // segment) until the player crosses — then it shuts and locks.
        let doorMaterial = SCNMaterial()
        doorMaterial.lightingModel = .physicallyBased
        doorMaterial.diffuse.contents = UIColor(red: 0.23, green: 0.24, blue: 0.3, alpha: 1)
        doorMaterial.roughness.contents = 0.5
        doorMaterial.metalness.contents = 0.7
        let entryDoor = SCNNode(geometry: SCNBox(
            width: CGFloat(level.entryDoorRect.width), height: 2.6,
            length: 0.12, chamferRadius: 0.02))
        entryDoor.geometry?.materials = [doorMaterial]
        entryDoor.position = SCNVector3(
            Float(level.entryDoorRect.minX - level.entryDoorRect.width / 2 + 0.3),
            1.3, Float(level.entryDoorRect.midY))
        entryDoor.name = "entryDoor"
        scene.rootNode.addChildNode(entryDoor)

        // Exit door (to floor 2) at the far end of the labs + status lamp.
        let exitDoor = SCNNode(geometry: SCNBox(width: 1.9, height: 2.7, length: 0.14, chamferRadius: 0.02))
        exitDoor.geometry?.materials = [doorMaterial]
        exitDoor.position = SCNVector3(
            Float(level.exitDoorPosition.x), 1.35, Float(level.exitDoorPosition.y) + 0.25)
        exitDoor.name = "exitDoor"
        if !isRoof {
            scene.rootNode.addChildNode(exitDoor)
        }

        let exitLampMaterial = SCNMaterial()
        exitLampMaterial.diffuse.contents = UIColor.red
        exitLampMaterial.emission.contents = UIColor.red
        let exitLamp = SCNNode(geometry: SCNSphere(radius: 0.07))
        exitLamp.geometry?.materials = [exitLampMaterial]
        exitLamp.position = SCNVector3(
            Float(level.exitDoorPosition.x), 2.95, Float(level.exitDoorPosition.y) + 0.25)
        scene.rootNode.addChildNode(exitLamp)

        // The generator (storage): powers the exit door. One tap starts
        // it — easy by hand — but its 3-second crank is VERY loud.
        let generatorMaterial = SCNMaterial()
        generatorMaterial.lightingModel = .physicallyBased
        generatorMaterial.diffuse.contents = UIColor(red: 0.45, green: 0.36, blue: 0.1, alpha: 1)
        generatorMaterial.roughness.contents = 0.6
        generatorMaterial.metalness.contents = 0.4
        let generator = SCNNode(geometry: SCNBox(width: 1.5, height: 1.05, length: 0.85, chamferRadius: 0.03))
        generator.geometry?.materials = [generatorMaterial]
        generator.position = SCNVector3(
            Float(level.generatorPosition.x), 0.52, Float(level.generatorPosition.y))
        generator.name = "generator"
        scene.rootNode.addChildNode(generator)

        let generatorLampMaterial = SCNMaterial()
        generatorLampMaterial.diffuse.contents = UIColor.red
        generatorLampMaterial.emission.contents = UIColor.red
        let generatorLamp = SCNNode(geometry: SCNSphere(radius: 0.06))
        generatorLamp.geometry?.materials = [generatorLampMaterial]
        generatorLamp.position = SCNVector3(
            Float(level.generatorPosition.x) + 0.5, 1.15, Float(level.generatorPosition.y))
        scene.rootNode.addChildNode(generatorLamp)

        // Hiding lockers.
        let lockerMaterial = SCNMaterial()
        lockerMaterial.lightingModel = .physicallyBased
        lockerMaterial.diffuse.contents = UIColor(red: 0.16, green: 0.22, blue: 0.24, alpha: 1)
        lockerMaterial.roughness.contents = 0.5
        lockerMaterial.metalness.contents = 0.6
        for locker in level.lockers {
            let node = SCNNode(geometry: SCNBox(width: 0.95, height: 2.15, length: 0.55, chamferRadius: 0.02))
            node.geometry?.materials = [lockerMaterial]
            node.position = SCNVector3(Float(locker.position.x), 1.07, Float(locker.position.y))
            node.eulerAngles.y = Float(atan2(-locker.facing.x, -locker.facing.y))
            node.name = "locker"
            scene.rootNode.addChildNode(node)
        }

        // Floor hazards: scattered tin cans (sound traps) and sparking
        // broken wires (light traps) the player can step on by mistake.
        var sparkNodes: [Int: SCNNode] = [:]
        let canMaterial = SCNMaterial()
        canMaterial.lightingModel = .physicallyBased
        canMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1)
        canMaterial.metalness.contents = 0.85
        canMaterial.roughness.contents = 0.35
        for (index, hazard) in level.hazards.enumerated() {
            switch hazard.kind {
            case .cans:
                for offset in [CGPoint(x: 0, y: 0), CGPoint(x: 0.16, y: 0.1), CGPoint(x: -0.12, y: 0.14)] {
                    let can = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.12))
                    can.geometry?.materials = [canMaterial]
                    can.position = SCNVector3(
                        Float(hazard.position.x + offset.x), 0.06,
                        Float(hazard.position.y + offset.y))
                    scene.rootNode.addChildNode(can)
                }
            case .sparkWire:
                let wireMaterial = SCNMaterial()
                wireMaterial.diffuse.contents = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
                let wire = SCNNode(geometry: SCNBox(width: 0.5, height: 0.05, length: 0.18, chamferRadius: 0.01))
                wire.geometry?.materials = [wireMaterial]
                wire.position = SCNVector3(Float(hazard.position.x), 0.03, Float(hazard.position.y))
                scene.rootNode.addChildNode(wire)

                let sparkLight = SCNLight()
                sparkLight.type = .omni
                sparkLight.color = UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1)
                sparkLight.intensity = 0
                sparkLight.attenuationStartDistance = 0
                sparkLight.attenuationEndDistance = 6
                let sparkNode = SCNNode()
                sparkNode.light = sparkLight
                sparkNode.position = SCNVector3(Float(hazard.position.x), 0.35, Float(hazard.position.y))
                scene.rootNode.addChildNode(sparkNode)
                sparkNodes[index] = sparkNode
            }
        }

        // The transmitter (roof finale): a mast, a dish, and a
        // blinking beacon. Sending the last signal takes 10 loud
        // seconds next to it.
        if let tx = level.transmitterPosition {
            let mastMaterial = SCNMaterial()
            mastMaterial.lightingModel = .physicallyBased
            mastMaterial.diffuse.contents = UIColor(red: 0.3, green: 0.31, blue: 0.34, alpha: 1)
            mastMaterial.metalness.contents = 0.8
            mastMaterial.roughness.contents = 0.4
            let base = SCNNode(geometry: SCNBox(width: 1.1, height: 0.7, length: 1.1, chamferRadius: 0.03))
            base.geometry?.materials = [mastMaterial]
            base.position = SCNVector3(Float(tx.x), 0.35, Float(tx.y))
            scene.rootNode.addChildNode(base)
            let mast = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 3.1))
            mast.geometry?.materials = [mastMaterial]
            mast.position = SCNVector3(Float(tx.x), 2.2, Float(tx.y))
            scene.rootNode.addChildNode(mast)
            let dish = SCNNode(geometry: SCNSphere(radius: 0.85))
            dish.geometry?.materials = [mastMaterial]
            dish.scale = SCNVector3(1, 0.35, 1)
            dish.position = SCNVector3(Float(tx.x) - 0.4, 3.6, Float(tx.y))
            dish.eulerAngles.z = 0.7
            scene.rootNode.addChildNode(dish)
            let beaconMaterial = SCNMaterial()
            beaconMaterial.diffuse.contents = UIColor.red
            beaconMaterial.emission.contents = UIColor.red
            let beacon = SCNNode(geometry: SCNSphere(radius: 0.07))
            beacon.geometry?.materials = [beaconMaterial]
            beacon.position = SCNVector3(Float(tx.x), 3.85, Float(tx.y))
            scene.rootNode.addChildNode(beacon)
            beacon.runAction(SCNAction.repeatForever(SCNAction.sequence([
                SCNAction.fadeOut(duration: 0.7),
                SCNAction.fadeIn(duration: 0.7)
            ])))
        }

        // Code: 5 random digits; each clue spot shows its digit as a
        // glowing marker lying on the floor. (No code on the roof.)
        var rng = SystemRandomNumberGenerator()
        let codeDigits: [Int] = level.codeClues.isEmpty
            ? []
            : (0..<5).map { _ in Int.random(in: 0...9, using: &rng) }
        var clueNodes: [SCNNode] = []
        for (index, point) in level.codeClues.enumerated() {
            guard index < codeDigits.count else { break }
            let text = SCNText(string: "\(codeDigits[index])", extrusionDepth: 0.02)
            text.font = UIFont.systemFont(ofSize: 12)
            let clueMaterial = SCNMaterial()
            clueMaterial.diffuse.contents = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
            clueMaterial.emission.contents = UIColor(red: 0.9, green: 0.65, blue: 0.1, alpha: 1)
            text.materials = [clueMaterial]
            let clue = SCNNode(geometry: text)
            clue.scale = SCNVector3(0.03, 0.03, 0.03)
            clue.position = SCNVector3(Float(point.x), 0.04, Float(point.y))
            clue.eulerAngles.x = -Float.pi / 2
            clue.name = "clue_\(index)"
            scene.rootNode.addChildNode(clue)
            clueNodes.append(clue)
        }

        let player = FirstPersonController(start: level.playerSpawn)
        rig.eulerAngles.y = Float(player.yaw)

        let controller = FPSceneController(
            level: level, input: input, player: player,
            rig: rig, cameraNode: cameraNode,
            soundHunters: soundHunters, sightHunters: sightHunters,
            spotLight: spot, stoneNodes: stoneNodes, batteryNodes: batteryNodes,
            stickNode: stickNode, breakables: breakables,
            entryDoor: entryDoor, exitLampMaterial: exitLampMaterial,
            generatorLampMaterial: generatorLampMaterial,
            sparkNodes: sparkNodes,
            codeDigits: codeDigits, clueNodes: clueNodes,
            onCaught: onCaught, onModeChange: onModeChange,
            onLightChange: onLightChange, onLightLevelChange: onLightLevelChange,
            onStonesChange: onStonesChange,
            onObjective: onObjective, onCodeChange: onCodeChange,
            onStickChange: onStickChange, onFloorComplete: onFloorComplete,
            onInteractPrompt: onInteractPrompt, onBreath: onBreath,
            onHidden: onHidden, onSendProgress: onSendProgress,
            onGameWin: onGameWin
        )
        controller.start()
        return FPSceneBundle(scene: scene, cameraNode: cameraNode, controller: controller)
    }

    // MARK: - World building

    private static func floorMaterial(for surface: SurfaceType) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        switch surface {
        case .carpet:
            material.diffuse.contents = UIColor(red: 0.1, green: 0.12, blue: 0.1, alpha: 1)
            material.roughness.contents = 1.0
            material.metalness.contents = 0.0
        case .concrete:
            material.diffuse.contents = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            material.roughness.contents = 0.92
            material.metalness.contents = 0.02
        case .metal:
            material.diffuse.contents = UIColor(red: 0.2, green: 0.22, blue: 0.27, alpha: 1)
            material.roughness.contents = 0.45
            material.metalness.contents = 0.85
        case .glass:
            material.diffuse.contents = UIColor(red: 0.3, green: 0.38, blue: 0.46, alpha: 1)
            material.roughness.contents = 0.25
            material.metalness.contents = 0.1
        }
        return material
    }

    private static func buildFloorsAndCeiling(scene: SCNScene, level: LevelData3D) {
        for zone in level.zones {
            guard zone.rect.width > 0.1, zone.rect.height > 0.1 else { continue }
            let floor = SCNNode(geometry: SCNBox(
                width: CGFloat(zone.rect.width), height: 0.1,
                length: CGFloat(zone.rect.height), chamferRadius: 0))
            floor.geometry?.materials = [floorMaterial(for: zone.surface)]
            floor.position = SCNVector3(Float(zone.rect.midX), -0.05, Float(zone.rect.midY))
            floor.receivesShadow = true
            floor.name = "floor_\(zone.name)"
            scene.rootNode.addChildNode(floor)

            if zone.surface == .glass {
                addGlassShards(scene: scene, rect: zone.rect)
            }
        }

        // The roof has no ceiling — open dawn sky.
        guard level.transmitterPosition == nil else { return }
        let bounds = level.worldBounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let ceiling = SCNNode(geometry: SCNBox(
            width: CGFloat(bounds.width), height: 0.1,
            length: CGFloat(bounds.height), chamferRadius: 0))
        let ceilingMaterial = SCNMaterial()
        ceilingMaterial.lightingModel = .physicallyBased
        ceilingMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        ceilingMaterial.roughness.contents = 0.95
        ceiling.geometry?.materials = [ceilingMaterial]
        ceiling.position = SCNVector3(
            Float(bounds.midX), Float(level.wallHeight) + 0.05, Float(bounds.midY))
        scene.rootNode.addChildNode(ceiling)
    }

    // Broken-glass shards: small reflective boxes, deterministic layout.
    private static func addGlassShards(scene: SCNScene, rect: CGRect) {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextRandom() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / 65535.0
        }
        let shardMaterial = SCNMaterial()
        shardMaterial.lightingModel = .physicallyBased
        shardMaterial.diffuse.contents = UIColor(red: 0.65, green: 0.78, blue: 0.88, alpha: 1)
        shardMaterial.roughness.contents = 0.12
        shardMaterial.metalness.contents = 0.2

        for _ in 0..<26 {
            let size = 0.05 + nextRandom() * 0.14
            let shard = SCNNode(geometry: SCNBox(
                width: size, height: 0.012, length: size * 0.7, chamferRadius: 0))
            shard.geometry?.materials = [shardMaterial]
            let x = CGFloat(rect.minX) + nextRandom() * CGFloat(rect.width)
            let z = CGFloat(rect.minY) + nextRandom() * CGFloat(rect.height)
            shard.position = SCNVector3(Float(x), 0.012, Float(z))
            shard.eulerAngles.y = Float(nextRandom() * .pi)
            scene.rootNode.addChildNode(shard)
        }
    }

    private static func buildWalls(scene: SCNScene, level: LevelData3D) {
        let wallMaterial = SCNMaterial()
        wallMaterial.lightingModel = .physicallyBased
        wallMaterial.diffuse.contents = UIColor(red: 0.19, green: 0.19, blue: 0.22, alpha: 1)
        wallMaterial.roughness.contents = 0.85
        wallMaterial.metalness.contents = 0.05

        func addWall(rect: CGRect) {
            guard rect.width > 0.05, rect.height > 0.05 else { return }
            let wall = SCNNode(geometry: SCNBox(
                width: CGFloat(rect.width), height: CGFloat(level.wallHeight),
                length: CGFloat(rect.height), chamferRadius: 0))
            wall.geometry?.materials = [wallMaterial]
            wall.position = SCNVector3(
                Float(rect.midX), Float(level.wallHeight) / 2, Float(rect.midY))
            wall.receivesShadow = true
            scene.rootNode.addChildNode(wall)
        }

        for wall in level.walls {
            addWall(rect: wall)
        }
        let b = level.worldBounds
        let t: CGFloat = 0.3
        addWall(rect: CGRect(x: b.minX - t, y: b.minY - t, width: b.width + 2 * t, height: t))
        addWall(rect: CGRect(x: b.minX - t, y: b.maxY, width: b.width + 2 * t, height: t))
        addWall(rect: CGRect(x: b.minX - t, y: b.minY, width: t, height: b.height))
        addWall(rect: CGRect(x: b.maxX, y: b.minY, width: t, height: b.height))
    }

    private static func buildLights(scene: SCNScene, level: LevelData3D, ambientIntensity: CGFloat) {
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.14, green: 0.18, blue: 0.28, alpha: 1)
        ambient.intensity = ambientIntensity
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let spots: [(x: Float, z: Float, flicker: Bool)] = [
            (13, 8.1, true),
            (3.8, 13.5, false)
        ]
        for spot in spots {
            let node = SCNNode()
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(red: 1.0, green: 0.16, blue: 0.1, alpha: 1)
            light.intensity = 26
            light.attenuationStartDistance = 1
            light.attenuationEndDistance = 11
            node.light = light
            node.position = SCNVector3(spot.x, 2.9, spot.z)
            scene.rootNode.addChildNode(node)
            if spot.flicker {
                addFlicker(node: node, light: light)
            }
        }
    }

    // Runs on the light's own node (already in the scene), so it ticks.
    private static func addFlicker(node: SCNNode, light: SCNLight) {
        let baseIntensity: CGFloat = 26
        let flicker = SCNAction.customAction(duration: 0.09) { _, elapsed in
            light.intensity = elapsed < 0.045 ? baseIntensity * 0.25 : baseIntensity
        }
        let sequence = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.wait(duration: 2.4),
            flicker,
            SCNAction.wait(duration: 0.35),
            flicker
        ]))
        node.runAction(sequence, forKey: "flicker")
    }

    private static func buildDust(scene: SCNScene, level: LevelData3D) {
        let bounds = level.worldBounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let system = SCNParticleSystem()
        system.birthRate = 6
        system.particleLifeSpan = 9
        system.particleSize = 0.015
        system.particleColor = UIColor.white.withAlphaComponent(0.3)
        system.emitterShape = SCNBox(
            width: CGFloat(bounds.width), height: 2.6,
            length: CGFloat(bounds.height), chamferRadius: 0)
        system.particleVelocity = 0.04
        system.particleVelocityVariation = 0.03
        system.spreadingAngle = 180
        let node = SCNNode()
        node.position = SCNVector3(Float(bounds.midX), 1.5, Float(bounds.midY))
        node.addParticleSystem(system)
        scene.rootNode.addChildNode(node)
    }
}

// Per-frame game loop for the first-person scene (renderer delegate).
final class FPSceneController: NSObject, SCNSceneRendererDelegate {
    private let level: LevelData3D
    private let input: FPInputState
    private let player: FirstPersonController
    private let rig: SCNNode
    private let cameraNode: SCNNode
    private let soundHunters: [DeathAngel3D]
    private let sightHunters: [LightHunter3D]
    private let spotLight: SCNLight
    private let onCaught: () -> Void
    private let onModeChange: (MovementMode) -> Void
    private let onLightChange: (Bool, Int) -> Void
    private let onLightLevelChange: (String) -> Void
    private let onStonesChange: (Int) -> Void
    private let onObjective: (String) -> Void
    private let onCodeChange: ([Int?]) -> Void
    private let onStickChange: (Bool) -> Void
    private let onFloorComplete: () -> Void
    private let onInteractPrompt: (String?) -> Void
    private let onBreath: (Int, Bool) -> Void
    private let onHidden: (Bool) -> Void
    private let onSendProgress: (Int, Bool) -> Void
    private let onGameWin: () -> Void

    private var sceneTime: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var noiseTimer: TimeInterval = 0
    private var lastSurface: SurfaceType = .carpet
    private var lastMode: MovementMode = .idle
    private var caughtFired = false
    private var heartbeatTimer: TimeInterval = 0
    private var noiseToken: UUID?

    // Stones
    private var stones: [(position: CGPoint, node: SCNNode, taken: Bool)]
    private var stoneInventory = 0
    private let stoneCap = 5
    private struct ThrownStone {
        let node: SCNNode
        let from: CGPoint
        let to: CGPoint
        var t: CGFloat = 0
    }
    private var thrownStone: ThrownStone?

    // Flashlight: three levels (steady / strong / flash strobe).
    private var lightOn = true
    private var battery: CGFloat = 100
    private var flashLevel: FlashLevel = .steady
    private var strobeHigh = true
    private var effectiveLightOn = true
    private var lastPublishedLightOn: Bool?
    private var lastPublishedPercent: Int?
    private var batteries: [(position: CGPoint, node: SCNNode, taken: Bool)]

    // Stick + breakables
    private let stickNode: SCNNode
    private var hasStick = false
    private var breakables: [(prop: BreakableProp, node: SCNNode, broken: Bool)]
    private var swingCooldown: TimeInterval = 0

    // Building flow: entry door locks behind the player; the 5-digit
    // code (clues near/under/behind monsters) opens the exit door.
    private let entryDoor: SCNNode
    private var doorLocked = false
    private let exitLampMaterial: SCNMaterial
    private let generatorLampMaterial: SCNMaterial
    private let sparkNodes: [Int: SCNNode]
    private let codeDigits: [Int]
    private var foundDigits: [Int?]
    private let clueNodes: [SCNNode]
    private var exitUnlocked = false
    private var floorCompleteFired = false

    // Generator + hiding
    private var codeComplete = false
    private var generatorOn = false
    private var crankTimeLeft: TimeInterval?
    private var crankNoiseTimer: TimeInterval = 0
    private var hiddenLockerIndex: Int?
    private var preHidePosition: CGPoint?
    private var breath: CGFloat = 0
    private var lastPrompt: String?
    private var promptInitialized = false
    private var lastBreathValue = -1
    private var lastBreathVisible = false

    // Floor hazards
    private var hazardReadyAt: [TimeInterval] = []
    private var hazardLightUntil: TimeInterval = 0

    // Roof finale: sending the last signal
    private var sending = false
    private var signalSent = false
    private var sendLeft: TimeInterval = 10
    private var sendPulseTimer: TimeInterval = 0
    private var lastSendPercent = -1

    init(level: LevelData3D, input: FPInputState, player: FirstPersonController,
         rig: SCNNode, cameraNode: SCNNode,
         soundHunters: [DeathAngel3D], sightHunters: [LightHunter3D],
         spotLight: SCNLight, stoneNodes: [SCNNode], batteryNodes: [SCNNode],
         stickNode: SCNNode, breakables: [(prop: BreakableProp, node: SCNNode)],
         entryDoor: SCNNode, exitLampMaterial: SCNMaterial,
         generatorLampMaterial: SCNMaterial,
         sparkNodes: [Int: SCNNode],
         codeDigits: [Int], clueNodes: [SCNNode],
         onCaught: @escaping () -> Void,
         onModeChange: @escaping (MovementMode) -> Void,
         onLightChange: @escaping (Bool, Int) -> Void,
         onLightLevelChange: @escaping (String) -> Void,
         onStonesChange: @escaping (Int) -> Void,
         onObjective: @escaping (String) -> Void,
         onCodeChange: @escaping ([Int?]) -> Void,
         onStickChange: @escaping (Bool) -> Void,
         onFloorComplete: @escaping () -> Void,
         onInteractPrompt: @escaping (String?) -> Void,
         onBreath: @escaping (Int, Bool) -> Void,
         onHidden: @escaping (Bool) -> Void,
         onSendProgress: @escaping (Int, Bool) -> Void,
         onGameWin: @escaping () -> Void) {
        self.level = level
        self.input = input
        self.player = player
        self.rig = rig
        self.cameraNode = cameraNode
        self.soundHunters = soundHunters
        self.sightHunters = sightHunters
        self.spotLight = spotLight
        self.stones = zip(level.stones, stoneNodes).map { (position: $0.0, node: $0.1, taken: false) }
        self.batteries = zip(level.batteries, batteryNodes).map { (position: $0.0, node: $0.1, taken: false) }
        self.stickNode = stickNode
        self.breakables = breakables.map { (prop: $0.prop, node: $0.node, broken: false) }
        self.entryDoor = entryDoor
        self.exitLampMaterial = exitLampMaterial
        self.generatorLampMaterial = generatorLampMaterial
        self.sparkNodes = sparkNodes
        self.hazardReadyAt = Array(repeating: 0, count: level.hazards.count)
        self.codeDigits = codeDigits
        self.foundDigits = Array(repeating: nil, count: codeDigits.count)
        self.clueNodes = clueNodes
        self.onCaught = onCaught
        self.onModeChange = onModeChange
        self.onLightChange = onLightChange
        self.onLightLevelChange = onLightLevelChange
        self.onStonesChange = onStonesChange
        self.onObjective = onObjective
        self.onCodeChange = onCodeChange
        self.onStickChange = onStickChange
        self.onFloorComplete = onFloorComplete
        self.onInteractPrompt = onInteractPrompt
        self.onBreath = onBreath
        self.onHidden = onHidden
        self.onSendProgress = onSendProgress
        self.onGameWin = onGameWin
        super.init()
    }

    func start() {
        noiseToken = NoiseBus.shared.addListener { [weak self] event in
            guard let self = self else { return }
            for hunter in self.soundHunters {
                hunter.onNoise(event)
            }
        }
        AudioManager.shared.updateListener(position: player.position)
        publishLight()
        let levelName = flashLevel.arabicName
        DispatchQueue.main.async { [weak self] in self?.onLightLevelChange(levelName) }
        publishStones()
        if level.transmitterPosition != nil {
            publishObjective("وصلت السطح! فعّل جهاز الإرسال وأرسل الإشارة الأخيرة — بس صوته راح يجيب كل الوحوش")
        } else {
            publishObjective("تقدّم وادخل المبنى… الباب سيُقفل خلفك")
        }
        publishCode()
    }

    deinit {
        if let token = noiseToken {
            NoiseBus.shared.removeListener(token)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdate == 0 {
            lastUpdate = time
            return
        }
        var dt = time - lastUpdate
        lastUpdate = time
        guard dt > 0 else { return }
        dt = min(dt, 0.05)
        sceneTime += dt
        swingCooldown = max(0, swingCooldown - dt)

        // Walls for this frame: the entry gap becomes solid once locked.
        var walls = level.walls
        if doorLocked {
            walls.append(level.entryDoorRect)
        }

        // Look + move
        let look = input.consumeLookDelta()
        player.applyLook(dx: look.dx, dy: look.dy)
        player.update(dt: dt,
                      move: hiddenLockerIndex == nil ? input.moveVector() : .zero,
                      sprint: input.isSprinting(),
                      walls: walls, worldBounds: level.worldBounds)
        rig.position = SCNVector3(Float(player.position.x), 0, Float(player.position.y))
        rig.eulerAngles.y = Float(player.yaw)
        cameraNode.eulerAngles.x = Float(player.pitch)

        if player.mode != lastMode {
            lastMode = player.mode
            let mode = player.mode
            DispatchQueue.main.async { [weak self] in self?.onModeChange(mode) }
        }

        updateDoorAndCode()
        updateInteract()
        updateGenerator(dt: dt)
        updateSending(dt: dt)
        updateHazards()
        updateFlashlight(dt: dt)
        if hiddenLockerIndex == nil {
            updateStones(dt: dt)
            updateBatteries()
            updateStickAndBreakables()
        }

        // Footstep noise
        let surface = level.surface(at: player.position)
        if surface == .glass, lastSurface != .glass, player.mode != .idle {
            emitNoise(radiusOverride: 10)
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

        // Monsters: sound hunters via the noise bus; sight hunters sense
        // the player's light every frame.
        for hunter in soundHunters {
            hunter.updateAI(dt: dt, now: sceneTime)
        }
        for hunter in sightHunters {
            // A locker blocks sight completely; a spark flash counts as
            // light exactly like the flashlight does.
            if hiddenLockerIndex == nil {
                hunter.sense(playerPosition: player.position,
                             lightOn: effectiveLightOn || sceneTime < hazardLightUntil,
                             now: sceneTime)
            }
            hunter.updateAI(dt: dt, now: sceneTime)
        }

        // Catch check + heartbeat use the nearest active monster.
        var nearest: CGFloat = .greatestFiniteMagnitude
        var nearestSound: CGFloat = .greatestFiniteMagnitude
        var anyCaught = false
        for hunter in soundHunters where hunter.state != .dormant {
            let d = SafeMath.distance(hunter.floorPosition, player.position)
            nearest = min(nearest, d)
            nearestSound = min(nearestSound, d)
            if hiddenLockerIndex != nil {
                // Hidden: a sound hunter catches you only if it tracked
                // your hiding spot (a gasp, a careless noise) and comes
                // right up to the locker.
                if d < 0.7, let known = hunter.lastKnownPosition,
                   SafeMath.distance(known, player.position) < 1.5 {
                    anyCaught = true
                }
            } else if d < 0.85 {
                anyCaught = true
            }
        }
        for hunter in sightHunters {
            let d = SafeMath.distance(hunter.floorPosition, player.position)
            nearest = min(nearest, d)
            if hiddenLockerIndex == nil, d < 0.85 { anyCaught = true }
        }
        if !caughtFired, anyCaught {
            caughtFired = true
            DispatchQueue.main.async { [weak self] in self?.onCaught() }
        }
        updateBreath(dt: dt, nearestSound: nearestSound)

        AudioManager.shared.updateListener(position: player.position)

        if nearest < 7 {
            heartbeatTimer += dt
            let proximity = 1 - nearest / 7
            let interval = 1.1 - 0.75 * TimeInterval(proximity)
            if heartbeatTimer >= interval {
                heartbeatTimer = 0
                HapticsManager.shared.heartbeat(proximity: Float(proximity))
            }
        } else {
            heartbeatTimer = 0
        }
    }

    // MARK: - Building flow

    private func updateDoorAndCode() {
        // Entry door locks once the player is inside (past the door).
        if !doorLocked, player.position.y > level.entryDoorRect.midY + 1.2 {
            doorLocked = true
            let targetX = Float(level.entryDoorRect.midX)
            entryDoor.runAction(SCNAction.moveTo(
                x: CGFloat(targetX), y: 1.3, z: CGFloat(level.entryDoorRect.midY),
                duration: 0.5))
            let doorPos = CGPoint(x: level.entryDoorRect.midX, y: level.entryDoorRect.midY)
            AudioManager.shared.play(.doorSlam, at: doorPos)
            entryDoor.runAction(SCNAction.sequence([
                SCNAction.wait(duration: 0.55),
                SCNAction.run { _ in
                    AudioManager.shared.play(.doorLock, at: doorPos)
                }
            ]))
            if level.transmitterPosition == nil {
                publishObjective("انقفل الباب! فتّش الطابق عن رمز من ٥ أرقام مخبأة قرب الوحوش — ولا تنسَ المولد")
            }
        }

        // Code clues: walk over a glowing digit to learn it.
        if !exitUnlocked {
            for index in clueNodes.indices where foundDigits[index] == nil {
                guard index < level.codeClues.count, index < codeDigits.count else { continue }
                if SafeMath.distance(player.position, level.codeClues[index]) < 0.85 {
                    foundDigits[index] = codeDigits[index]
                    clueNodes[index].isHidden = true
                    AudioManager.shared.play(.codeDigitFound, at: player.position)
                    AudioManager.shared.play(.keypadBeep, at: player.position)
                    publishCode()
                    let foundCount = foundDigits.compactMap { $0 }.count
                    if foundCount >= codeDigits.count {
                        codeComplete = true
                        refreshExitState()
                        if !exitUnlocked {
                            publishObjective("اكتمل الرمز! بس الباب يحتاج كهرباء — شغّل المولد بالمخزن")
                        }
                    } else {
                        publishObjective("وجدت رقماً (\(foundCount) من \(codeDigits.count)) — كمّل التفتيش")
                    }
                }
            }
        }

        // Reaching the open exit door completes the floor.
        if exitUnlocked, !floorCompleteFired,
           SafeMath.distance(player.position, level.exitDoorPosition) < 1.1 {
            floorCompleteFired = true
            DispatchQueue.main.async { [weak self] in self?.onFloorComplete() }
        }
    }

    private func publishObjective(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onObjective(text) }
    }

    private func publishCode() {
        let snapshot = foundDigits
        DispatchQueue.main.async { [weak self] in self?.onCodeChange(snapshot) }
    }

    // MARK: - Generator, hiding, hazards

    // The exit door needs BOTH the full code and generator power.
    // Lamp: red = neither, orange = one of them, green = open.
    private func refreshExitState() {
        if codeComplete, generatorOn {
            if !exitUnlocked {
                exitUnlocked = true
                exitLampMaterial.diffuse.contents = UIColor.green
                exitLampMaterial.emission.contents = UIColor.green
                AudioManager.shared.play(.doorUnlock, at: level.exitDoorPosition)
                publishObjective("الرمز كامل والكهرباء واصلة — باب الطابق الثاني انفتح! توجّه له بأقصى الشمال")
            }
        } else if codeComplete || generatorOn {
            let orange = UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1)
            exitLampMaterial.diffuse.contents = orange
            exitLampMaterial.emission.contents = orange
        }
    }

    private func updateGenerator(dt: TimeInterval) {
        guard let left = crankTimeLeft else { return }
        crankNoiseTimer += dt
        if crankNoiseTimer >= 0.4 {
            crankNoiseTimer = 0
            // The crank is LOUD, in pulses, from the generator's spot.
            NoiseBus.shared.publish(NoiseEvent(
                position: level.generatorPosition, radius: 15, time: sceneTime))
        }
        let newLeft = left - dt
        if newLeft <= 0 {
            crankTimeLeft = nil
            generatorOn = true
            generatorLampMaterial.diffuse.contents = UIColor.green
            generatorLampMaterial.emission.contents = UIColor.green
            AudioManager.shared.play(.generatorOn, at: level.generatorPosition)
            refreshExitState()
            if !exitUnlocked, !codeComplete {
                publishObjective("المولد اشتغل والكهرباء وصلت للباب — بس الرمز بعده ناقص، كمّل التفتيش")
            }
        } else {
            crankTimeLeft = newLeft
        }
    }

    // Sending the last signal: 10 seconds of loud pulses from the
    // transmitter. The player does not have to stand still — but the
    // hunters are all coming to the mast.
    private func updateSending(dt: TimeInterval) {
        guard sending, !signalSent, let tx = level.transmitterPosition else { return }
        sendLeft -= dt
        sendPulseTimer += dt
        if sendPulseTimer >= 1 {
            sendPulseTimer = 0
            NoiseBus.shared.publish(NoiseEvent(position: tx, radius: 13, time: sceneTime))
            AudioManager.shared.play(.transmissionHum, at: tx)
        }
        let percent = Int(((10 - sendLeft) / 10 * 100).rounded())
        if percent != lastSendPercent {
            lastSendPercent = percent
            let p = percent
            DispatchQueue.main.async { [weak self] in self?.onSendProgress(p, true) }
        }
        if sendLeft <= 0 {
            sending = false
            signalSent = true
            AudioManager.shared.play(.signalSent, at: tx)
            DispatchQueue.main.async { [weak self] in
                self?.onSendProgress(100, false)
                self?.onGameWin()
            }
        }
    }

    private func nearestLockerIndex() -> Int? {
        var best: Int?
        var bestDistance: CGFloat = 1.7
        for (index, locker) in level.lockers.enumerated() {
            let d = SafeMath.distance(player.position, locker.position)
            if d < bestDistance {
                bestDistance = d
                best = index
            }
        }
        return best
    }

    private func updateInteract() {
        let tapped = input.consumeInteract()
        var prompt: String?

        if hiddenLockerIndex != nil {
            prompt = "اخرج من الخزانة"
            if tapped { exitLocker() }
        } else if let index = nearestLockerIndex() {
            prompt = "اختبئ بالخزانة"
            if tapped { enterLocker(index) }
        } else if let tx = level.transmitterPosition, !sending, !signalSent,
                  SafeMath.distance(player.position, tx) < 1.9 {
            prompt = "أرسل الإشارة الأخيرة"
            if tapped {
                sending = true
                sendLeft = 10
                sendPulseTimer = 1 // first pulse fires at once
                lastSendPercent = -1
                publishObjective("الإشارة تُرسل… ١٠ ثوانٍ وكل الوحوش جاية. انجو بنفسك!")
            }
        } else if level.transmitterPosition == nil, !generatorOn, crankTimeLeft == nil,
                  SafeMath.distance(player.position, level.generatorPosition) < 1.7 {
            prompt = "شغّل المولد"
            if tapped {
                crankTimeLeft = 3
                crankNoiseTimer = 0.4 // first loud pulse fires at once
                AudioManager.shared.play(.generatorCrank, at: level.generatorPosition)
                publishObjective("المولد يشتغل… صوته عالي والوحوش سمعت! اختبئ أو اهرب")
            }
        }

        if prompt != lastPrompt || !promptInitialized {
            promptInitialized = true
            lastPrompt = prompt
            let current = prompt
            DispatchQueue.main.async { [weak self] in self?.onInteractPrompt(current) }
        }
    }

    private func enterLocker(_ index: Int) {
        guard level.lockers.indices.contains(index) else { return }
        hiddenLockerIndex = index
        preHidePosition = player.position
        let locker = level.lockers[index]
        player.teleport(to: locker.position)
        player.face(direction: locker.facing)
        breath = 0
        AudioManager.shared.play(.lockerHide, at: player.position)
        DispatchQueue.main.async { [weak self] in self?.onHidden(true) }
    }

    private func exitLocker() {
        guard let index = hiddenLockerIndex,
              level.lockers.indices.contains(index) else {
            hiddenLockerIndex = nil
            return
        }
        let locker = level.lockers[index]
        let stepOut = CGPoint(
            x: locker.position.x + locker.facing.x * 0.95,
            y: locker.position.y + locker.facing.y * 0.95)
        player.teleport(to: preHidePosition ?? stepOut)
        hiddenLockerIndex = nil
        preHidePosition = nil
        breath = 0
        AudioManager.shared.play(.lockerOpen, at: player.position)
        DispatchQueue.main.async { [weak self] in self?.onHidden(false) }
        publishBreath(force: true)
    }

    // While hidden, a nearby sound hunter fills your breath meter.
    // Holding your breath slows it almost to a stop; if it fills, you
    // gasp — a noise right at your locker.
    private func updateBreath(dt: TimeInterval, nearestSound: CGFloat) {
        guard hiddenLockerIndex != nil else { return }
        if nearestSound < 6 {
            breath += (input.isHoldingBreath() ? 2 : 16) * CGFloat(dt)
        } else {
            breath -= 10 * CGFloat(dt)
        }
        breath = max(0, min(100, breath))
        if breath >= 100 {
            breath = 55
            NoiseBus.shared.publish(NoiseEvent(
                position: player.position, radius: 8, time: sceneTime))
            AudioManager.shared.play(.breathGasp, at: player.position)
            HapticsManager.shared.pulse(intensity: 0.7, sharpness: 0.8)
        }
        publishBreath(force: false, nearestSound: nearestSound)
    }

    private func publishBreath(force: Bool, nearestSound: CGFloat = .greatestFiniteMagnitude) {
        let visible = hiddenLockerIndex != nil && (breath > 1 || nearestSound < 6)
        let value = Int(breath.rounded())
        guard force || value != lastBreathValue || visible != lastBreathVisible else { return }
        lastBreathValue = value
        lastBreathVisible = visible
        DispatchQueue.main.async { [weak self] in self?.onBreath(value, visible) }
    }

    // Floor hazards: step on one by mistake and it betrays you.
    private func updateHazards() {
        guard hiddenLockerIndex == nil else { return }
        for index in level.hazards.indices {
            let hazard = level.hazards[index]
            guard sceneTime >= hazardReadyAt[index] else { continue }
            guard SafeMath.distance(player.position, hazard.position) < 0.55 else { continue }
            hazardReadyAt[index] = sceneTime + 5
            switch hazard.kind {
            case .cans:
                AudioManager.shared.play(.metalClank, at: hazard.position)
                NoiseBus.shared.publish(NoiseEvent(
                    position: hazard.position, radius: 9.5, time: sceneTime))
                HapticsManager.shared.pulse(intensity: 0.5, sharpness: 0.7)
            case .sparkWire:
                AudioManager.shared.play(.sparkZap, at: hazard.position)
                // For 1.6s you are lit — the sight hunter sees you.
                hazardLightUntil = sceneTime + 1.6
                if let node = sparkNodes[index], let light = node.light {
                    light.intensity = 500
                    node.runAction(SCNAction.sequence([
                        SCNAction.wait(duration: 1.2),
                        SCNAction.run { _ in light.intensity = 0 }
                    ]))
                }
                HapticsManager.shared.pulse(intensity: 0.6, sharpness: 0.9)
            }
        }
    }

    // MARK: - Flashlight & stones

    private func updateFlashlight(dt: TimeInterval) {
        if input.consumeFlashlightToggle() {
            if battery > 0 {
                lightOn.toggle()
            }
            publishLight()
        }
        if input.consumeLightCycle(), battery > 0 {
            flashLevel = flashLevel.next
            for hunter in sightHunters {
                hunter.lightDetectionRange = flashLevel.detectionRange
            }
            let name = flashLevel.arabicName
            DispatchQueue.main.async { [weak self] in self?.onLightLevelChange(name) }
            publishLight()
        }

        // Strobe phase for the flash level: mostly lit, brief dips.
        strobeHigh = flashLevel != .flash || sin(sceneTime * 22) > -0.2
        effectiveLightOn = lightOn && strobeHigh && battery > 0
        applyLight()

        if lightOn, battery > 0 {
            battery -= flashLevel.drainPerSecond * CGFloat(dt)
            if battery <= 0 {
                battery = 0
                lightOn = false
                effectiveLightOn = false
                applyLight()
            }
            publishLight()
        }
    }

    private func applyLight() {
        guard lightOn, battery > 0 else {
            spotLight.intensity = 0
            return
        }
        switch flashLevel {
        case .steady:
            spotLight.intensity = 450
            spotLight.spotAngle = 38
        case .strong:
            spotLight.intensity = 850
            spotLight.spotAngle = 52
        case .flash:
            spotLight.intensity = strobeHigh ? 450 : 25
            spotLight.spotAngle = 38
        }
    }

    private func updateBatteries() {
        guard battery < 100 else { return }
        for index in batteries.indices where !batteries[index].taken {
            if SafeMath.distance(player.position, batteries[index].position) < 0.7 {
                batteries[index].taken = true
                batteries[index].node.isHidden = true
                battery = min(100, battery + 40)
                AudioManager.shared.play(.pickupItem, at: player.position)
                publishLight()
                break
            }
        }
    }

    private func publishLight() {
        let percent = Int(battery.rounded())
        guard lastPublishedLightOn != lightOn || lastPublishedPercent != percent else { return }
        lastPublishedLightOn = lightOn
        lastPublishedPercent = percent
        let on = lightOn
        DispatchQueue.main.async { [weak self] in self?.onLightChange(on, percent) }
    }

    private func publishStones() {
        let count = stoneInventory
        DispatchQueue.main.async { [weak self] in self?.onStonesChange(count) }
    }

    private func updateStones(dt: TimeInterval) {
        if stoneInventory < stoneCap {
            for index in stones.indices where !stones[index].taken {
                if SafeMath.distance(player.position, stones[index].position) < 0.7 {
                    stones[index].taken = true
                    stones[index].node.isHidden = true
                    stoneInventory += 1
                    AudioManager.shared.play(.pickupItem, at: player.position)
                    publishStones()
                    break
                }
            }
        }

        if thrownStone == nil, input.consumeThrow(), stoneInventory > 0 {
            stoneInventory -= 1
            publishStones()
            let start = CGPoint(
                x: player.position.x + player.forward.x * 0.4,
                y: player.position.y + player.forward.y * 0.4
            )
            var target = CGPoint(
                x: player.position.x + player.forward.x * 6,
                y: player.position.y + player.forward.y * 6
            )
            target = target.clamped(to: level.worldBounds.insetBy(dx: 0.3, dy: 0.3))
            let node = SCNNode(geometry: SCNSphere(radius: 0.09))
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.42, green: 0.4, blue: 0.38, alpha: 1)
            node.geometry?.materials = [material]
            node.position = SCNVector3(Float(start.x), 1.1, Float(start.y))
            rig.parent?.addChildNode(node)
            thrownStone = ThrownStone(node: node, from: start, to: target)
            AudioManager.shared.play(.throwItem, at: start)
        }

        if var flight = thrownStone {
            flight.t += CGFloat(dt) / 0.55
            if flight.t >= 1 {
                let landing = NoiseEvent(position: flight.to, radius: 11, time: sceneTime)
                NoiseBus.shared.publish(landing)
                AudioManager.shared.play(.throwItem, at: flight.to)
                flight.node.position = SCNVector3(Float(flight.to.x), 0.05, Float(flight.to.y))
                let cleanup = SCNAction.sequence([
                    SCNAction.wait(duration: 2.0),
                    SCNAction.fadeOut(duration: 0.4),
                    SCNAction.removeFromParentNode()
                ])
                flight.node.runAction(cleanup)
                thrownStone = nil
            } else {
                let t = flight.t
                let x = flight.from.x + (flight.to.x - flight.from.x) * t
                let z = flight.from.y + (flight.to.y - flight.from.y) * t
                let y = 1.1 - 1.05 * t + sin(t * .pi) * 0.35
                flight.node.position = SCNVector3(Float(x), Float(y), Float(z))
                thrownStone = flight
            }
        }
    }

    // MARK: - Stick & breakables

    private func updateStickAndBreakables() {
        // Pickup: walk over the stick.
        if !hasStick,
           SafeMath.distance(player.position, level.stickSpawn) < 0.8 {
            hasStick = true
            stickNode.isHidden = true
            AudioManager.shared.play(.pickupItem, at: player.position)
            DispatchQueue.main.async { [weak self] in self?.onStickChange(true) }
        }

        guard hasStick, swingCooldown <= 0, input.consumeSwing() else { return }
        swingCooldown = 0.7
        AudioManager.shared.play(.stickSwing, at: player.position)
        HapticsManager.shared.pulse(intensity: 0.4, sharpness: 0.6)

        // The strike lands ~1.3m in front of the player.
        let hitPoint = CGPoint(
            x: player.position.x + player.forward.x * 1.3,
            y: player.position.y + player.forward.y * 1.3
        )

        // Break the nearest intact prop in reach — very loud on purpose:
        // the player makes the noise, then runs before hunters arrive.
        var bestIndex: Int?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for index in breakables.indices where !breakables[index].broken {
            let d = SafeMath.distance(hitPoint, breakables[index].prop.position)
            if d < 1.6, d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }

        if let index = bestIndex {
            breakables[index].broken = true
            let broken = breakables[index]
            switch broken.prop.kind {
            case .crate:
                broken.node.scale = SCNVector3(1, 0.4, 1)
                broken.node.position.y = 0.14
                AudioManager.shared.play(.breakWood, at: broken.prop.position)
                NoiseBus.shared.publish(NoiseEvent(
                    position: broken.prop.position, radius: 12.5, time: sceneTime))
            case .glassPanel:
                broken.node.isHidden = true
                AudioManager.shared.play(.breakGlass, at: broken.prop.position)
                NoiseBus.shared.publish(NoiseEvent(
                    position: broken.prop.position, radius: 16, time: sceneTime))
            }
        } else {
            // A plain hit on wall/floor: loud, but less than a break.
            AudioManager.shared.play(.stickHit, at: hitPoint)
            NoiseBus.shared.publish(NoiseEvent(
                position: hitPoint, radius: 9, time: sceneTime))
        }
    }

    // MARK: - Noise

    private func emitNoise(radiusOverride: CGFloat?) {
        let radius = radiusOverride ?? player.noiseRadius(on: level.surface(at: player.position))
        guard radius > 0 else { return }
        let event = NoiseEvent(position: player.position, radius: radius, time: sceneTime)
        NoiseBus.shared.publish(event)
        if event.level >= .loud {
            for hunter in soundHunters {
                hunter.recordHabit(zone: level.zoneName(at: player.position))
            }
        }
    }
}
