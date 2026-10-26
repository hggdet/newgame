import SwiftUI

// Main menu (landscape, Arabic RTL) — first-person build.
// His layout: his own key-art background fills the screen (slow
// breathing zoom, flying sparks, distant lightning), no title text,
// and at the BOTTOM-LEFT a column of plain dark tiles, no borders —
// «ابدأ» (gold letters) on top, «الإعدادات» and «كيف ألعب؟» side by
// side below it. No Continue button. A light horror ambience loops
// underneath, and «ابدأ» fades to black behind a slamming door.
// The menu never builds a 3D scene itself; it only presents
// FPGameView, which creates the scene after real bounds exist.
struct MenuView: View {
    @StateObject private var errorCenter = ErrorCenter.shared
    @State private var showGame = false
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var artZoom = false
    @State private var flash: Double = 0
    @State private var startFade = false
    @AppStorage("menu.headphonesSeen") private var headphonesSeen = false

    @State private var volume: Double = Double(GameSettings.soundVolume)
    @State private var hapticsOn: Bool = GameSettings.hapticsEnabled
    @State private var sensitivity: Double = Double(GameSettings.lookSensitivity)

    var body: some View {
        ZStack {
            background

            EmberField()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Distant lightning: a soft white flash, thunder follows.
            Rectangle()
                .fill(Color.white.opacity(flash))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Buttons: bottom-left corner column (positioned in LTR
            // so "left" stays left under the RTL layout).
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                    Button {
                        startCinematic()
                    } label: {
                        Text("ابدأ")
                            .font(.system(.title2, weight: .black))
                            .foregroundStyle(Color(red: 0.96, green: 0.79, blue: 0.36))
                            .frame(width: 168, height: 62)
                            .menuTile(fill: darkFill)
                    }

                        HStack(spacing: 12) {
                            Button {
                                tapFeedback()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showSettings.toggle()
                                    showHelp = false
                                }
                            } label: {
                                Text("الإعدادات")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 78, height: 54)
                                    .menuTile(fill: darkFill)
                            }

                            Button {
                                tapFeedback()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showHelp.toggle()
                                    showSettings = false
                                }
                            } label: {
                                Text("كيف ألعب؟")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 78, height: 54)
                                    .menuTile(fill: darkFill)
                            }
                        }
                    }
                    Spacer()
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.leading, 30)
            .padding(.bottom, 26)

            if showHelp {
                helpPanel
            }

            if showSettings {
                settingsPanel
            }

            if !headphonesSeen {
                headphonesNotice
            }

            // Cinematic start: the screen sinks to black over the
            // closing door before the game appears.
            Rectangle()
                .fill(Color.black.opacity(startFade ? 1 : 0))
                .ignoresSafeArea()
                .allowsHitTesting(startFade)

            if let info = errorCenter.current {
                ErrorView(info: info) {
                    errorCenter.dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showGame, onDismiss: {
            startFade = false
            AudioManager.shared.playLooped(.menuAmbience, volume: 0.4)
        }) {
            FPGameView(startFloor: 1) {
                showGame = false
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .onAppear {
            AudioManager.shared.playLooped(.menuAmbience, volume: 0.4)
            artZoom = true
        }
        .task {
            await lightningLoop()
        }
    }

    // «ابدأ»: tap feedback, ambience stops, the door slams and locks
    // behind the player while the screen fades to black, then the
    // game opens.
    private func startCinematic() {
        guard !startFade else { return }
        tapFeedback()
        AudioManager.shared.stopLooped()
        withAnimation(.easeIn(duration: 1.5)) {
            startFade = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            AudioManager.shared.play(.doorSlam, volume: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AudioManager.shared.play(.doorLock, volume: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            showGame = true
        }
    }

    // Random distant lightning while the menu is on screen: two soft
    // pulses, then a low thunder roll half a second later.
    private func lightningLoop() async {
        while !Task.isCancelled {
            let wait = Double.random(in: 6...15)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.07)) { flash = 0.16 }
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.easeIn(duration: 0.1)) { flash = 0 }
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.easeOut(duration: 0.06)) { flash = 0.1 }
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeIn(duration: 0.16)) { flash = 0 }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            if !showGame {
                AudioManager.shared.play(.thunder, volume: 0.22)
            }
        }
    }

    // One-time notice (first launch only): play with headphones.
    private var headphonesNotice: some View {
        VStack(spacing: 10) {
            Text("🎧")
                .font(.system(size: 40))
            Text("يُفضّل اللعب بالسماعات\nلتجربة رعب كاملة")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button {
                tapFeedback()
                headphonesSeen = true
            } label: {
                Text("فهمت")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 40)
                    .menuTile(fill: darkFill)
            }
        }
        .padding(22)
        .glassPanel()
        .padding(.horizontal, 40)
    }

    // Light touch feedback on every menu button: a soft tap sound
    // plus a gentle vibration (respects the haptics setting).
    private func tapFeedback() {
        AudioManager.shared.play(.uiTap)
        HapticsManager.shared.pulse(intensity: 0.3, sharpness: 0.4)
    }

    // Simple dark tile fill (his choice: dark and plain, no white
    // border, no bright colours).
    private var darkFill: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.58), Color.black.opacity(0.42)],
            startPoint: .top, endPoint: .bottom)
    }

    // Key art when it ships in the bundle (menu_bg.jpg); layered dark
    // gradients underneath and as the fallback.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.03, blue: 0.08),
                         Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let art = menuArt {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    // A very slow breathing zoom keeps the still
                    // artwork alive without distracting from it.
                    .scaleEffect(artZoom ? 1.07 : 1.0)
                    .animation(.easeInOut(duration: 26)
                        .repeatForever(autoreverses: true), value: artZoom)
                LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.clear,
                             Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [Color.red.opacity(0.16), Color.clear],
                    center: .topLeading, startRadius: 10, endRadius: 420)
                    .ignoresSafeArea()
                RadialGradient(
                    colors: [Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.10), Color.clear],
                    center: .bottomTrailing, startRadius: 10, endRadius: 460)
                    .ignoresSafeArea()
            }
        }
    }

    private var menuArt: UIImage? {
        guard let url = Bundle.main.url(forResource: "menu_bg", withExtension: "jpg") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("🎯 الهدف: بكل طابق اجمع رمزاً من ٥ أرقام مخبأة قرب الوحوش، شغّل المولد، وافتح باب الطابق التالي — لحد السطح.")
            Text("👹 وحشان: واحد أعمى يسمع صوتك، وواحد يشوف نور فلاشك بس. وكل نوع منهم ٣.")
            Text("🔦 فلاشك سلاح وفضيحة بنفس الوقت — قوته الأعلى تنوّر أكثر وتفضحك من أبعد.")
            Text("🪨 ارمِ حصو أو اكسر شيئاً بالعصا لتشتيت الوحوش… واهرب قبل وصولهم.")
            Text("🗄️ اختبئ بالخزائن وامسك نفسك إذا وحش الصوت قرّب. وانتبه تدوس علباً أو أسلاك شرارة بالأرض.")
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.92))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(16)
        .glassPanel()
        .padding(.leading, 220)
        .padding(.trailing, 24)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("الإعدادات")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text("مستوى الصوت")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: $volume, in: 0...1)
                    .tint(Color(red: 0.85, green: 0.65, blue: 0.15))
                    .onChange(of: volume) { _, newValue in
                        GameSettings.soundVolume = Float(newValue)
                    }
            }

            Toggle("الاهتزاز", isOn: $hapticsOn)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .tint(Color(red: 0.85, green: 0.65, blue: 0.15))
                .onChange(of: hapticsOn) { _, newValue in
                    GameSettings.hapticsEnabled = newValue
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("حساسية النظر")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: $sensitivity, in: 0.4...2)
                    .tint(Color(red: 0.85, green: 0.65, blue: 0.15))
                    .onChange(of: sensitivity) { _, newValue in
                        GameSettings.lookSensitivity = CGFloat(newValue)
                    }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(18)
        .glassPanel()
        .padding(.leading, 220)
        .padding(.trailing, 24)
    }
}

// Squarish menu tile: soft corners, plain dark fill, NO border
// (his final choice for the menu buttons).
private struct MenuTileModifier: ViewModifier {
    let fill: LinearGradient

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
    }
}

private extension View {
    func menuTile(fill: LinearGradient) -> some View {
        modifier(MenuTileModifier(fill: fill))
    }
}
