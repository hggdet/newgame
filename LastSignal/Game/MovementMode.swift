import Foundation
import CoreGraphics

// How the player is moving, decided by joystick push + sprint button:
// gentle push = sneak (silent), full push = walk, sprint button = run.
enum MovementMode: String {
    case idle
    case sneak
    case walk
    case run

    // Speed in meters per second (first-person scale).
    // First build shipped at roughly half of natural FPS pace
    // (walk 1.7 / run 3.1) and felt annoyingly slow on device;
    // these are standard first-person speeds.
    var speedMeters: CGFloat {
        switch self {
        case .idle: return 0
        case .sneak: return 1.5
        case .walk: return 3.4
        case .run: return 6.0
        }
    }

    var arabicName: String {
        switch self {
        case .idle: return "واقف"
        case .sneak: return "تسلل"
        case .walk: return "مشي"
        case .run: return "ركض"
        }
    }
}
