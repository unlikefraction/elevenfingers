import UIKit

final class FooterBarView: UIView {
    var onCloseKeyboard: (() -> Void)?
    var onToggleTextMode: (() -> Void)?
    var onGlobe: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        close.addAction(UIAction { [weak self] _ in self?.onCloseKeyboard?() }, for: .touchUpInside)

        let textMode = UIButton(type: .system)
        textMode.setImage(UIImage(systemName: "character.textbox"), for: .normal)
        textMode.setTitle(" Aa", for: .normal)
        textMode.addAction(UIAction { [weak self] _ in self?.onToggleTextMode?() }, for: .touchUpInside)

        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addAction(UIAction { [weak self] _ in self?.onGlobe?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [close, UIView(), textMode, UIView(), globe])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
