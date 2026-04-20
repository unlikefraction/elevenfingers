import Foundation

final class AppBridge {
    private let notifier = DarwinNotifier()

    func post(_ event: DarwinEvent) {
        notifier.post(event)
    }

    func observe(_ event: DarwinEvent, handler: @escaping () -> Void) {
        notifier.observe(event, handler: handler)
    }
}
