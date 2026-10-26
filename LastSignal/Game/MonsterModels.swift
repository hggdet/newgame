import Foundation
import SceneKit
import UIKit

// PLACEHOLDER MODELS — MonsterModels.swift
// Original designs built from SceneKit primitives (no external assets):
// silhouettes *inspired by* the references, never copies of them.
// Replace these builders with real rigged models later; the game logic
// only ever touches the returned root node.

// PBR materials shared by the monster builders.
enum MonsterMaterials {
    static func wetSkin() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1)
        material.roughness.contents = 0.38 // wet sheen
        material.metalness.contents = 0.08
        return material
    }

    static func bone() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.55, green: 0.5, blue: 0.42, alpha: 1)
        material.roughness.contents = 0.7
        material.metalness.contents = 0.0
        return material
    }
}

enum MonsterModels {

    // The sound hunter: a quadruped crawler with very long front arms,
    // clawed hands, an eyeless head and a heavy jaw. ~1.1m at the shoulder,
    // ~2.3m long. Head faces the node's -Z.
    static func soundHunter() -> SCNNode {
        let root = SCNNode()
        root.name = "soundHunter"
        let skin = MonsterMaterials.wetSkin()
        let bone = MonsterMaterials.bone()

        func part(_ geometry: SCNGeometry, material: SCNMaterial,
                  position: SCNVector3, euler: SCNVector3 = SCNVector3Zero,
                  scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.eulerAngles = euler
            node.scale = scale
            node.castsShadow = true
            root.addChildNode(node)
            return node
        }

        // Torso: a horizontal capsule, hunched.
        _ = part(SCNCapsule(capRadius: 0.26, height: 1.15), material: skin,
                 position: SCNVector3(0, 0.78, 0.1),
                 euler: SCNVector3(Float.pi / 2.3, 0, 0))
        // Hips.
        _ = part(SCNSphere(radius: 0.3), material: skin,
                 position: SCNVector3(0, 0.72, 0.62),
                 scale: SCNVector3(0.95, 0.9, 1.1))
        // Head: elongated, eyeless, low in front of the torso (faces -Z).
        _ = part(SCNSphere(radius: 0.21), material: skin,
                 position: SCNVector3(0, 0.66, -0.52),
                 scale: SCNVector3(0.85, 0.8, 1.45))
        // Heavy jaw.
        _ = part(SCNBox(width: 0.2, height: 0.09, length: 0.34, chamferRadius: 0.02),
                 material: bone,
                 position: SCNVector3(0, 0.52, -0.58))
        // Teeth: small cones under the jaw line.
        for index in 0..<5 {
            let x = -0.07 + Float(index) * 0.035
            _ = part(SCNCone(topRadius: 0, bottomRadius: 0.006, height: 0.045),
                     material: bone,
                     position: SCNVector3(x, 0.47, -0.66),
                     euler: SCNVector3(Float.pi, 0, 0))
        }
        // Long front arms: upper arm down-forward, forearm to the ground,
        // three claw cones per hand. (The defining silhouette.)
        for side: Float in [-1, 1] {
            _ = part(SCNCylinder(radius: 0.055, height: 0.78), material: skin,
                     position: SCNVector3(0.3 * side, 0.55, -0.42),
                     euler: SCNVector3(0.5, 0, 0.25 * side))
            _ = part(SCNCylinder(radius: 0.04, height: 0.85), material: skin,
                     position: SCNVector3(0.42 * side, 0.3, -0.72),
                     euler: SCNVector3(0.25, 0, 0.1 * side))
            for claw in 0..<3 {
                let spread = Float(claw - 1) * 0.07
                _ = part(SCNCone(topRadius: 0, bottomRadius: 0.012, height: 0.16),
                         material: bone,
                         position: SCNVector3(0.44 * side + spread, 0.05, -0.95),
                         euler: SCNVector3(-Float.pi / 2.4, 0, 0))
            }
        }
        // Hind legs: shorter, bent back.
        for side: Float in [-1, 1] {
            _ = part(SCNCylinder(radius: 0.07, height: 0.6), material: skin,
                     position: SCNVector3(0.28 * side, 0.5, 0.72),
                     euler: SCNVector3(-0.6, 0, 0.2 * side))
            _ = part(SCNCylinder(radius: 0.05, height: 0.55), material: skin,
                     position: SCNVector3(0.3 * side, 0.22, 0.92),
                     euler: SCNVector3(0.3, 0, 0))
        }

        // Idle breathing: a slow, subtle torso-scale loop (cheap, safe).
        let breathe = SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.scale(to: 1.03, duration: 1.4),
                SCNAction.scale(to: 1.0, duration: 1.4)
            ])
        )
        breathe.timingMode = .easeInEaseOut
        root.runAction(breathe, forKey: "breathing")
        return root
    }

    // The sight hunter: a tall, thin standing figure (~2.2m) whose face is
    // a ring of closed petals that reads as a flower head. Long arms hang
    // past its knees, ending in claws. Head faces the node's -Z.
    // (Petal-opening animation arrives with the light system polish.)
    static func sightHunter() -> SCNNode {
        let root = SCNNode()
        root.name = "sightHunter"
        let skin = MonsterMaterials.wetSkin()
        let bone = MonsterMaterials.bone()

        func part(_ geometry: SCNGeometry, material: SCNMaterial,
                  position: SCNVector3, euler: SCNVector3 = SCNVector3Zero,
                  scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.eulerAngles = euler
            node.scale = scale
            node.castsShadow = true
            root.addChildNode(node)
            return node
        }

        // Legs: long and thin.
        for side: Float in [-1, 1] {
            _ = part(SCNCylinder(radius: 0.05, height: 1.05), material: skin,
                     position: SCNVector3(0.13 * side, 0.52, 0))
            _ = part(SCNBox(width: 0.11, height: 0.05, length: 0.26, chamferRadius: 0.01),
                     material: skin,
                     position: SCNVector3(0.13 * side, 0.03, -0.05))
        }
        // Torso: vertical capsule, ribcage-slim.
        _ = part(SCNCapsule(capRadius: 0.19, height: 0.72), material: skin,
                 position: SCNVector3(0, 1.42, 0),
                 scale: SCNVector3(0.9, 1, 0.7))
        // Long arms hanging past the knees, three claws each.
        for side: Float in [-1, 1] {
            _ = part(SCNCylinder(radius: 0.04, height: 1.15), material: skin,
                     position: SCNVector3(0.3 * side, 1.12, 0),
                     euler: SCNVector3(0, 0, 0.06 * side))
            for claw in 0..<3 {
                let spread = Float(claw - 1) * 0.045
                _ = part(SCNCone(topRadius: 0, bottomRadius: 0.01, height: 0.17),
                         material: bone,
                         position: SCNVector3(0.31 * side + spread, 0.47, -0.02),
                         euler: SCNVector3(Float.pi, 0, 0))
            }
        }
        // Head core.
        _ = part(SCNSphere(radius: 0.13), material: skin,
                 position: SCNVector3(0, 1.98, 0))
        // Petals: five flattened cones in a ring, closed around the face.
        for index in 0..<5 {
            let angle = Float(index) / 5 * Float.pi * 2
            let x = sin(angle) * 0.11
            let y = cos(angle) * 0.11
            _ = part(SCNCone(topRadius: 0.005, bottomRadius: 0.055, height: 0.34),
                     material: skin,
                     position: SCNVector3(x, 1.98 + y, -0.1),
                     euler: SCNVector3(-Float.pi / 2.6, 0, -angle))
        }

        let sway = SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0, z: 0.02, duration: 2.2),
                SCNAction.rotateBy(x: 0, y: 0, z: -0.02, duration: 2.2)
            ])
        )
        sway.timingMode = .easeInEaseOut
        root.runAction(sway, forKey: "sway")
        return root
    }
}
