import Foundation
import CoreHaptics
import UIKit

// Haptics that can never crash the game:
// - CoreHaptics is only touched when the hardware reports supportsHaptics.
// - Engine creation/start is wrapped in do/catch; on any failure we fall
//   back to UIFeedbackGenerator, and if that is unavailable we stay silent.
final class HapticsManager {
    static let shared = HapticsManager()

    private var engine: CHHapticEngine?
    private var engineReady = false
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var isEnabled: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: "settings.haptics") as? Bool {
                return stored
            }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: "settings.haptics") }
    }

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engineReady = false
            return
        }
        do {
            let created = try CHHapticEngine()
            try created.start()
            created.resetHandler = { [weak self] in
                // Engine was reset by the system; try to restart quietly.
                do { try self?.engine?.start() } catch { self?.engineReady = false }
            }
            engine = created
            engineReady = true
        } catch {
            engine = nil
            engineReady = false
        }
    }

    // One short pulse. intensity/sharpness are clamped to 0...1.
    func pulse(intensity: Float, sharpness: Float = 0.5) {
        guard isEnabled else { return }
        let clampedIntensity = min(max(intensity, 0), 1)
        let clampedSharpness = min(max(sharpness, 0), 1)

        if engineReady, let engine = engine {
            do {
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: clampedSharpness)
                    ],
                    relativeTime: 0
                )
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
                return
            } catch {
                engineReady = false
                // Fall through to the generator fallback below.
            }
        }
        impact.impactOccurred(intensity: CGFloat(clampedIntensity))
    }

    // Heartbeat tick that gets stronger as danger gets closer (0...1).
    func heartbeat(proximity: Float) {
        let p = min(max(proximity, 0), 1)
        guard p > 0.05 else { return }
        pulse(intensity: 0.25 + 0.75 * p, sharpness: 0.7)
    }
}
