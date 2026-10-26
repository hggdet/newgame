import Foundation
import CoreGraphics

// Data-driven level description for the first-person build.
// Coordinates are meters on the floor plane: a rect's x/y map to world
// X/Z, its width/height map to world X extent / Z extent.
// Four levels: floors 1-3 of the building (code + generator + exit
// door) and the roof (floor 4: reach the transmitter and send the
// last signal). Darkness and monster speed scale per floor.

struct SurfaceZone3D {
    let rect: CGRect
    let surface: SurfaceType // from NoiseBus.swift (shared)
    let name: String
}

// A prop the player can smash with the stick: breaking it makes a very
// loud noise — a distraction the player creates, then runs from.
struct BreakableProp {
    enum Kind {
        case crate      // wood: loud thud + splinters
        case glassPanel // glass: extreme shatter
    }
    let position: CGPoint
    let kind: Kind
}

// A hiding locker. `facing` is the floor-plane direction the hidden
// player looks toward (and steps out to).
struct LockerSpot {
    let position: CGPoint
    let facing: CGPoint
}

// A floor hazard: step on it by mistake and it betrays you — cans
// clatter loudly; a sparking broken wire flashes light that the sight
// hunter can see, exactly as if your flashlight were on.
struct FloorHazard {
    enum Kind {
        case cans      // sound trap
        case sparkWire // light trap
    }
    let position: CGPoint
    let kind: Kind
}

// One hunter's placement: where it starts and the loop it patrols.
// Sound hunters start dormant unless `startsAwake` (only the one
// sleeping near a code digit sleeps, per the design).
struct HunterSpawn {
    let spawn: CGPoint
    let waypoints: [CGPoint]
    let startsAwake: Bool
}

struct LevelData3D {
    let floorNumber: Int // 1, 2, 3, and 4 = the roof
    let worldBounds: CGRect // (0,0) to (width, depth) in meters
    let wallHeight: CGFloat
    let zones: [SurfaceZone3D] // glass first: it wins overlaps
    let walls: [CGRect] // solid wall footprints (collision + visuals)
    let playerSpawn: CGPoint
    let soundHunters: [HunterSpawn] // 3 per floor
    let sightHunters: [HunterSpawn] // 3 per floor
    let monsterSpeedScale: CGFloat
    let stones: [CGPoint] // throwable pebbles scattered on the floor
    let stickSpawn: CGPoint
    let breakables: [BreakableProp]
    let entryDoorRect: CGRect // doorway gap; becomes solid once locked
    let exitDoorPosition: CGPoint
    let codeClues: [CGPoint] // exactly 5 on floors 1-3; empty on the roof
    let generatorPosition: CGPoint // powers the exit door; loud to start
    let lockers: [LockerSpot]
    let hazards: [FloorHazard]
    let batteries: [CGPoint] // flashlight battery pickups (+40%)
    let transmitterPosition: CGPoint? // roof only: send the last signal

    func surface(at point: CGPoint) -> SurfaceType {
        for zone in zones where zone.rect.contains(point) {
            return zone.surface
        }
        return .concrete
    }

    func zoneName(at point: CGPoint) -> String {
        for zone in zones where zone.rect.contains(point) {
            return zone.name
        }
        return "خارج المناطق"
    }

    static func level(forFloor floor: Int) -> LevelData3D {
        switch floor {
        case 2: return floor2
        case 3: return floor3
        case 4: return roof
        default: return testStation
        }
    }

    // MARK: - Floor 1 (the test station layout, now the real floor 1)

