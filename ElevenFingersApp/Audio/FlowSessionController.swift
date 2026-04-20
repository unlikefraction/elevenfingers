import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class FlowSessionController: ObservableObject {
    static let shared = FlowSessionController()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var recording: Bool = false
    @Published private(set) var statusText: String = "Inactive"

    private let notifier = DarwinNotifier()
    private let recorder = AudioRecorder()
    private var expiryTimer: Timer?
    private var statusTimer: Timer?
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        syncState()
        observeInterruptions()
    }

    func syncState() {
        let state = SessionState.read()
        isActive = state.active
        recording = state.recording
        expiresAt = state.expiresAt.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        }
        refreshStatusText()
    }

    func start() {
        guard !isActive else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("Audio session activation failed: \(error)")
            return
        }

        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "FlowSession") { [weak self] in
            guard let self else { return }
            self.endBackgroundTask()
        }

        let duration = currentDurationSeconds()
        let now = Date()
        let expires: Date? = duration.map { now.addingTimeInterval($0) }

        let state = SessionState(
            active: true,
            startedAt: now.timeIntervalSince1970,
            expiresAt: expires?.timeIntervalSince1970,
            recording: false,
            lastResultAt: SessionState.read().lastResultAt
        )
        state.write()
        isActive = true
        expiresAt = expires

        scheduleExpiry(at: expires)
        startStatusTicker()
        refreshStatusText()
    }

    func stop() {
        recorder.stop()
        expiryTimer?.invalidate()
        statusTimer?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let prior = SessionState.read()
        SessionState(
            active: false,
            startedAt: 0,
            expiresAt: nil,
            recording: false,
            lastResultAt: prior.lastResultAt
        ).write()

        isActive = false
        recording = false
        expiresAt = nil
        notifier.post(.sessionExpired)
        endBackgroundTask()
        refreshStatusText()
    }

    func startRecording() {
        guard isActive else { start(); return }
        recorder.start()
        recording = true
        updateSessionRecording(true)
    }

    func stopRecording() {
        recorder.stop()
        recording = false
        updateSessionRecording(false)
    }

    private func updateSessionRecording(_ flag: Bool) {
        var state = SessionState.read()
        state.recording = flag
        state.write()
    }

    private func scheduleExpiry(at date: Date?) {
        expiryTimer?.invalidate()
        guard let date else { return }
        let interval = max(1, date.timeIntervalSinceNow)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func startStatusTicker() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusText() }
        }
    }

    private func refreshStatusText() {
        if !isActive {
            statusText = "Inactive — tap Start to arm"
            return
        }
        if let expiresAt {
            let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
            let minutes = remaining / 60
            let seconds = remaining % 60
            statusText = String(format: "Active — expires in %d:%02d", minutes, seconds)
        } else {
            statusText = "Active — until stopped"
        }
    }

    private func currentDurationSeconds() -> TimeInterval? {
        let raw = AppGroup.userDefaults.string(forKey: DefaultsKeys.sessionDuration) ?? SessionDurationOption.fifteenMinutes.rawValue
        let option = SessionDurationOption(rawValue: raw) ?? .fifteenMinutes
        return option.seconds
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            if type == .began {
                Task { @MainActor in self.stop() }
            }
        }
    }

    private func endBackgroundTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }
}
