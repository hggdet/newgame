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
    var speedMeters: CGFloat {
        switch self {
        case .idle: return 0
        case .sneak: return 0.85
        case .walk: return 1.7
        case .run: return 3.1
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
