import SwiftUI
import UIKit

// Arabic in-app error screen: message + file/line + copy button.
// Shown instead of crashing whenever a recoverable failure is reported.
struct ErrorView: View {
    let info: AppErrorInfo
    var onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 16) {
                Text("حدث خطأ")
                    .font(.title2.bold())
                    .foregroundStyle(.red)

                Text(info.message)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("الملف: \(info.file) — السطر: \(info.line)")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)

                Text("تم حفظ الخطأ في سجل داخل التطبيق، واللعبة مستمرة.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = info.displayText
                        copied = true
                    } label: {
                        Text(copied ? "تم النسخ ✓" : "نسخ الخطأ")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("إغلاق")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(28)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
