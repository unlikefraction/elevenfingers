import UIKit
import PencilKit

final class KeyboardViewController: UIInputViewController {

    private let bridge = AppBridge()

    private lazy var canvasHost = CanvasHostView()
    private lazy var toolStrip = ToolStripView()
    private lazy var waveformView = WaveformView()
    private lazy var bottomBar = BottomBarView()
    private lazy var footerBar = FooterBarView()
    private lazy var textModeView = SpacebarSliderView()
    private lazy var toastLabel = UILabel()

    private var isTextMode = false
    private var submissionTimeout: Timer?
    private var pendingInsert = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false

        buildLayout()
        hookActions()
        observeBridge()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        adaptForContainerSize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.adaptForContainerSize()
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adaptForContainerSize()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let data = try? Data(contentsOf: SharedPaths.result),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty,
           pendingInsert {
            pendingInsert = false
            textDocumentProxy.insertText(text)
            try? FileManager.default.removeItem(at: SharedPaths.result)
        }
    }

    // MARK: Layout
    private var topRow = UIView()
    private var canvasContainer = UIView()
    private var topRowHeight: NSLayoutConstraint!
    private var bottomBarHeight: NSLayoutConstraint!
    private var footerBarHeight: NSLayoutConstraint!

    private func buildLayout() {
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let recordButton = bottomBar.recordButton
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        topRow.addSubview(recordButton)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        topRow.addSubview(waveformView)

        let deleteAudioButton = bottomBar.deleteAudioButton
        deleteAudioButton.translatesAutoresizingMaskIntoConstraints = false
        topRow.addSubview(deleteAudioButton)

        NSLayoutConstraint.activate([
            recordButton.leadingAnchor.constraint(equalTo: topRow.leadingAnchor, constant: 8),
            recordButton.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 64),

            waveformView.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 8),
            waveformView.trailingAnchor.constraint(equalTo: deleteAudioButton.leadingAnchor, constant: -8),
            waveformView.topAnchor.constraint(equalTo: topRow.topAnchor, constant: 4),
            waveformView.bottomAnchor.constraint(equalTo: topRow.bottomAnchor, constant: -4),

            deleteAudioButton.trailingAnchor.constraint(equalTo: topRow.trailingAnchor, constant: -8),
            deleteAudioButton.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            deleteAudioButton.widthAnchor.constraint(equalToConstant: 28),
        ])

        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        canvasHost.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(canvasHost)

        textModeView.translatesAutoresizingMaskIntoConstraints = false
        textModeView.isHidden = true
        canvasContainer.addSubview(textModeView)

        NSLayoutConstraint.activate([
            canvasHost.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            canvasHost.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor, constant: 6),
            canvasHost.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor, constant: -6),
            canvasHost.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),

            textModeView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            textModeView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            textModeView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            textModeView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
        ])

        let stack = UIStackView(arrangedSubviews: [
            topRow,
            canvasContainer,
            bottomBar,
            footerBar,
        ])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        topRowHeight = topRow.heightAnchor.constraint(equalToConstant: 36)
        bottomBarHeight = bottomBar.heightAnchor.constraint(equalToConstant: 38)
        footerBarHeight = footerBar.heightAnchor.constraint(equalToConstant: 30)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),

            topRowHeight,
            bottomBarHeight,
            footerBarHeight,
        ])

        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .systemFont(ofSize: 12, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.numberOfLines = 2
        view.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -4),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.85),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
    }

    private func adaptForContainerSize() {
        let h = view.bounds.height
        guard h > 0 else { return }
        // Scale chrome based on available height. Floating kb is ~320 tall; docked is larger.
        if h < 260 {
            topRowHeight.constant = 30
            bottomBarHeight.constant = 34
            footerBarHeight.constant = 26
        } else if h < 340 {
            topRowHeight.constant = 34
            bottomBarHeight.constant = 36
            footerBarHeight.constant = 28
        } else {
            topRowHeight.constant = 40
            bottomBarHeight.constant = 42
            footerBarHeight.constant = 32
        }
    }

    // MARK: Actions
    private func hookActions() {
        toolStrip.onToolChange = { [weak self] tool in
            self?.canvasHost.setTool(tool)
        }
        bottomBar.toolStrip = toolStrip
        bottomBar.onUndo = { [weak self] in self?.canvasHost.undo() }
        bottomBar.onRedo = { [weak self] in self?.canvasHost.redo() }
        bottomBar.onCopyImage = { [weak self] in self?.copyCanvasAsImage() }
        bottomBar.onClearCanvas = { [weak self] in self?.canvasHost.clear() }
        bottomBar.onSubmit = { [weak self] in self?.submit() }

        bottomBar.onToggleRecord = { [weak self] in self?.toggleRecord() }
        bottomBar.onDeleteAudio = { [weak self] in self?.deleteAudio() }

        footerBar.onCloseKeyboard = { [weak self] in self?.dismissKeyboard() }
        footerBar.onToggleTextMode = { [weak self] in self?.toggleTextMode() }
        footerBar.onGlobe = { [weak self] in self?.advanceToNextInputMode() }

        textModeView.onDelta = { [weak self] delta in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
        }
        textModeView.onBackspace = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
    }

    // MARK: Bridge
    private func observeBridge() {
        bridge.observe(.levelsTick) { [weak self] in
            DispatchQueue.main.async { self?.waveformView.reload() }
        }
        bridge.observe(.resultReady) { [weak self] in
            DispatchQueue.main.async { self?.handleResultReady() }
        }
        bridge.observe(.resultFailed) { [weak self] in
            DispatchQueue.main.async { self?.handleResultFailed() }
        }
    }

    private func toggleRecord() {
        let state = SessionState.read()
        if !state.active {
            bridge.post(.sessionStart)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.bridge.post(.recordingStart)
                self?.bottomBar.setRecording(true)
            }
            return
        }
        if state.recording {
            bridge.post(.recordingStop)
            bottomBar.setRecording(false)
        } else {
            bridge.post(.recordingStart)
            bottomBar.setRecording(true)
        }
    }

    private func deleteAudio() {
        bridge.post(.recordingStop)
        try? FileManager.default.removeItem(at: SharedPaths.currentAudio)
        bottomBar.setRecording(false)
        showToast("Audio cleared")
    }

    private func copyCanvasAsImage() {
        let image = canvasHost.renderImage(scale: 2.0)
        if let png = image.pngData() {
            UIPasteboard.general.setData(png, forPasteboardType: "public.png")
            showToast("Canvas copied")
        }
    }

    private func toggleTextMode() {
        isTextMode.toggle()
        canvasHost.isHidden = isTextMode
        textModeView.isHidden = !isTextMode
        toolStrip.isHidden = isTextMode
    }

    private func submit() {
        if canvasHost.hasStrokes {
            let image = canvasHost.renderImage(scale: 2.0)
            if let png = image.pngData() {
                try? png.write(to: SharedPaths.canvasImage, options: .atomic)
            }
        } else {
            try? FileManager.default.removeItem(at: SharedPaths.canvasImage)
        }
        pendingInsert = true
        bridge.post(.submit)
        bottomBar.setSubmitting(true)
        startSubmissionTimeout()
    }

    private func startSubmissionTimeout() {
        submissionTimeout?.invalidate()
        submissionTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.handleTimeout() }
        }
    }

    private func handleResultReady() {
        submissionTimeout?.invalidate()
        bottomBar.setSubmitting(false)
        bottomBar.setRecording(false)
        guard let data = try? Data(contentsOf: SharedPaths.result),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        textDocumentProxy.insertText(text)
        try? FileManager.default.removeItem(at: SharedPaths.result)
        canvasHost.clear()
        pendingInsert = false
    }

    private func handleResultFailed() {
        submissionTimeout?.invalidate()
        bottomBar.setSubmitting(false)
        let env = PipelineErrorEnvelope.read()
        showToast(env?.message ?? "Submission failed")
    }

    private func handleTimeout() {
        bottomBar.setSubmitting(false)
        showToast("Open ElevenFingers to finish — tap")
    }

    private func showToast(_ message: String) {
        toastLabel.text = "  \(message)  "
        view.bringSubviewToFront(toastLabel)
        UIView.animate(withDuration: 0.2, animations: { self.toastLabel.alpha = 1 }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                UIView.animate(withDuration: 0.25) { self.toastLabel.alpha = 0 }
            }
        }
    }
}
