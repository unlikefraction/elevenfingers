import Foundation

public enum LevelBuffer {
    public static let slots = 64

    public static func write(_ levels: [Float]) {
        var padded = levels
        if padded.count < slots {
            padded.append(contentsOf: Array(repeating: 0, count: slots - padded.count))
        } else if padded.count > slots {
            padded = Array(padded.suffix(slots))
        }
        let data = padded.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: SharedPaths.levels, options: .atomic)
    }

    public static func read() -> [Float] {
        guard let data = try? Data(contentsOf: SharedPaths.levels),
              data.count == slots * MemoryLayout<Float>.size else {
            return Array(repeating: 0, count: slots)
        }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}

public struct BackendConfig {
    public static let defaultURL = "https://elevenfingers.unlikefraction.com"

    public static func baseURL() -> URL {
        let stored = AppGroup.userDefaults.string(forKey: DefaultsKeys.backendURL)
        if let stored, !stored.isEmpty, let url = URL(string: stored) {
            return url
        }
        return URL(string: defaultURL)!
    }

    public static func set(_ url: String) {
        AppGroup.userDefaults.set(url, forKey: DefaultsKeys.backendURL)
    }
}
