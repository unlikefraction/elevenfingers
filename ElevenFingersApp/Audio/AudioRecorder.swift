import AVFoundation
import Foundation

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var ring: [Float] = Array(repeating: 0, count: LevelBuffer.slots)
    private let notifier = DarwinNotifier()

    func start() {
        stop()

        let url = SharedPaths.currentAudio
        try? FileManager.default.removeItem(at: url)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32000,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder
            startMetering()
        } catch {
            print("AudioRecorder.start failed: \(error)")
        }
    }

    func stop() {
        stopMetering()
        recorder?.stop()
        recorder = nil
        ring = Array(repeating: 0, count: LevelBuffer.slots)
        LevelBuffer.write(ring)
        notifier.post(.levelsTick)
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tickMeter()
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tickMeter() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        // db is in -160…0 range. Map -50 dB (quiet) → 0 and 0 dB → 1.
        let normalized = max(0, min(1, (db + 50) / 50))
        ring.removeFirst()
        ring.append(Float(normalized))
        LevelBuffer.write(ring)
        notifier.post(.levelsTick)
    }
}