    static let testStation: LevelData3D = {
        let zones: [SurfaceZone3D] = [
            SurfaceZone3D(rect: CGRect(x: 10, y: 6.4, width: 5.2, height: 3.0),
                          surface: .glass, name: "زجاج الممر"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 0, width: 7.2, height: 6.2),
                          surface: .carpet, name: "المدخل"),
            SurfaceZone3D(rect: CGRect(x: 7.2, y: 0, width: 18.8, height: 6.2),
                          surface: .concrete, name: "قاعة"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 6.2, width: 26, height: 3.8),
                          surface: .metal, name: "ممر معدني"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 10, width: 7.6, height: 7),
                          surface: .metal, name: "المخزن"),
            SurfaceZone3D(rect: CGRect(x: 7.6, y: 10, width: 18.4, height: 7),
                          surface: .concrete, name: "المختبرات")
        ]

        // Interior walls, each with a doorway gap.
        let walls: [CGRect] = [
            CGRect(x: 0, y: 6.05, width: 10, height: 0.3),
            CGRect(x: 15.2, y: 6.05, width: 10.8, height: 0.3),
            CGRect(x: 7.6, y: 9.85, width: 7.4, height: 0.3),
            CGRect(x: 16.4, y: 9.85, width: 9.6, height: 0.3),
            CGRect(x: 0, y: 9.85, width: 7.6, height: 0.3),
            CGRect(x: 7.45, y: 10, width: 0.3, height: 3.4),
            CGRect(x: 7.45, y: 14.8, width: 0.3, height: 2.2)
        ]

        return LevelData3D(
            floorNumber: 1,
            worldBounds: CGRect(x: 0, y: 0, width: 26, height: 17),
            wallHeight: 3.2,
            zones: zones,
            walls: walls,
            playerSpawn: CGPoint(x: 2.2, y: 2.2),
            soundHunters: [
                HunterSpawn(spawn: CGPoint(x: 3.8, y: 13.5), waypoints: [
                    CGPoint(x: 3.8, y: 13.5), CGPoint(x: 2, y: 11), CGPoint(x: 6, y: 15.5)
                ], startsAwake: false), // sleeps in storage, over digit 0
                HunterSpawn(spawn: CGPoint(x: 22, y: 8.1), waypoints: [
                    CGPoint(x: 22, y: 8.1), CGPoint(x: 16, y: 8.1), CGPoint(x: 24, y: 8.1)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 20, y: 14), waypoints: [
                    CGPoint(x: 20, y: 14), CGPoint(x: 12, y: 15.5), CGPoint(x: 23, y: 11.5)
                ], startsAwake: true)
            ],
            sightHunters: [
                HunterSpawn(spawn: CGPoint(x: 12, y: 13), waypoints: [
                    CGPoint(x: 12, y: 13), CGPoint(x: 18, y: 12), CGPoint(x: 10, y: 15.5)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 16, y: 3), waypoints: [
                    CGPoint(x: 16, y: 3), CGPoint(x: 22, y: 4.5), CGPoint(x: 10, y: 2.5)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 5, y: 8.1), waypoints: [
                    CGPoint(x: 5, y: 8.1), CGPoint(x: 9, y: 8.1), CGPoint(x: 2.5, y: 8.1)
                ], startsAwake: true)
            ],
            monsterSpeedScale: 1.0,
            stones: [
                CGPoint(x: 3, y: 4), CGPoint(x: 5.5, y: 2), CGPoint(x: 9, y: 3),
                CGPoint(x: 14, y: 5), CGPoint(x: 8, y: 8), CGPoint(x: 12.5, y: 8),
                CGPoint(x: 18, y: 7.5), CGPoint(x: 22, y: 8.5), CGPoint(x: 12, y: 13),
                CGPoint(x: 20, y: 15), CGPoint(x: 2, y: 15.5)
            ],
            stickSpawn: CGPoint(x: 2.8, y: 3.4),
            breakables: [
                BreakableProp(position: CGPoint(x: 8.5, y: 4.5), kind: .crate),
                BreakableProp(position: CGPoint(x: 18, y: 12), kind: .crate),
                BreakableProp(position: CGPoint(x: 4, y: 8.2), kind: .crate),
                BreakableProp(position: CGPoint(x: 15, y: 3), kind: .glassPanel),
                BreakableProp(position: CGPoint(x: 23, y: 14.5), kind: .glassPanel)
            ],
            entryDoorRect: CGRect(x: 10, y: 6.05, width: 5.2, height: 0.3),
            exitDoorPosition: CGPoint(x: 20, y: 16.6),
            codeClues: [
                CGPoint(x: 3.8, y: 13.9),  // 0: under the sleeping sound hunter
                CGPoint(x: 12, y: 11.6),   // 1: behind the labs sight hunter
                CGPoint(x: 20.6, y: 8.7),  // 2: near the corridor sound hunter
                CGPoint(x: 20, y: 12.4),   // 3: behind the labs sound hunter
                CGPoint(x: 6.4, y: 8.1)    // 4: near the corridor sight hunter
            ],
            generatorPosition: CGPoint(x: 5.6, y: 15.6),
            lockers: [
                LockerSpot(position: CGPoint(x: 1.2, y: 16.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 10.3, y: 16.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 24.6, y: 11.2), facing: CGPoint(x: -1, y: 0)),
                LockerSpot(position: CGPoint(x: 13, y: 9.5), facing: CGPoint(x: 0, y: -1))
            ],
            hazards: [
                FloorHazard(position: CGPoint(x: 9.5, y: 8), kind: .cans),
                FloorHazard(position: CGPoint(x: 15.5, y: 12.5), kind: .cans),
                FloorHazard(position: CGPoint(x: 18, y: 14), kind: .cans),
                FloorHazard(position: CGPoint(x: 13.5, y: 14), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 23, y: 8), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 7, y: 11.5), kind: .sparkWire)
            ],
            batteries: [
                CGPoint(x: 4.5, y: 12.5),
                CGPoint(x: 22.5, y: 15.5),
                CGPoint(x: 16.5, y: 7)
            ],
            transmitterPosition: nil
        )
    }()

    // MARK: - Floor 2 (bigger: server room, offices, electrical)

    static let floor2: LevelData3D = {
        let zones: [SurfaceZone3D] = [
            SurfaceZone3D(rect: CGRect(x: 13, y: 6.4, width: 4.5, height: 3.0),
                          surface: .glass, name: "زجاج الممر"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 0, width: 8.6, height: 6.2),
                          surface: .carpet, name: "المدخل"),
            SurfaceZone3D(rect: CGRect(x: 8.6, y: 0, width: 21.4, height: 6.2),
                          surface: .concrete, name: "قاعة"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 6.2, width: 30, height: 3.8),
                          surface: .metal, name: "ممر معدني"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 10, width: 10.6, height: 10),
                          surface: .metal, name: "غرفة الخوادم"),
            SurfaceZone3D(rect: CGRect(x: 10.6, y: 10, width: 11.4, height: 10),
                          surface: .carpet, name: "مكاتب"),
            SurfaceZone3D(rect: CGRect(x: 22, y: 10, width: 8, height: 10),
                          surface: .concrete, name: "الكهرباء")
        ]
        let walls: [CGRect] = [
            CGRect(x: 0, y: 6.05, width: 10, height: 0.3),
            CGRect(x: 15.2, y: 6.05, width: 14.8, height: 0.3),
            CGRect(x: 0, y: 9.85, width: 12, height: 0.3),
            CGRect(x: 13.4, y: 9.85, width: 16.6, height: 0.3),
            CGRect(x: 10.45, y: 10, width: 0.3, height: 3.6),
            CGRect(x: 10.45, y: 15.2, width: 0.3, height: 4.8),
            CGRect(x: 21.85, y: 10, width: 0.3, height: 5.5),
            CGRect(x: 21.85, y: 17, width: 0.3, height: 3)
        ]
        return LevelData3D(
            floorNumber: 2,
            worldBounds: CGRect(x: 0, y: 0, width: 30, height: 20),
            wallHeight: 3.2,
            zones: zones,
            walls: walls,
            playerSpawn: CGPoint(x: 2.2, y: 2.2),
            soundHunters: [
                HunterSpawn(spawn: CGPoint(x: 4, y: 17.5), waypoints: [
                    CGPoint(x: 4, y: 17.5), CGPoint(x: 2.5, y: 12), CGPoint(x: 7, y: 16)
                ], startsAwake: false), // sleeps in the server room
                HunterSpawn(spawn: CGPoint(x: 25, y: 8.1), waypoints: [
                    CGPoint(x: 25, y: 8.1), CGPoint(x: 18, y: 8.1), CGPoint(x: 28, y: 8.1)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 16, y: 13), waypoints: [
                    CGPoint(x: 16, y: 13), CGPoint(x: 12, y: 17), CGPoint(x: 20, y: 11)
                ], startsAwake: true)
            ],
            sightHunters: [
                HunterSpawn(spawn: CGPoint(x: 20, y: 3), waypoints: [
                    CGPoint(x: 20, y: 3), CGPoint(x: 26, y: 4.5), CGPoint(x: 12, y: 2.5)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 6, y: 8.1), waypoints: [
                    CGPoint(x: 6, y: 8.1), CGPoint(x: 10, y: 8.1), CGPoint(x: 3, y: 8.1)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 24, y: 12), waypoints: [
                    CGPoint(x: 24, y: 12), CGPoint(x: 16, y: 15), CGPoint(x: 27, y: 17)
                ], startsAwake: true)
            ],
            monsterSpeedScale: 1.07,
            stones: [
                CGPoint(x: 3, y: 4), CGPoint(x: 6, y: 2), CGPoint(x: 10, y: 3),
                CGPoint(x: 15, y: 5), CGPoint(x: 8, y: 8), CGPoint(x: 14.5, y: 8),
                CGPoint(x: 20, y: 7.5), CGPoint(x: 26, y: 8.5), CGPoint(x: 13, y: 13),
                CGPoint(x: 19, y: 16), CGPoint(x: 3, y: 16), CGPoint(x: 25, y: 13)
            ],
            stickSpawn: CGPoint(x: 2.8, y: 3.4),
            breakables: [
                BreakableProp(position: CGPoint(x: 9, y: 4.5), kind: .crate),
                BreakableProp(position: CGPoint(x: 19, y: 12), kind: .crate),
                BreakableProp(position: CGPoint(x: 5, y: 8.2), kind: .crate),
                BreakableProp(position: CGPoint(x: 24, y: 17), kind: .crate),
                BreakableProp(position: CGPoint(x: 16, y: 3), kind: .glassPanel),
                BreakableProp(position: CGPoint(x: 12, y: 19), kind: .glassPanel)
            ],
            entryDoorRect: CGRect(x: 10, y: 6.05, width: 5.2, height: 0.3),
            exitDoorPosition: CGPoint(x: 26, y: 19.55),
            codeClues: [
                CGPoint(x: 4, y: 18.1),    // 0: under the sleeping sound hunter
                CGPoint(x: 24.5, y: 12.6), // 1: near the electrical sight hunter
                CGPoint(x: 25.6, y: 8.7),  // 2: near the corridor sound hunter
                CGPoint(x: 15.5, y: 16.5), // 3: behind the offices sound hunter
                CGPoint(x: 6.6, y: 8.1)    // 4: near the corridor sight hunter
            ],
            generatorPosition: CGPoint(x: 26.5, y: 18.5), // electrical room
            lockers: [
                LockerSpot(position: CGPoint(x: 1.2, y: 19.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 11.2, y: 19.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 20.5, y: 10.6), facing: CGPoint(x: 0, y: 1)),
                LockerSpot(position: CGPoint(x: 29.3, y: 14), facing: CGPoint(x: -1, y: 0))
            ],
            hazards: [
                FloorHazard(position: CGPoint(x: 11, y: 8), kind: .cans),
                FloorHazard(position: CGPoint(x: 17, y: 12.5), kind: .cans),
                FloorHazard(position: CGPoint(x: 24, y: 16), kind: .cans),
                FloorHazard(position: CGPoint(x: 5, y: 8), kind: .cans),
                FloorHazard(position: CGPoint(x: 14, y: 14), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 27, y: 8), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 8, y: 12), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 20, y: 18), kind: .sparkWire)
            ],
            batteries: [
                CGPoint(x: 5, y: 18.8),  // server room, near the sleeper
                CGPoint(x: 27, y: 11)    // electrical
            ],
            transmitterPosition: nil
        )
    }()

    // MARK: - Floor 3 (the darkest: two labs and a vault)

    static let floor3: LevelData3D = {
        let zones: [SurfaceZone3D] = [
            SurfaceZone3D(rect: CGRect(x: 14, y: 6.4, width: 5, height: 3.0),
                          surface: .glass, name: "زجاج الممر"),
            SurfaceZone3D(rect: CGRect(x: 24, y: 10.3, width: 4, height: 3),
                          surface: .glass, name: "زجاج المختبر"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 0, width: 9.4, height: 6.2),
                          surface: .carpet, name: "المدخل"),
            SurfaceZone3D(rect: CGRect(x: 9.4, y: 0, width: 22.6, height: 6.2),
                          surface: .concrete, name: "قاعة"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 6.2, width: 32, height: 3.8),
                          surface: .metal, name: "ممر معدني"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 10, width: 11.6, height: 12),
                          surface: .concrete, name: "مختبر أ"),
            SurfaceZone3D(rect: CGRect(x: 11.6, y: 10, width: 11.4, height: 12),
                          surface: .metal, name: "مختبر ب"),
            SurfaceZone3D(rect: CGRect(x: 23, y: 10, width: 9, height: 12),
                          surface: .metal, name: "الخزنة")
        ]
        let walls: [CGRect] = [
            CGRect(x: 0, y: 6.05, width: 11, height: 0.3),
            CGRect(x: 16.2, y: 6.05, width: 15.8, height: 0.3),
            CGRect(x: 0, y: 9.85, width: 14, height: 0.3),
            CGRect(x: 15.4, y: 9.85, width: 16.6, height: 0.3),
            CGRect(x: 11.45, y: 10, width: 0.3, height: 4.4),
            CGRect(x: 11.45, y: 16, width: 0.3, height: 6),
            CGRect(x: 22.85, y: 10, width: 0.3, height: 6),
            CGRect(x: 22.85, y: 17.6, width: 0.3, height: 4.4)
        ]
        return LevelData3D(
            floorNumber: 3,
            worldBounds: CGRect(x: 0, y: 0, width: 32, height: 22),
            wallHeight: 3.2,
            zones: zones,
            walls: walls,
            playerSpawn: CGPoint(x: 2.2, y: 2.2),
            soundHunters: [
                HunterSpawn(spawn: CGPoint(x: 27.5, y: 20), waypoints: [
                    CGPoint(x: 27.5, y: 20), CGPoint(x: 24.5, y: 13), CGPoint(x: 30, y: 17)
                ], startsAwake: false), // sleeps in the vault
                HunterSpawn(spawn: CGPoint(x: 27, y: 8.1), waypoints: [
                    CGPoint(x: 27, y: 8.1), CGPoint(x: 20, y: 8.1), CGPoint(x: 30, y: 8.1)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 17, y: 15), waypoints: [
                    CGPoint(x: 17, y: 15), CGPoint(x: 13, y: 19), CGPoint(x: 21, y: 12)
                ], startsAwake: true)
            ],
            sightHunters: [
                HunterSpawn(spawn: CGPoint(x: 22, y: 3), waypoints: [
                    CGPoint(x: 22, y: 3), CGPoint(x: 28, y: 4.5), CGPoint(x: 14, y: 2.5)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 5, y: 16), waypoints: [
                    CGPoint(x: 5, y: 16), CGPoint(x: 9, y: 20), CGPoint(x: 2.5, y: 12)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 6, y: 8.1), waypoints: [
                    CGPoint(x: 6, y: 8.1), CGPoint(x: 11, y: 8.1), CGPoint(x: 3, y: 8.1)
                ], startsAwake: true)
            ],
            monsterSpeedScale: 1.15,
            stones: [
                CGPoint(x: 3, y: 4), CGPoint(x: 6.5, y: 2), CGPoint(x: 11, y: 3),
                CGPoint(x: 17, y: 5), CGPoint(x: 8, y: 8), CGPoint(x: 16.5, y: 8),
                CGPoint(x: 22, y: 7.5), CGPoint(x: 29, y: 8.5), CGPoint(x: 13, y: 14),
                CGPoint(x: 20, y: 18), CGPoint(x: 4, y: 19), CGPoint(x: 27, y: 14)
            ],
            stickSpawn: CGPoint(x: 2.8, y: 3.4),
            breakables: [
                BreakableProp(position: CGPoint(x: 9.5, y: 4.5), kind: .crate),
                BreakableProp(position: CGPoint(x: 20, y: 13), kind: .crate),
                BreakableProp(position: CGPoint(x: 5, y: 8.2), kind: .crate),
                BreakableProp(position: CGPoint(x: 26, y: 19), kind: .crate),
                BreakableProp(position: CGPoint(x: 14, y: 20), kind: .crate),
                BreakableProp(position: CGPoint(x: 18, y: 3), kind: .glassPanel),
                BreakableProp(position: CGPoint(x: 30, y: 15), kind: .glassPanel)
            ],
            entryDoorRect: CGRect(x: 11, y: 6.05, width: 5.2, height: 0.3),
            exitDoorPosition: CGPoint(x: 28, y: 21.55),
            codeClues: [
                CGPoint(x: 27.5, y: 20.6), // 0: under the vault sleeper
                CGPoint(x: 5.6, y: 16.6),  // 1: behind the lab A sight hunter
                CGPoint(x: 26.4, y: 8.7),  // 2: near the corridor sound hunter
                CGPoint(x: 17.6, y: 15.6),  // 3: behind the lab B sound hunter
                CGPoint(x: 16.5, y: 8.1)   // 4: on the corridor glass
            ],
            generatorPosition: CGPoint(x: 2.2, y: 20.5), // lab A far corner
            lockers: [
                LockerSpot(position: CGPoint(x: 1.2, y: 21.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 12.2, y: 21.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 24, y: 21.4), facing: CGPoint(x: 0, y: -1)),
                LockerSpot(position: CGPoint(x: 31.3, y: 12), facing: CGPoint(x: -1, y: 0)),
                LockerSpot(position: CGPoint(x: 15, y: 9.5), facing: CGPoint(x: 0, y: -1))
            ],
            hazards: [
                FloorHazard(position: CGPoint(x: 12, y: 8), kind: .cans),
                FloorHazard(position: CGPoint(x: 18, y: 13), kind: .cans),
                FloorHazard(position: CGPoint(x: 26, y: 18), kind: .cans),
                FloorHazard(position: CGPoint(x: 7, y: 17), kind: .cans),
                FloorHazard(position: CGPoint(x: 15, y: 14), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 29, y: 8), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 9, y: 12), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 25, y: 11), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 20, y: 20), kind: .sparkWire)
            ],
            batteries: [
                CGPoint(x: 28.5, y: 20.8), // vault, near the sleeper
                CGPoint(x: 3, y: 11)       // lab A entry
            ],
            transmitterPosition: nil
        )
    }()

    // MARK: - The roof (floor 4): open sky, dawn, one last signal

    static let roof: LevelData3D = {
        let zones: [SurfaceZone3D] = [
            SurfaceZone3D(rect: CGRect(x: 12, y: 7, width: 6, height: 4),
                          surface: .glass, name: "كوة زجاجية"),
            SurfaceZone3D(rect: CGRect(x: 0, y: 0, width: 30, height: 18),
                          surface: .metal, name: "سطح المحطة")
        ]
        // Low parapets and equipment blocks (wallHeight is 1.1 here).
        let walls: [CGRect] = [
            CGRect(x: 0, y: 0, width: 12.8, height: 0.3),
            CGRect(x: 17.2, y: 0, width: 12.8, height: 0.3),
            CGRect(x: 0, y: 17.7, width: 30, height: 0.3),
            CGRect(x: 0, y: 0, width: 0.3, height: 18),
            CGRect(x: 29.7, y: 0, width: 0.3, height: 18),
            CGRect(x: 6, y: 4, width: 2.4, height: 1.2),
            CGRect(x: 20, y: 12, width: 2.4, height: 1.2),
            CGRect(x: 9, y: 13, width: 1.2, height: 2.4),
            CGRect(x: 24, y: 4, width: 1.2, height: 2.4)
        ]
        return LevelData3D(
            floorNumber: 4,
            worldBounds: CGRect(x: 0, y: 0, width: 30, height: 18),
            wallHeight: 1.1,
            zones: zones,
            walls: walls,
            playerSpawn: CGPoint(x: 15, y: 2.2),
            soundHunters: [
                HunterSpawn(spawn: CGPoint(x: 8, y: 14), waypoints: [
                    CGPoint(x: 8, y: 14), CGPoint(x: 4, y: 8), CGPoint(x: 14, y: 15)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 22, y: 5), waypoints: [
                    CGPoint(x: 22, y: 5), CGPoint(x: 26, y: 12), CGPoint(x: 18, y: 3)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 16, y: 16), waypoints: [
                    CGPoint(x: 16, y: 16), CGPoint(x: 10, y: 17), CGPoint(x: 24, y: 17)
                ], startsAwake: true)
            ],
            sightHunters: [
                HunterSpawn(spawn: CGPoint(x: 10, y: 5), waypoints: [
                    CGPoint(x: 10, y: 5), CGPoint(x: 5, y: 10), CGPoint(x: 16, y: 4)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 24, y: 14), waypoints: [
                    CGPoint(x: 24, y: 14), CGPoint(x: 28, y: 8), CGPoint(x: 20, y: 16)
                ], startsAwake: true),
                HunterSpawn(spawn: CGPoint(x: 16, y: 12), waypoints: [
                    CGPoint(x: 16, y: 12), CGPoint(x: 12, y: 15), CGPoint(x: 20, y: 9)
                ], startsAwake: true)
            ],
            monsterSpeedScale: 1.1,
            stones: [
                CGPoint(x: 5, y: 3), CGPoint(x: 11, y: 6), CGPoint(x: 19, y: 10),
                CGPoint(x: 25, y: 6), CGPoint(x: 8, y: 16), CGPoint(x: 22, y: 17),
                CGPoint(x: 14, y: 4), CGPoint(x: 28, y: 12)
            ],
            stickSpawn: CGPoint(x: 16.5, y: 3),
            breakables: [
                BreakableProp(position: CGPoint(x: 13, y: 15), kind: .crate),
                BreakableProp(position: CGPoint(x: 23, y: 10), kind: .crate)
            ],
            entryDoorRect: CGRect(x: 12.8, y: 0.15, width: 4.4, height: 0.3),
            exitDoorPosition: CGPoint(x: 15, y: 17), // unused on the roof
            codeClues: [],
            generatorPosition: CGPoint(x: 1.5, y: 16.5), // visual only here
            lockers: [
                LockerSpot(position: CGPoint(x: 1.2, y: 8.6), facing: CGPoint(x: 1, y: 0)),
                LockerSpot(position: CGPoint(x: 28.6, y: 16.6), facing: CGPoint(x: -1, y: 0)),
                LockerSpot(position: CGPoint(x: 15, y: 17.2), facing: CGPoint(x: 0, y: -1))
            ],
            hazards: [
                FloorHazard(position: CGPoint(x: 18, y: 8), kind: .cans),
                FloorHazard(position: CGPoint(x: 7, y: 10), kind: .cans),
                FloorHazard(position: CGPoint(x: 21, y: 15), kind: .sparkWire),
                FloorHazard(position: CGPoint(x: 11, y: 3), kind: .sparkWire)
            ],
            batteries: [
                CGPoint(x: 2, y: 2)
            ],
            transmitterPosition: CGPoint(x: 26, y: 9)
        )
    }()
}
