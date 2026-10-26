import SwiftUI
import UIKit

// AppDelegate locks the whole app (menu included) to landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

@main
struct LastSignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MenuView()
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
        }
    }
}

// Asks the window scene to actually adopt landscape geometry. The
// delegate mask alone is not always enough: if the app is launched
// while the phone is held in portrait, the SwiftUI scene can keep
// portrait bounds and the whole interface renders rotated and
// cropped (his on-device report). This request forces the issue.
func requestLandscapeOrientation() {
    for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .landscape),
            errorHandler: { _ in })
    }
}

// Layout guard: if the bounds are still portrait (height > width),
// rotate the content into a landscape frame of swapped dimensions
// so nothing is ever cropped or sideways, whatever the window did.
struct LandscapeRoot: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.height > size.width {
                content
                    .frame(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: size.width, height: size.height)
            } else {
                content
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}

extension View {
    func landscapeRoot() -> some View {
        modifier(LandscapeRoot())
    }
}
