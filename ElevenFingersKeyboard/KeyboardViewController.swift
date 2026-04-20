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

    private var isTextMode = false
    private var submissionSpinner: UIActivityIndicatorView?
    private var submissionTimeout: Timer?
    private var pendingInsert = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.systemGroupedBackground
        view.translatesAutoresizingMaskIntoConstraints = false

        buildLayout()
        hookActions()
        observeBridge()

        preferredContentSize = CGSize(width: 620, height: 360)
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
    private func buildLayout() {
        let topRow = UIView()
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
            recordButton.leadingAnchor.constraint(equalTo: topRow.leadingAnchor, constant: 12),
            recordButton.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 32),

            waveformView.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 12),
            waveformView.trailingAnchor.constraint(equalTo: deleteAudioButton.leadingAnchor, constant: -12),
            waveformView.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 28),

            deleteAudioButton.trailingAnchor.constraint(equalTo: topRow.trailingAnchor, constant: -12),
            deleteAudioButton.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            deleteAudioButton.widthAnchor.constraint(equalToConstant: 32),
            deleteAudioButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        let canvasContainer = UIView()
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        canvasHost.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(canvasHost)

        textModeView.translatesAutoresizingMaskIntoConstraints = false
        textModeView.isHidden = true
        canvasContainer.addSubview(textModeView)

        NSLayoutConstraint.activate([
            canvasHost.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            canvasHost.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            canvasHost.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
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
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topRow.heightAnchor.constraint(equalToConstant: 44),
            canvasContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),
            footerBar.heightAnchor.constraint(equalToConstant: 36),
        ])
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
        bottomBar.onDeleteAudio = { [weak self] in self?.confirmDeleteAudio() }

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

    private func confirmDeleteAudio() {
        let alert = UIAlertController(
            title: "Delete audio?",
            message: "The current recording will be discarded.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.bridge.post(.recordingStop)
            try? FileManager.default.removeItem(at: SharedPaths.currentAudio)
            self?.bottomBar.setRecording(false)
        })
        presentInputAlert(alert)
    }

    private func copyCanvasAsImage() {
        let image = canvasHost.renderImage(scale: 2.0)
        if let png = image.pngData() {
            UIPasteboard.general.setData(png, forPasteboardType: "public.png")
        }
    }

    private func toggleTextMode() {
        isTextMode.toggle()
        canvasHost.isHidden = isTextMode
        textModeView.isHidden = !isTextMode
        toolStrip.isHidden = isTextMode
    }

    private func submit() {
        let image = canvasHost.renderImage(scale: 2.0)
        if canvasHost.hasStrokes, let png = image.pngData() {
            try? png.write(to: SharedPaths.canvasImage, options: .atomic)
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
            DispatchQueue.main.async { self?.showWakeCTA() }
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
        let message = env?.message ?? "Submission failed"
        let alert = UIAlertController(title: "ElevenFingers", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentInputAlert(alert)
    }

    private func showWakeCTA() {
        bottomBar.setSubmitting(false)
        let alert = UIAlertController(
            title: "Open ElevenFingers",
            message: "The app is asleep. Tap to wake it and complete the submission.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            if let url = URL(string: "elevenfingers://wake?pending=submit") {
                self?.extensionContext?.open(url, completionHandler: nil)
            }
        })
        presentInputAlert(alert)
    }

    private func presentInputAlert(_ alert: UIAlertController) {
        present(alert, animated: true)
    }
}
