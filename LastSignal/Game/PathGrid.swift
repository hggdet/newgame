import Foundation
import CoreGraphics

// Grid pathfinding over a floor's wall footprints (his rule: the
// monsters must TRACK the player around walls, never walk through
// them). One shared grid per floor; BFS over 0.5m cells with wall
// clearance for the monster's body, then line-of-sight smoothing so
// paths hug natural routes instead of zig-zagging cell to cell.
// Fully fail-safe: any degenerate input yields an empty path and the
// caller falls back to a wall-clamped direct step.
final class PathGrid {
    private let bounds: CGRect
    private let cell: CGFloat
    private let cols: Int
    private let rows: Int
    private let blockedCells: [Bool]
    private let solidWalls: [CGRect] // walls inflated by body clearance

    init(worldBounds: CGRect, walls: [CGRect], cellSize: CGFloat = 0.5, clearance: CGFloat = 0.38) {
        bounds = worldBounds
        cell = cellSize
        cols = max(1, Int(ceil(worldBounds.width / cellSize)))
        rows = max(1, Int(ceil(worldBounds.height / cellSize)))
        solidWalls = walls.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        var grid = [Bool](repeating: false, count: cols * rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let center = CGPoint(
                    x: worldBounds.minX + (CGFloat(col) + 0.5) * cellSize,
                    y: worldBounds.minY + (CGFloat(row) + 0.5) * cellSize)
                grid[row * cols + col] = solidWalls.contains { $0.contains(center) }
            }
        }
        blockedCells = grid
    }

    // A point the monster's body cannot occupy.
    func isBlocked(_ point: CGPoint) -> Bool {
        if !bounds.contains(point) { return true }
        return solidWalls.contains { $0.contains(point) }
    }

    func findPath(from start: CGPoint, to goal: CGPoint) -> [CGPoint] {
        let (sc, sr) = cellIndex(of: start)
        let (gc, gr) = cellIndex(of: goal)
        guard let s = nearestWalkable(col: sc, row: sr),
              let g = nearestWalkable(col: gc, row: gr) else { return [] }
        if s.0 == g.0 && s.1 == g.1 { return [goal] }

        let total = cols * rows
        var prev = [Int](repeating: -1, count: total)
        var visited = [Bool](repeating: false, count: total)
        var queue: [Int] = []
        let startIndex = s.1 * cols + s.0
        let goalIndex = g.1 * cols + g.0
        visited[startIndex] = true
        queue.append(startIndex)
        var head = 0
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == goalIndex { break }
            let cc = current % cols
            let cr = current / cols
            for (dc, dr) in dirs {
                let nc = cc + dc
                let nr = cr + dr
                guard nc >= 0, nr >= 0, nc < cols, nr < rows else { continue }
                let ni = nr * cols + nc
                if visited[ni] || blockedCells[ni] { continue }
                visited[ni] = true
                prev[ni] = current
                queue.append(ni)
            }
        }
        guard visited[goalIndex] else { return [] }

        var cells: [Int] = []
        var cursor = goalIndex
        while cursor != -1 {
            cells.append(cursor)
            cursor = prev[cursor]
        }
        cells.reverse()
        var points = cells.map { center(ofCol: $0 % cols, row: $0 / cols) }
        if !points.isEmpty && !isBlocked(goal) {
            points[points.count - 1] = goal
        }
        return smooth(points, from: start)
    }

    // True when a straight walk from a to b never enters a wall.
    func segmentClear(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let distance = SafeMath.distance(a, b)
        let steps = max(1, Int(distance / 0.2))
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: a.x + (b.x - a.x) * t,
                                y: a.y + (b.y - a.y) * t)
            if isBlocked(point) { return false }
        }
        return true
    }

    private func smooth(_ points: [CGPoint], from start: CGPoint) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = []
        var anchor = start
        var index = 0
        while index < points.count {
            var furthest = index
            var probe = index
            while probe < points.count && segmentClear(anchor, points[probe]) {
                furthest = probe
                probe += 1
            }
            result.append(points[furthest])
            anchor = points[furthest]
            index = furthest + 1
        }
        return result
    }

    private func cellIndex(of point: CGPoint) -> (Int, Int) {
        let col = Int((point.x - bounds.minX) / cell)
        let row = Int((point.y - bounds.minY) / cell)
        return (min(max(col, 0), cols - 1), min(max(row, 0), rows - 1))
    }

    private func center(ofCol col: Int, row: Int) -> CGPoint {
        CGPoint(x: bounds.minX + (CGFloat(col) + 0.5) * cell,
                y: bounds.minY + (CGFloat(row) + 0.5) * cell)
    }

    private func nearestWalkable(col: Int, row: Int) -> (Int, Int)? {
        if !blockedCells[row * cols + col] { return (col, row) }
        for radius in 1...6 {
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dc), abs(dr)) == radius {
                    let nc = col + dc
                    let nr = row + dr
                    if nc >= 0, nr >= 0, nc < cols, nr < rows,
                       !blockedCells[nr * cols + nc] {
                        return (nc, nr)
                    }
                }
            }
        }
        return nil
    }
}
