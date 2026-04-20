import AVFoundation
import Foundation

final class AudioRecorder {
    private var recorder: AVAudioRecorder?

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
        } catch {
            print("AudioRecorder.start failed: \(error)")
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }

    var isRecording: Bool { recorder?.isRecording ?? false }
}
