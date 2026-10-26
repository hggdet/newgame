import Foundation
import CoreGraphics

// How loud a noise is, derived from its radius so the whole game agrees.
enum NoiseLevel: Int, Comparable {
    case silent = 0
    case quiet = 1
    case moderate = 2
    case loud = 3
    case extreme = 4

    static func < (lhs: NoiseLevel, rhs: NoiseLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(radius: CGFloat) -> NoiseLevel {
        guard radius.isSafeFinite, radius > 0 else { return .silent }
        switch radius {
        case ..<80: return .quiet
        case ..<160: return .moderate
        case ..<260: return .loud
        default: return .extreme
        }
    }

    var arabicName: String {
        switch self {
        case .silent: return "صامت"
        case .quiet: return "هادئ"
        case .moderate: return "متوسط"
        case .loud: return "عالٍ"
        case .extreme: return "مدوٍّ"
        }
    }
}

// One noise in the world. Monsters hear an event only when they stand
// inside its radius — they learn the ORIGIN, never the player's true
// position beyond the moment of the noise.
struct NoiseEvent {
    let position: CGPoint
    let radius: CGFloat
    let level: NoiseLevel
    let time: TimeInterval

    init(position: CGPoint, radius: CGFloat, time: TimeInterval) {
        self.position = position
        self.radius = max(0, radius)
        self.level = NoiseLevel.from(radius: radius)
        self.time = time
    }
}

// Floor materials: metal is loud, carpet is quiet, broken glass is
// dangerous even while sneaking.
enum SurfaceType: String {
    case carpet
    case concrete
    case metal
    case glass

    var arabicName: String {
        switch self {
        case .carpet: return "سجاد"
        case .concrete: return "خرسانة"
        case .metal: return "معدن"
        case .glass: return "زجاج مكسور"
        }
    }
}

struct SurfaceZone {
    let rect: CGRect
    let surface: SurfaceType
    let name: String
}

// Publish/subscribe bus for noise. The scene publishes; monsters subscribe.
// Listeners are held by token so they can be removed safely.
final class NoiseBus {
    static let shared = NoiseBus()

    private var listeners: [UUID: (NoiseEvent) -> Void] = [:]
    private(set) var lastEvent: NoiseEvent?

    private init() {}

    @discardableResult
    func addListener(_ listener: @escaping (NoiseEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    func publish(_ event: NoiseEvent) {
        lastEvent = event
        // Copy first: a listener may unsubscribe while being called.
        let current = Array(listeners.values)
        for listener in current {
            listener(event)
        }
    }
}
