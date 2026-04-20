import Foundation

@MainActor
final class KeyboardBridge {
    static let shared = KeyboardBridge()

    private let notifier = DarwinNotifier()

    private init() {}

    func start() {
        notifier.observe(.sessionStart) {
            Task { @MainActor in FlowSessionController.shared.start() }
        }
        notifier.observe(.sessionStop) {
            Task { @MainActor in FlowSessionController.shared.stop() }
        }
        notifier.observe(.recordingStart) {
            Task { @MainActor in FlowSessionController.shared.startRecording() }
        }
        notifier.observe(.recordingStop) {
            Task { @MainActor in FlowSessionController.shared.stopRecording() }
        }
        notifier.observe(.submit) {
            Task { @MainActor in await PipelineCoordinator.shared.runPipeline() }
        }
    }
}
