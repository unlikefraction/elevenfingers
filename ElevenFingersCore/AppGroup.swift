import Foundation

public enum AppGroup {
    public static let identifier = "group.com.elevenfingers.shared"

    public static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            fatalError("App group container missing: \(identifier)")
        }
        return url
    }

    public static var sharedDirectory: URL {
        let dir = containerURL.appendingPathComponent("shared", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        return dir
    }

    public static var userDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            fatalError("Cannot open shared UserDefaults: \(identifier)")
        }
        return defaults
    }
}

public enum SharedPaths {
    public static var currentAudio: URL {
        AppGroup.sharedDirectory.appendingPathComponent("current.m4a")
    }

    public static var canvasImage: URL {
        AppGroup.sharedDirectory.appendingPathComponent("canvas.png")
    }

    public static var result: URL {
        AppGroup.sharedDirectory.appendingPathComponent("result.txt")
    }

    public static var levels: URL {
        AppGroup.sharedDirectory.appendingPathComponent("levels.bin")
    }

    public static var sessionJSON: URL {
        AppGroup.sharedDirectory.appendingPathComponent("session.json")
    }

    public static var errorJSON: URL {
        AppGroup.sharedDirectory.appendingPathComponent("error.json")
    }
}

public enum DefaultsKeys {
    public static let dictionary = "dictionary"
    public static let backendURL = "backendURL"
    public static let sessionDuration = "sessionDuration"
    public static let languageCode = "languageCode"
    public static let lastResultAt = "lastResultAt"
}
