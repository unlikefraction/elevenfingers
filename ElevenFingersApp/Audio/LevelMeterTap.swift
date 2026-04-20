import AVFoundation
import Foundation

final class LevelMeterTap {
    private let engine = AVAudioEngine()
    private let notifier = DarwinNotifier()
    private var ring: [Float] = Array(repeating: 0, count: LevelBuffer.slots)
    private var lastTick: CFTimeInterval = 0

    func start() {
        stop()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.ingest(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            print("LevelMeterTap start failed: \(error)")
        }
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func ingest(buffer: AVAudioPCMBuffer) {
        guard let floats = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for i in 0..<count {
            let s = floats[i]
            sum += s * s
        }
        let rms = sqrtf(sum / Float(count))
        ring.removeFirst()
        ring.append(rms)

        let now = CACurrentMediaTime()
        if now - lastTick > (1.0 / 20.0) {
            lastTick = now
            LevelBuffer.write(ring)
            notifier.post(.levelsTick)
        }
    }
}
