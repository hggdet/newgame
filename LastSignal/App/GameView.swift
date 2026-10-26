import SwiftUI
import SpriteKit

// Hosts the SpriteKit scene.
// STEP 0 FIX (the crash): the old path built the scene while the view size
// was still .zero (menu tap -> scene with no real bounds). Here the scene is
// created ONLY after GeometryReader reports a real landscape size, and if a
// valid size never arrives we show an Arabic message instead of crashing.
struct GameView: View {
    var onExit: () -> Void

    @StateObject private var errorCenter = ErrorCenter.shared
    @State private var scene: GameScene?
    @State private var caught = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Group {
                    if let scene = scene {
                        SpriteView(scene: scene)
                            .ignoresSafeArea()
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("جارٍ تحضير المحطة…")
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onAppear { makeSceneIfNeeded(size: geo.size) }
                .onChange(of: geo.size) { _, newSize in
                    makeSceneIfNeeded(size: newSize)
                }
            }

            if caught {
                caughtOverlay
            }

            if let info = errorCenter.current {
                ErrorView(info: info) {
                    errorCenter.dismiss()
                }
            }
        }
    }

    private var caughtOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("أمسك بك ملاك الموت")
                    .font(.title.bold())
                    .foregroundStyle(.red)
                Text("الظلام ابتلع الإشارة…")
                    .foregroundStyle(.gray)
                HStack(spacing: 12) {
                    Button {
                        caught = false
                        scene = nil // Next layout pass rebuilds a fresh scene.
                    } label: {
                        Text("حاول مجدداً")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        onExit()
                    } label: {
                        Text("القائمة")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
    }

    // Creates the scene exactly once, and only with a real size.
    private func makeSceneIfNeeded(size: CGSize) {
        guard scene == nil else { return }
        guard size.width > 50, size.height > 50,
              size.width.isSafeFinite, size.height.isSafeFinite else {
            // Bounds not ready yet — the next onChange will retry. No crash.
            return
        }
        let newScene = GameScene()
        newScene.size = size
        newScene.scaleMode = .resizeFill
        newScene.onPlayerCaught = {
            caught = true
            AudioManager.shared.play(.deathAngelAttack)
            HapticsManager.shared.pulse(intensity: 1.0, sharpness: 0.9)
        }
        scene = newScene
    }
}
