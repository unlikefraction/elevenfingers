import PencilKit
import UIKit

enum CanvasTool { case pen, eraser, laser }

final class CanvasHostView: UIView, PKCanvasViewDelegate, UIPencilInteractionDelegate {
    private var canvasView: PKCanvasView!
    private let laserLayer = CALayer()
    private var undoStack: [PKDrawing] = []
    private var redoStack: [PKDrawing] = []
    private var currentTool: CanvasTool = .pen

    private let maxUndoDepth = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = UIColor.white
        layer.cornerRadius = 8
        clipsToBounds = true

        rebuildCanvas()

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
    }

    private func rebuildCanvas() {
        canvasView?.removeFromSuperview()

        let canvas = PKCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = self

        addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        self.canvasView = canvas
        applyTool(currentTool)
    }

    func setTool(_ tool: CanvasTool) {
        currentTool = tool
        applyTool(tool)
    }

    private func applyTool(_ tool: CanvasTool) {
        guard let canvasView else { return }
        switch tool {
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: .black, width: 2.5)
            canvasView.isUserInteractionEnabled = true
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
            canvasView.isUserInteractionEnabled = true
        case .laser:
            canvasView.tool = PKInkingTool(.pen, color: .clear, width: 0)
            canvasView.isUserInteractionEnabled = false
        }
    }

    var hasStrokes: Bool {
        !(canvasView?.drawing.strokes.isEmpty ?? true)
    }

    func renderImage(scale: CGFloat) -> UIImage {
        guard let canvasView else { return UIImage() }
        let bounds = canvasView.bounds
        return canvasView.drawing.image(from: bounds, scale: scale)
    }

    func clear() {
        pushUndo()
        canvasView?.drawing = PKDrawing()
    }

    func undo() {
        guard let canvasView else { return }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(canvasView.drawing)
        canvasView.drawing = previous
    }

    func redo() {
        guard let canvasView else { return }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(canvasView.drawing)
        canvasView.drawing = next
    }

    private func pushUndo() {
        guard let canvasView else { return }
        undoStack.append(canvasView.drawing)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        redoStack.removeAll()
    }

    // MARK: PKCanvasViewDelegate
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if undoStack.last != canvasView.drawing {
            undoStack.append(canvasView.drawing)
            if undoStack.count > maxUndoDepth {
                undoStack.removeFirst(undoStack.count - maxUndoDepth)
            }
            redoStack.removeAll()
        }
    }

    // MARK: UIPencilInteractionDelegate
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        let next: CanvasTool = currentTool == .pen ? .eraser : .pen
        setTool(next)
        NotificationCenter.default.post(name: .toolChanged, object: next)
    }

    func pencilInteractionDidSqueeze(_ interaction: UIPencilInteraction) {
        let cycle: CanvasTool
        switch currentTool {
        case .pen: cycle = .eraser
        case .eraser: cycle = .laser
        case .laser: cycle = .pen
        }
        setTool(cycle)
        NotificationCenter.default.post(name: .toolChanged, object: cycle)
    }
}

extension Notification.Name {
    static let toolChanged = Notification.Name("com.elevenfingers.toolChanged")
}
