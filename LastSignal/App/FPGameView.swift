import SwiftUI
import SceneKit

// Hosts the first-person SceneKit view plus the touch HUD:
// left joystick (move), right-side drag (look), hold button (sprint).
// The 3D scene content does not depend on the view's size, and the SCNView
// is created once the view appears — no zero-size scene building anywhere.
struct FPGameView: View {
    var startFloor: Int = 1
    var onExit: () -> Void

    @StateObject private var errorCenter = ErrorCenter.shared
    @StateObject private var model = FPGameModel()
    @State private var lastLookTranslation = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let bundle = model.bundle {
                FPSceneRepresentable(bundle: bundle)
                    .id(model.sessionID)
                    .ignoresSafeArea()

                // Look area: drag anywhere on the right side to turn.
                HStack {
                    Spacer()
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let dx = value.translation.width - lastLookTranslation.width
                                    let dy = value.translation.height - lastLookTranslation.height
                                    lastLookTranslation = value.translation
                                    model.input.addLook(dx: dx, dy: dy)
                                }
                                .onEnded { _ in
                                    lastLookTranslation = .zero
                                }
                        )
                }
                .ignoresSafeArea()

                // Objective + code progress (top center)
                VStack {
                    Text(model.objectiveText)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassPill()
                        .padding(.top, 12)
                    if model.currentFloor != 4 {
                        Text(model.codeText)
                            .font(.headline.monospaced())
                            .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassPill()
                    }
                    Text(model.floorLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassPill()
                    if model.sendActive {
                        Text("📡 جارٍ إرسال الإشارة… \(model.sendPercent)٪")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(red: 0.55, green: 0.9, blue: 1))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassPill(tint: Color(red: 0.2, green: 0.5, blue: 0.9))
                    }
                    if model.breathVisible {
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.18))
                                    Capsule()
                                        .fill(Color(red: 0.45, green: 0.75, blue: 1))
                                        .frame(width: geo.size.width * CGFloat(100 - model.breathPercent) / 100)
                                }
                            }
                            .frame(width: 170, height: 9)
                            Text("نَفَسك — امسكه إذا الوحش قريب")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassPill()
                    }
                    Spacer()
                }
                .padding(.horizontal, 120)

                // HUD
                VStack {
                    Spacer()
                    if let prompt = model.interactPrompt {
                        Button {
                            model.input.requestInteract()
                            HapticsManager.shared.pulse(intensity: 0.3, sharpness: 0.5)
                        } label: {
                            Text(prompt)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .glassPill(tint: Color(red: 0.3, green: 0.6, blue: 0.9))
                        }
                        .padding(.bottom, 10)
                    }
                    HStack(alignment: .bottom) {
                        JoystickView(input: model.input)
                            .padding(.leading, 26)
                            .padding(.bottom, 8)

                        Spacer()

                        Text(model.modeText)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .glassPill()
                            .padding(.bottom, 16)

                        Spacer()

                        // Arranged by gameplay: least-used at the top,
                        // the panic button (sprint) biggest and closest
                        // to the thumb at the bottom, flashlight just
                        // above it.
                        VStack(spacing: 11) {
                            StickButton(input: model.input, hasStick: model.hasStick)
                            ThrowButton(input: model.input, count: model.stoneCount)
                            if model.breathVisible {
                                HoldBreathButton(input: model.input)
                            }
                            FlashlightButton(input: model.input,
                                             isOn: model.lightOn,
                                             percent: model.batteryPercent,
                                             levelName: model.lightLevelName)
                            SprintButton(input: model.input)
                        }
                        .padding(.trailing, 26)
                        .padding(.bottom, 8)
                    }
                    .padding(.bottom, 10)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("جارٍ تحضير المحطة…")
                        .foregroundStyle(.gray)
                }
            }

            if model.isHidden, !model.caught {
                hiddenOverlay
            }

            if model.caught {
                caughtOverlay
            }

            if model.floorComplete, !model.caught, !model.gameWon {
                floorCompleteOverlay
            }

            if model.gameWon {
                winOverlay
            }

            if let info = errorCenter.current {
                ErrorView(info: info) {
                    errorCenter.dismiss()
                }
            }
        }
        .onAppear { model.startIfNeeded(floor: startFloor) }
    }

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🏆 أرسلت الإشارة الأخيرة")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("طلع الفجر… ونجوت من المحطة. إشارتك وصلت — وقصتك ما انتهت هنا.")
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        model.playAgain()
                    } label: {
                        Text("العب من جديد")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill(tint: Color(red: 0.35, green: 0.9, blue: 0.75))
                    }
                    Button {
                        onExit()
                    } label: {
                        Text("القائمة")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill()
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
    }

    // Inside a locker: darkness with slat gaps, like looking out
    // through the locker door vents.
    private var hiddenOverlay: some View {
        ZStack {
            VStack(spacing: 30) {
                ForEach(0..<14, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                }
            }
            .ignoresSafeArea()
            VStack {
                Text("مختبئ — لا تصدر أي صوت")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 10)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }

    private var floorCompleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(model.currentFloor == 3
                     ? "أكملت الطابق الثالث 🎉"
                     : "أكملت الطابق \(arabicNumeral(model.currentFloor)) 🎉")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(model.currentFloor == 3
                     ? "بقى بس السطح… أرسل الإشارة الأخيرة وانهِ الكابوس."
                     : "الطابق التالي أظلم، ووحوشه أسرع.")
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        model.nextFloor()
                    } label: {
                        Text(model.currentFloor == 3 ? "اصعد إلى السطح" : "الطابق التالي")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill(tint: Color(red: 0.35, green: 0.9, blue: 0.75))
                    }
                    Button {
                        onExit()
                    } label: {
                        Text("القائمة")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill()
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
    }

    private var caughtOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("أمسك بيك الوحش")
                    .font(.title.bold())
                    .foregroundStyle(.red)
                Text("الظلام ابتلع الإشارة…")
                    .foregroundStyle(.gray)
                HStack(spacing: 12) {
                    Button {
                        model.restart()
                    } label: {
                        Text("حاول مجدداً")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill(tint: .red)
                    }
                    Button {
                        onExit()
                    } label: {
                        Text("القائمة")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .glassPill()
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
    }
}

