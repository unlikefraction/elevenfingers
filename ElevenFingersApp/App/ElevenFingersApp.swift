import SwiftUI

@main
struct ElevenFingersAppEntry: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    appDelegate.handleURL(url)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let bridge = KeyboardBridge.shared
    let flow = FlowSessionController.shared
    let pipeline = PipelineCoordinator.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        bridge.start()
        return true
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "elevenfingers" else { return }
        if url.host == "wake" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let pending = comps?.queryItems?.first(where: { $0.name == "pending" })?.value
            if pending == "submit" {
                Task { await pipeline.runPipeline() }
            }
        }
    }
}
