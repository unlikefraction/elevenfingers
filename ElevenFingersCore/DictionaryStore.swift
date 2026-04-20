import Foundation

public final class DictionaryStore {
    public static let shared = DictionaryStore()

    private let defaults = AppGroup.userDefaults

    public init() {}

    public func get() -> String {
        defaults.string(forKey: DefaultsKeys.dictionary) ?? ""
    }

    public func set(_ value: String) {
        defaults.set(value, forKey: DefaultsKeys.dictionary)
    }
}

public enum SessionDurationOption: String, CaseIterable {
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case untilStopped

    public var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes:    return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .oneHour:        return 60 * 60
        case .untilStopped:   return nil
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes:    return "5 min"
        case .fifteenMinutes: return "15 min"
        case .oneHour:        return "1 hr"
        case .untilStopped:   return "Until stopped"
        }
    }
}

public struct SessionState: Codable {
    public var active: Bool
    public var startedAt: TimeInterval
    public var expiresAt: TimeInterval?
    public var recording: Bool
    public var lastResultAt: TimeInterval?

    public init(active: Bool, startedAt: TimeInterval, expiresAt: TimeInterval?, recording: Bool, lastResultAt: TimeInterval?) {
        self.active = active
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.recording = recording
        self.lastResultAt = lastResultAt
    }

    public static var inactive: SessionState {
        SessionState(active: false, startedAt: 0, expiresAt: nil, recording: false, lastResultAt: nil)
    }

    public static func read() -> SessionState {
        guard let data = try? Data(contentsOf: SharedPaths.sessionJSON),
              let state = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return .inactive
        }
        return state
    }

    public func write() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: SharedPaths.sessionJSON, options: .atomic)
        }
    }
}

public enum PipelineError: Codable {
    case network(String)
    case upstream(String)
    case timeout
    case unknown(String)
}

public struct PipelineErrorEnvelope: Codable {
    public let at: TimeInterval
    public let kind: String
    public let message: String

    public init(at: TimeInterval, kind: String, message: String) {
        self.at = at
        self.kind = kind
        self.message = message
    }

    public static func write(_ envelope: PipelineErrorEnvelope) {
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: SharedPaths.errorJSON, options: .atomic)
        }
    }

    public static func read() -> PipelineErrorEnvelope? {
        guard let data = try? Data(contentsOf: SharedPaths.errorJSON),
              let env = try? JSONDecoder().decode(PipelineErrorEnvelope.self, from: data) else {
            return nil
        }
        return env
    }
}
