import Foundation

// Campaign progress, stored in UserDefaults: the highest floor the
// player has unlocked (Continue starts there) and whether the last
// signal has ever been sent. Deliberately tiny and fail-safe — a
// missing value just means floor 1.
enum GameProgress {
    private static let unlockedKey = "lastsignal.highestUnlockedFloor"
    private static let wonKey = "lastsignal.hasWon"

    static var highestUnlocked: Int {
        let stored = UserDefaults.standard.integer(forKey: unlockedKey)
        return min(4, max(1, stored))
    }

    static func unlock(floor: Int) {
        guard floor >= 2, floor <= 4, floor > highestUnlocked else { return }
        UserDefaults.standard.set(floor, forKey: unlockedKey)
    }

    static var hasWon: Bool {
        UserDefaults.standard.bool(forKey: wonKey)
    }

    static func markWon() {
        UserDefaults.standard.set(true, forKey: wonKey)
        unlock(floor: 4)
    }
}
