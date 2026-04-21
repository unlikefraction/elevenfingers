import SwiftUI

@main
struct ElevenFingersAppEntry: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    appDelegate.handleURL(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { @MainActor in
                            FlowSessionController.shared.ensureActive()
                        }
                    }
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
        Task { @MainActor in flow.ensureActive() }
        return true
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "elevenfingers" else { return }
        if url.host == "wake" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let pending = comps?.queryItems?.first(where: { $0.name == "pending" })?.value
            Task { @MainActor in
                FlowSessionController.shared.ensureActive()
                switch pending {
                case "submit":
                    await PipelineCoordinator.shared.runPipeline()
                case "record":
                    FlowSessionController.shared.startRecording()
                default:
                    break
                }
            }
        }
    }
}