// Owns the scene bundle and the published HUD state.
final class FPGameModel: ObservableObject {
    @Published var bundle: FPSceneBundle?
    @Published var caught = false
    @Published var modeText = "واقف"
    @Published var sessionID = UUID()
    @Published var lightOn = true
    @Published var batteryPercent = 100
    @Published var lightLevelName = "ثابت"
    @Published var stoneCount = 0
    @Published var objectiveText = ""
    @Published var codeText = "الرمز: – – – – –"
    @Published var hasStick = false
    @Published var floorComplete = false
    @Published var interactPrompt: String?
    @Published var breathPercent = 0
    @Published var breathVisible = false
    @Published var isHidden = false
    @Published var currentFloor = 1
    @Published var gameWon = false
    @Published var sendPercent = 0
    @Published var sendActive = false

    let input = FPInputState()

    var floorLabel: String {
        switch currentFloor {
        case 2: return "الطابق ٢ من ٣ • الظلام ٨٧٪"
        case 3: return "الطابق ٣ من ٣ • الظلام ٩٤٪"
        case 4: return "السطح • الفجر"
        default: return "الطابق ١ من ٣ • الظلام ٨٠٪"
        }
    }

    func startIfNeeded(floor: Int) {
        guard bundle == nil else { return }
        currentFloor = min(4, max(1, floor))
        makeBundle()
    }

    func restart() {
        caught = false
        floorComplete = false
        gameWon = false
        sendActive = false
        sendPercent = 0
        hasStick = false
        interactPrompt = nil
        breathPercent = 0
        breathVisible = false
        isHidden = false
        sessionID = UUID()
        makeBundle()
    }

    func nextFloor() {
        guard currentFloor < 4 else { return }
        currentFloor += 1
        restart()
    }

    func playAgain() {
        currentFloor = 1
        restart()
    }

    private func makeBundle() {
        bundle = FPSceneFactory.make(
            floor: currentFloor,
            input: input,
            onCaught: { [weak self] in
                self?.caught = true
                AudioManager.shared.play(.deathAngelAttack)
                HapticsManager.shared.pulse(intensity: 1.0, sharpness: 0.9)
            },
            onModeChange: { [weak self] mode in
                self?.modeText = mode.arabicName
            },
            onLightChange: { [weak self] isOn, percent in
                self?.lightOn = isOn
                self?.batteryPercent = percent
            },
            onLightLevelChange: { [weak self] name in
                self?.lightLevelName = name
            },
            onStonesChange: { [weak self] count in
                self?.stoneCount = count
            },
            onObjective: { [weak self] text in
                self?.objectiveText = text
            },
            onCodeChange: { [weak self] digits in
                let parts = digits.map { value in value.map(String.init) ?? "–" }
                self?.codeText = "الرمز: " + parts.joined(separator: " ")
            },
            onStickChange: { [weak self] has in
                self?.hasStick = has
            },
            onFloorComplete: { [weak self] in
                guard let self = self else { return }
                GameProgress.unlock(floor: self.currentFloor + 1)
                self.floorComplete = true
                AudioManager.shared.play(.endingSting)
            },
            onInteractPrompt: { [weak self] prompt in
                self?.interactPrompt = prompt
            },
            onBreath: { [weak self] percent, visible in
                self?.breathPercent = percent
                self?.breathVisible = visible
            },
            onHidden: { [weak self] hidden in
                self?.isHidden = hidden
            },
            onSendProgress: { [weak self] percent, active in
                self?.sendPercent = percent
                self?.sendActive = active
            },
            onGameWin: { [weak self] in
                self?.gameWon = true
                GameProgress.markWon()
                AudioManager.shared.play(.endingSting)
            }
        )
    }
}

