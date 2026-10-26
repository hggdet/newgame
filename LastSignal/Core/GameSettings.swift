import Foundation
import CoreGraphics

// Player-facing settings (menu's Settings panel). Stored in
// UserDefaults; the audio and haptics managers already read their
// own keys, so this is a thin shared facade over the same storage.
enum GameSettings {
    static var soundVolume: Float {
        get { AudioManager.shared.volume }
        set { AudioManager.shared.volume = newValue }
    }

    static var hapticsEnabled: Bool {
        get { HapticsManager.shared.isEnabled }
        set { HapticsManager.shared.isEnabled = newValue }
    }

    // Look sensitivity multiplier for the first-person camera.
    static var lookSensitivity: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "settings.lookSensitivity")
            return stored > 0 ? CGFloat(stored) : 1
        }
        set {
            let clamped = min(max(newValue, 0.4), 2)
            UserDefaults.standard.set(Double(clamped), forKey: "settings.lookSensitivity")
        }
    }
}
