import SwiftUI

// Main menu (landscape, Arabic RTL).
// STEP 0 FIX: this menu never creates a scene itself and never touches
// SpriteKit with a .zero size — it only presents GameView, which builds the
// scene after real landscape bounds exist.
struct MenuView: View {
    @StateObject private var errorCenter = ErrorCenter.shared
    @State private var showGame = false

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.04)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Text("إشارة أخيرة")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(.white)

                Text("محطة أبحاث مهجورة… وخمس قطع بينك وبين الحقيقة")
                    .font(.headline)
                    .foregroundStyle(.gray)

                Spacer()

                Button {
                    AudioManager.shared.play(.uiTap)
                    showGame = true
                } label: {
                    Text("ابدأ لعبة جديدة")
                        .font(.title3.bold())
                        .foregroundStyle(.black)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.35, green: 0.9, blue: 0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Continue/settings arrive with the save system (Batch D).
                // The button is visibly disabled until a save exists, which is
                // the required behaviour: no save -> no continue.
                Button {
                    reportError("لا توجد لعبة محفوظة بعد")
                } label: {
                    Text("متابعة")
                        .font(.title3.bold())
                        .foregroundStyle(.gray)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding(24)

            if let info = errorCenter.current {
                ErrorView(info: info) {
                    errorCenter.dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            GameView {
                showGame = false
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