// Western digits -> Arabic-Indic digits for HUD labels.
func arabicNumeral(_ value: Int) -> String {
    let digits = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
    return String(value).map { ch in
        ch.isNumber ? digits[ch.wholeNumberValue ?? 0] : String(ch)
    }.joined()
}

// SCNView wrapper: 120fps target (ProMotion), 4x MSAA, no default lighting.
struct FPSceneRepresentable: UIViewRepresentable {
    let bundle: FPSceneBundle

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = bundle.scene
        view.pointOfView = bundle.cameraNode
        view.delegate = bundle.controller
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 120
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// Left thumb joystick. Publishes a normalized move vector:
// x = strafe right +, y = forward +.
struct JoystickView: View {
    let input: FPInputState
    @State private var offset = CGSize.zero
    private let maxRadius: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 116, height: 116)
                .glassCircle()
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 54, height: 54)
                .glassCircle()
                .offset(offset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let length = hypot(dx, dy)
                    let clampFactor = length > maxRadius ? maxRadius / length : 1
                    offset = CGSize(width: dx * clampFactor, height: dy * clampFactor)
                    input.setMove(CGPoint(x: offset.width / maxRadius,
                                          y: -offset.height / maxRadius))
                }
                .onEnded { _ in
                    offset = .zero
                    input.setMove(.zero)
                }
        )
    }
}

// Flashlight button: battery % and level printed on it.
// Tap = on/off. Long-press = cycle level (ثابت / قوي / وامض):
// strong drains fast and betrays you from farther away; the strobe
// sips battery and only lights you in pulses.
struct FlashlightButton: View {
    let input: FPInputState
    let isOn: Bool
    let percent: Int
    let levelName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 64, height: 64)
                .glassCircle(tint: Color(red: 1, green: 0.9, blue: 0.55))
            VStack(spacing: 0) {
                Text("🔦")
                    .font(.system(size: 15))
                Text("\(percent)%")
                    .font(.caption2.bold())
                    .foregroundStyle(percent <= 20 ? .red : .white)
                Text(levelName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .opacity(isOn ? 1 : 0.45)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    input.requestLightCycle()
                    HapticsManager.shared.pulse(intensity: 0.45, sharpness: 0.6)
                }
                .exclusively(before: TapGesture().onEnded {
                    input.requestFlashlightToggle()
                    HapticsManager.shared.pulse(intensity: 0.3, sharpness: 0.5)
                })
        )
    }
}

// Stick button: appears once the player picks the stick up.
// A swing hits ~1.3m ahead — smashing a crate/glass panel makes a very
// loud distraction; a plain hit is loud too. Then you run.
struct StickButton: View {
    let input: FPInputState
    let hasStick: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 56, height: 56)
                .glassCircle(tint: Color(red: 0.55, green: 0.38, blue: 0.2))
            VStack(spacing: 0) {
                Text("عصا")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("اضرب")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(hasStick ? 1 : 0.35)
        }
        .onTapGesture {
            if hasStick {
                input.requestSwing()
            }
        }
    }
}

// Throw-a-stone button, with the carried count printed on it.
// Stones are picked up by walking over them (max 5); a thrown stone
// lands ~6m ahead and makes a loud decoy noise.
struct ThrowButton: View {
    let input: FPInputState
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 56, height: 56)
                .glassCircle(tint: Color(red: 0.6, green: 0.65, blue: 0.7))
            VStack(spacing: 0) {
                Text("رمي")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("حصو ×\(count)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(count > 0 ? 1 : 0.45)
        }
        .onTapGesture {
            if count > 0 {
                input.requestThrow()
                HapticsManager.shared.pulse(intensity: 0.35, sharpness: 0.5)
            }
        }
    }
}

// Hold-your-breath button: shown while hidden with a sound hunter
// near. Holding it nearly stops the breath meter; letting the meter
// fill means a gasp — a noise right at your locker.
struct HoldBreathButton: View {
    let input: FPInputState
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 62, height: 62)
                .glassCircle(tint: Color(red: 0.45, green: 0.75, blue: 1))
                .scaleEffect(pressed ? 0.93 : 1)
            VStack(spacing: 0) {
                Text("امسك")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("نفسك")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        input.setHoldBreath(true)
                    }
                }
                .onEnded { _ in
                    pressed = false
                    input.setHoldBreath(false)
                }
        )
    }
}

// Hold-to-sprint button (loud movement).
struct SprintButton: View {
    let input: FPInputState
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 80, height: 80)
                .glassCircle(tint: Color(red: 1, green: 0.45, blue: 0.2))
                .scaleEffect(pressed ? 0.93 : 1)
            Text("اركض")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        input.setSprint(true)
                    }
                }
                .onEnded { _ in
                    pressed = false
                    input.setSprint(false)
                }
        )
    }
}
