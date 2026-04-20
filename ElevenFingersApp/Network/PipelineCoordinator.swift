import Combine
import Foundation
import os
import UIKit

@MainActor
final class PipelineCoordinator: ObservableObject {
    static let shared = PipelineCoordinator()

    @Published private(set) var lastResult: String = ""
    @Published private(set) var inFlight: Bool = false
    @Published private(set) var logs: [String] = []

    private let notifier = DarwinNotifier()
    private let logger = Logger(subsystem: "com.elevenfingers.app", category: "pipeline")

    private init() {
        if let data = try? Data(contentsOf: SharedPaths.result),
           let text = String(data: data, encoding: .utf8) {
            lastResult = text
        }
    }

    func runPipeline() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        append("pipeline start")
        let dictionary = DictionaryStore.shared.get()
        let languageCode = AppGroup.userDefaults.string(forKey: DefaultsKeys.languageCode) ?? "eng"

        let imageData: Data? = try? Data(contentsOf: SharedPaths.canvasImage)
        let audioData: Data? = try? Data(contentsOf: SharedPaths.currentAudio)

        if imageData == nil && audioData == nil {
            append("pipeline skipped: no inputs")
            writeError("no-input", "Nothing to submit")
            notifier.post(.resultFailed)
            return
        }

        async let ocrRaw: (String?, String) = Self.runOCR(imageData: imageData, dictionary: dictionary)
        async let sttRaw: (String?, String) = Self.runSTT(audioData: audioData, languageCode: languageCode)

        let (ocr, ocrLog) = await ocrRaw
        let (stt, sttLog) = await sttRaw
        if !ocrLog.isEmpty { append(ocrLog) }
        if !sttLog.isEmpty { append(sttLog) }

        if (ocr ?? "").isEmpty && (stt ?? "").isEmpty {
            append("pipeline aborted: both ocr and stt empty")
            writeError("no-signal", "Nothing could be read or transcribed")
            notifier.post(.resultFailed)
            return
        }

        do {
            let result = try await BackendClient.shared.writer(ocr: ocr, stt: stt, dictionary: dictionary)
            try? result.text.write(to: SharedPaths.result, atomically: true, encoding: .utf8)
            lastResult = result.text
            append("writer ok \(result.elapsed_ms)ms -> \(result.text.count) chars")

            var state = SessionState.read()
            state.lastResultAt = Date().timeIntervalSince1970
            state.write()

            try? FileManager.default.removeItem(at: SharedPaths.canvasImage)
            try? FileManager.default.removeItem(at: SharedPaths.currentAudio)

            notifier.post(.resultReady)
        } catch {
            append("writer failed: \(error)")
            writeError("writer", "\(error)")
            notifier.post(.resultFailed)
        }
    }

    private static func runOCR(imageData: Data?, dictionary: String) async -> (String?, String) {
        guard let imageData, imageData.count > 32 else { return (nil, "") }
        do {
            let r = try await BackendClient.shared.ocr(image: imageData, dictionary: dictionary)
            return (r.text, "ocr ok \(r.elapsed_ms)ms text=\(r.text.count)")
        } catch {
            return (nil, "ocr failed: \(error)")
        }
    }

    private static func runSTT(audioData: Data?, languageCode: String) async -> (String?, String) {
        guard let audioData, audioData.count > 2048 else { return (nil, "") }
        do {
            let r = try await BackendClient.shared.stt(audio: audioData, languageCode: languageCode)
            return (r.text, "stt ok \(r.elapsed_ms)ms text=\(r.text.count)")
        } catch {
            return (nil, "stt failed: \(error)")
        }
    }

    private func writeError(_ kind: String, _ message: String) {
        let env = PipelineErrorEnvelope(
            at: Date().timeIntervalSince1970, kind: kind, message: message
        )
        PipelineErrorEnvelope.write(env)
    }

    private func append(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(ts)] \(line)"
        logs.append(entry)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
        logger.info("\(line, privacy: .public)")
    }
}
