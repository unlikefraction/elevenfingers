import UIKit

final class BottomBarView: UIView {
    weak var toolStrip: ToolStripView? {
        didSet { rebuildLayout() }
    }

    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopyImage: (() -> Void)?
    var onClearCanvas: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onToggleRecord: (() -> Void)?
    var onDeleteAudio: (() -> Void)?

    let recordButton = UIButton(type: .system)
    let deleteAudioButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let redoButton = UIButton(type: .system)
    private let copyImageButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let submitButton = UIButton(type: .system)
    private let submitSpinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        recordButton.setImage(UIImage(systemName: "record.circle"), for: .normal)
        recordButton.setTitle(" Rec", for: .normal)
        recordButton.tintColor = .systemRed
        recordButton.addAction(UIAction { [weak self] _ in self?.onToggleRecord?() }, for: .touchUpInside)

        deleteAudioButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteAudioButton.tintColor = .secondaryLabel
        deleteAudioButton.addAction(UIAction { [weak self] _ in self?.onDeleteAudio?() }, for: .touchUpInside)

        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        undoButton.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .touchUpInside)

        redoButton.setImage(UIImage(systemName: "arrow.uturn.forward"), for: .normal)
        redoButton.addAction(UIAction { [weak self] _ in self?.onRedo?() }, for: .touchUpInside)

        copyImageButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyImageButton.addAction(UIAction { [weak self] _ in self?.onCopyImage?() }, for: .touchUpInside)

        clearButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClearCanvas?() }, for: .touchUpInside)

        submitButton.setTitle("Submit", for: .normal)
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.backgroundColor = .systemBlue
        submitButton.layer.cornerRadius = 10
        submitButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        submitButton.addAction(UIAction { [weak self] _ in self?.onSubmit?() }, for: .touchUpInside)

        submitSpinner.color = .white
        submitSpinner.hidesWhenStopped = true
        submitButton.addSubview(submitSpinner)
        submitSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitSpinner.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            submitSpinner.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
        ])

        rebuildLayout()
    }

    private func rebuildLayout() {
        subviews.filter { $0 is UIStackView }.forEach { $0.removeFromSuperview() }

        let leftStack = UIStackView(arrangedSubviews: [])
        leftStack.axis = .horizontal
        leftStack.spacing = 10
        leftStack.alignment = .center
        if let toolStrip {
            leftStack.addArrangedSubview(toolStrip)
        }

        let centerStack = UIStackView(arrangedSubviews: [undoButton, redoButton])
        centerStack.axis = .horizontal
        centerStack.spacing = 12

        let rightEdits = UIStackView(arrangedSubviews: [copyImageButton, clearButton])
        rightEdits.axis = .horizontal
        rightEdits.spacing = 12

        let submitWrap = UIView()
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitWrap.addSubview(submitButton)
        NSLayoutConstraint.activate([
            submitButton.leadingAnchor.constraint(equalTo: submitWrap.leadingAnchor),
            submitButton.trailingAnchor.constraint(equalTo: submitWrap.trailingAnchor),
            submitButton.topAnchor.constraint(equalTo: submitWrap.topAnchor, constant: 4),
            submitButton.bottomAnchor.constraint(equalTo: submitWrap.bottomAnchor, constant: -4),
            submitButton.widthAnchor.constraint(equalToConstant: 88),
            submitButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        let stack = UIStackView(arrangedSubviews: [leftStack, centerStack, rightEdits, submitWrap])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func setRecording(_ recording: Bool) {
        if recording {
            recordButton.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            recordButton.setTitle(" Stop", for: .normal)
        } else {
            recordButton.setImage(UIImage(systemName: "record.circle"), for: .normal)
            recordButton.setTitle(" Rec", for: .normal)
        }
    }

    func setSubmitting(_ submitting: Bool) {
        if submitting {
            submitButton.setTitle("", for: .normal)
            submitSpinner.startAnimating()
            submitButton.isEnabled = false
        } else {
            submitButton.setTitle("Submit", for: .normal)
            submitSpinner.stopAnimating()
            submitButton.isEnabled = true
        }
    }
}
