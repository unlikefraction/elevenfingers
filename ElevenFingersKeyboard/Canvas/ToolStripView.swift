import UIKit

final class ToolStripView: UIView {
    var onToolChange: ((CanvasTool) -> Void)?

    private let penButton = UIButton(type: .system)
    private let eraserButton = UIButton(type: .system)
    private let laserButton = UIButton(type: .system)

    private var buttons: [(UIButton, CanvasTool)] {
        [(penButton, .pen), (eraserButton, .eraser), (laserButton, .laser)]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        penButton.setImage(UIImage(systemName: "pencil.tip"), for: .normal)
        eraserButton.setImage(UIImage(systemName: "eraser"), for: .normal)
        laserButton.setImage(UIImage(systemName: "cursorarrow.rays"), for: .normal)

        for (button, tool) in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .label
            button.addAction(UIAction { [weak self] _ in
                self?.select(tool)
            }, for: .touchUpInside)
        }

        let stack = UIStackView(arrangedSubviews: [penButton, eraserButton, laserButton])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            forName: .toolChanged, object: nil, queue: .main
        ) { [weak self] note in
            if let tool = note.object as? CanvasTool { self?.highlight(tool) }
        }

        select(.pen)
    }

    private func select(_ tool: CanvasTool) {
        highlight(tool)
        onToolChange?(tool)
    }

    private func highlight(_ tool: CanvasTool) {
        for (button, t) in buttons {
            button.alpha = t == tool ? 1.0 : 0.5
        }
    }
}
