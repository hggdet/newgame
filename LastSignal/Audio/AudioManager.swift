import Foundation
import AVFoundation

// Every sound the game can request. The raw value is the audio file's base
// name inside the app bundle (extensions tried: m4a, wav, mp3, caf).
// No audio files ship yet: a missing file is a silent no-op, never a crash.
// Later batches/game polish drop real files in with these exact names.
enum Sound: String, CaseIterable {
    case demogorgonGrowl = "demogorgon_growl"
    case demogorgonRoar = "demogorgon_roar"
    case demogorgonNearby = "demogorgon_nearby"
    case deathAngelScreech = "deathangel_screech"
    case deathAngelStep = "deathangel_step"
    case deathAngelAttack = "deathangel_attack"
    case playerStep = "player_step"
    case playerStepGlass = "player_step_glass"
    case doorCreak = "door_creak"
    case doorSlam = "door_slam"
    case doorSealedHit = "door_sealed_hit"
    case pickupPart = "pickup_part"
    case pickupItem = "pickup_item"
    case throwItem = "throw_item"
    case flareIgnite = "flare_ignite"
    case flareBurn = "flare_burn"
    case lockerOpen = "locker_open"
    case lockerHide = "locker_hide"
    case breathHold = "breath_hold"
    case breathGasp = "breath_gasp"
    case heartbeat = "heartbeat"
    case transmissionHum = "transmission_hum"
    case signalSent = "signal_sent"
    case transmissionDone = "transmission_done"
    case survivorCry = "survivor_cry"
    case survivorRescued = "survivor_rescued"
    case distantDoor = "distant_door"
    case distantFootsteps = "distant_footsteps"
    case uiTap = "ui_tap"
    case gameOverSting = "gameover_sting"
    case endingSting = "ending_sting"
    case stickSwing = "stick_swing"
    case stickHit = "stick_hit"
    case breakWood = "break_wood"
    case breakGlass = "break_glass"
    case codeDigitFound = "code_digit_found"
    case doorLock = "door_lock"
    case doorUnlock = "door_unlock"
    case keypadBeep = "keypad_beep"
    case sightHunterScreech = "sighthunter_screech"
    case generatorCrank = "generator_crank"
    case generatorOn = "generator_on"
    case metalClank = "metal_clank"
    case sparkZap = "spark_zap"
    case menuAmbience = "amb_station"
    case thunder = "thunder"
}

// Directional audio on AVAudioEngine + AVAudioEnvironmentNode (3D).
// Startup is fully guarded: session configuration and engine.start() are in
// do/catch, and any failure simply disables audio — the game continues.
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private var loopNode: AVAudioPlayerNode?
    private(set) var isAvailable = false

    var volume: Float {
        get {
            if let stored = UserDefaults.standard.object(forKey: "settings.volume") as? Float {
                return min(max(stored, 0), 1)
            }
            return 0.8
        }
        set {
            let clamped = min(max(newValue, 0), 1)
            UserDefaults.standard.set(clamped, forKey: "settings.volume")
            engine.mainMixerNode.outputVolume = clamped
        }
    }

    private init() {
        startEngine()
    }

    private func startEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio session refused: continue silently without audio.
            isAvailable = false
            return
        }

        engine.attach(environment)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.distanceAttenuationParameters.maximumDistance = 1200
        environment.distanceAttenuationParameters.referenceDistance = 60
        environment.distanceAttenuationParameters.rolloffFactor = 1.5
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = volume

        do {
            engine.prepare()
            try engine.start()
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    // Updates the 3D listener (the player). Called from the scene each frame
    // is unnecessary — call it when the player moves meaningfully.
    func updateListener(position: CGPoint) {
        guard isAvailable else { return }
        // World units are points; scale down so attenuation feels right.
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(position.x) / 10.0,
            y: Float(position.y) / 10.0,
            z: 0
        )
    }

    // Plays a sound, optionally positioned in the world (directional).
    // Missing file / failed decode / stopped engine: silent no-op.
    func play(_ sound: Sound, at worldPosition: CGPoint? = nil, volume level: Float = 1.0) {
        guard isAvailable, engine.isRunning else { return }
        guard let buffer = loadBuffer(named: sound.rawValue) else { return }

        let node = AVAudioPlayerNode()
        node.volume = min(max(level, 0), 1)
        if let worldPosition = worldPosition {
            node.renderingAlgorithm = .sphericalHead
            node.position = AVAudio3DPoint(
                x: Float(worldPosition.x) / 10.0,
                y: Float(worldPosition.y) / 10.0,
                z: 0
            )
        }
        engine.attach(node)
        engine.connect(node, to: environment, format: buffer.format)
        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self, weak node] in
            DispatchQueue.main.async {
                guard let self = self, let node = node else { return }
                if node.engine != nil {
                    self.engine.detach(node)
                }
            }
        }
        node.play()
    }

    // Looping playback on a dedicated node (menu ambience). Starting
    // it again replaces whatever looped before; stopLooped ends it.
    // Missing file / unavailable engine: silent no-op.
    func playLooped(_ sound: Sound, volume level: Float = 0.5) {
        guard isAvailable, engine.isRunning else { return }
        guard let buffer = loadBuffer(named: sound.rawValue) else { return }
        stopLooped()
        let node = AVAudioPlayerNode()
        node.volume = min(max(level, 0), 1)
        engine.attach(node)
        engine.connect(node, to: environment, format: buffer.format)
        node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        node.play()
        loopNode = node
    }

    func stopLooped() {
        guard let node = loopNode else { return }
        node.stop()
        if node.engine != nil {
            engine.detach(node)
        }
        loopNode = nil
    }

    private func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = bufferCache[name] { return cached }

        let extensions = ["m4a", "wav", "mp3", "caf"]
        var fileURL: URL?
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                fileURL = url
                break
            }
        }
        guard let url = fileURL else { return nil } // No placeholder audio yet.

        do {
            let file = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: frameCount) else {
                return nil
            }
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { return nil }
            bufferCache[name] = buffer
            return buffer
        } catch {
            return nil
        }
    }
}
