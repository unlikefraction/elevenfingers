import UIKit

final class WaveformView: UIView {
    private var displayLink: CADisplayLink?
    private var levels: [Float] = Array(repeating: 0, count: LevelBuffer.slots)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopDisplayLink()
        } else {
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        reload()
    }

    func reload() {
        levels = LevelBuffer.read()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        let bars = levels.count
        let total = rect.width
        let gap: CGFloat = 2
        let barWidth = max(1, (total - CGFloat(bars - 1) * gap) / CGFloat(bars))

        let tint = tintColor ?? UIColor.systemBlue
        ctx.setFillColor(tint.cgColor)

        let midY = rect.midY
        for i in 0..<bars {
            let level = CGFloat(min(1.0, max(0.02, levels[i] * 8)))
            let h = max(2, rect.height * level)
            let x = CGFloat(i) * (barWidth + gap)
            let barRect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: min(barWidth / 2, 2))
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
    }
}
