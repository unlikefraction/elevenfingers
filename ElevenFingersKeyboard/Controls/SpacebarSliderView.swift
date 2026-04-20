import UIKit

final class SpacebarSliderView: UIView {
    var onDelta: ((Int) -> Void)?
    var onBackspace: (() -> Void)?

    private let spacebar = UIView()
    private let pxPerChar: CGFloat = 10.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = UIColor.systemGroupedBackground

        spacebar.backgroundColor = UIColor.systemBackground
        spacebar.layer.cornerRadius = 8
        spacebar.layer.borderColor = UIColor.separator.cgColor
        spacebar.layer.borderWidth = 0.5
        spacebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spacebar)

        let label = UILabel()
        label.text = "space — drag to move caret"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        spacebar.addSubview(label)

        let backspace = UIButton(type: .system)
        backspace.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspace.translatesAutoresizingMaskIntoConstraints = false
        backspace.addAction(UIAction { [weak self] _ in self?.onBackspace?() }, for: .touchUpInside)
        addSubview(backspace)

        NSLayoutConstraint.activate([
            spacebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            spacebar.trailingAnchor.constraint(equalTo: backspace.leadingAnchor, constant: -12),
            spacebar.centerYAnchor.constraint(equalTo: centerYAnchor),
            spacebar.heightAnchor.constraint(equalToConstant: 48),

            label.leadingAnchor.constraint(equalTo: spacebar.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: spacebar.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: spacebar.centerYAnchor),

            backspace.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            backspace.centerYAnchor.constraint(equalTo: centerYAnchor),
            backspace.widthAnchor.constraint(equalToConstant: 44),
            backspace.heightAnchor.constraint(equalToConstant: 44),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        spacebar.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let translation = gesture.translation(in: spacebar)
        let delta = Int(translation.x / pxPerChar)
        if delta != 0 {
            onDelta?(delta)
            gesture.setTranslation(.zero, in: spacebar)
        }
    }
}
