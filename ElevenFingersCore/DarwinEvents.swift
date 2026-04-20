import Foundation

public enum DarwinEvent: String, CaseIterable {
    case sessionStart    = "com.elevenfingers.session.start"
    case sessionStop     = "com.elevenfingers.session.stop"
    case sessionExpired  = "com.elevenfingers.session.expired"
    case recordingStart  = "com.elevenfingers.recording.start"
    case recordingStop   = "com.elevenfingers.recording.stop"
    case levelsTick      = "com.elevenfingers.levels.tick"
    case submit          = "com.elevenfingers.submit"
    case resultReady     = "com.elevenfingers.result.ready"
    case resultFailed    = "com.elevenfingers.result.failed"

    public var cfName: CFNotificationName {
        CFNotificationName(rawValue as CFString)
    }
}

public final class DarwinNotifier {
    public typealias Handler = () -> Void

    private var handlers: [DarwinEvent: Handler] = [:]
    private let queue = DispatchQueue.main

    public init() {}

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    public func post(_ event: DarwinEvent) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, event.cfName, nil, nil, true)
    }

    public func observe(_ event: DarwinEvent, handler: @escaping Handler) {
        handlers[event] = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let opaque = Unmanaged.passUnretained(self).toOpaque()

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer = observer, let name = name else { return }
            let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
            let raw = name.rawValue as String
            if let event = DarwinEvent(rawValue: raw),
               let handler = notifier.handlers[event] {
                DispatchQueue.main.async { handler() }
            }
        }

        CFNotificationCenterAddObserver(
            center,
            opaque,
            callback,
            event.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }
}
