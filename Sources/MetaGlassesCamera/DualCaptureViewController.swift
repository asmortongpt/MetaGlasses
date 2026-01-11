import UIKit
import Combine

/// View controller for capturing stereoscopic 3D images using both cameras
public class DualCaptureViewController: UIViewController {

    // MARK: - Properties

    private let cameraManager = DualCameraManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Components

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Not Connected"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Connect to Glasses"
        config.baseBackgroundColor = .systemBlue
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "eyeglasses")
        config.imagePadding = 8

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var stereoPreviewStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var leftImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var rightImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Capture Stereo 3D Image"
        config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "camera.metering.center.weighted")
        config.imagePadding = 8
        config.buttonSize = .large

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var capture3Button: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Capture 3 Stereo Pairs"
        config.baseBackgroundColor = .systemPurple
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "camera.stack.fill")
        config.imagePadding = 8

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(capture3ButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var exportSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Side-by-Side", "Anaglyph 3D", "Separate"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var exportButton: UIButton = {
        var config = UIButton.Configuration.bordered()
        config.title = "Export & Save"
        config.baseBackgroundColor = .systemOrange
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "square.and.arrow.down")
        config.imagePadding = 8

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true
        return progress
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var imageCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0 stereo pairs captured"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .systemGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var infoLabel: UILabel = {
        let label = UILabel()
        label.text = "📷 Dual Camera Mode: Captures from both navigation and imaging cameras simultaneously for 3D stereoscopic images"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .systemGray2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
    }

    // MARK: - Setup

    private func setupUI() {
        title = "3D Stereo Camera"
        view.backgroundColor = .systemBackground

        // Setup stereo preview
        stereoPreviewStack.addArrangedSubview(leftImageView)
        stereoPreviewStack.addArrangedSubview(rightImageView)

        view.addSubview(statusLabel)
        view.addSubview(connectButton)
        view.addSubview(infoLabel)
        view.addSubview(stereoPreviewStack)
        view.addSubview(progressView)
        view.addSubview(activityIndicator)
        view.addSubview(imageCountLabel)
        view.addSubview(captureButton)
        view.addSubview(capture3Button)
        view.addSubview(exportSegmentedControl)
        view.addSubview(exportButton)

        NSLayoutConstraint.activate([
            // Status Label
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Connect Button
            connectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 250),
            connectButton.heightAnchor.constraint(equalToConstant: 50),

            // Info Label
            infoLabel.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Stereo Preview Stack
            stereoPreviewStack.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 20),
            stereoPreviewStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stereoPreviewStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stereoPreviewStack.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),

            // Progress View
            progressView.topAnchor.constraint(equalTo: stereoPreviewStack.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: stereoPreviewStack.centerYAnchor),

            // Image Count Label
            imageCountLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            imageCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Capture Button
            captureButton.topAnchor.constraint(equalTo: imageCountLabel.bottomAnchor, constant: 20),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 280),
            captureButton.heightAnchor.constraint(equalToConstant: 54),

            // Capture 3 Button
            capture3Button.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 12),
            capture3Button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            capture3Button.widthAnchor.constraint(equalToConstant: 280),
            capture3Button.heightAnchor.constraint(equalToConstant: 50),

            // Export Segmented Control
            exportSegmentedControl.topAnchor.constraint(equalTo: capture3Button.bottomAnchor, constant: 24),
            exportSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exportSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Export Button
            exportButton.topAnchor.constraint(equalTo: exportSegmentedControl.bottomAnchor, constant: 12),
            exportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 200),
            exportButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func createImageView(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.textColor = .systemGray
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.heightAnchor.constraint(equalToConstant: 16)
        ])

        return container
    }

    private func setupBindings() {
        // Connection status
        cameraManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.updateConnectionStatus(isConnected)
            }
            .store(in: &cancellables)

        // Captured stereo pairs
        cameraManager.$capturedStereoPairs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pairs in
                self?.updateStereoPreview(pairs)
            }
            .store(in: &cancellables)

        // Capturing status
        cameraManager.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                self?.updateCapturingStatus(isCapturing)
            }
            .store(in: &cancellables)

        // Capture progress
        cameraManager.$captureProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.progress = Float(progress)
            }
            .store(in: &cancellables)

        // Error messages
        cameraManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.showError(error)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func connectButtonTapped() {
        Task {
            activityIndicator.startAnimating()
            connectButton.isEnabled = false

            do {
                try await cameraManager.connectToGlasses()
            } catch {
                showError("Connection failed: \(error.localizedDescription)")
            }

            activityIndicator.stopAnimating()
            connectButton.isEnabled = true
        }
    }

    @objc private func captureButtonTapped() {
        Task {
            do {
                _ = try await cameraManager.captureStereoImage()
                showSuccess("Stereo 3D image captured!")
            } catch {
                showError("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func capture3ButtonTapped() {
        Task {
            do {
                let pairs = try await cameraManager.captureMultipleStereoPairs(count: 3, delay: 2.0)
                showSuccess("Captured \(pairs.count) stereo pairs for 3D reconstruction!")
            } catch {
                showError("Multi-capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func exportButtonTapped() {
        guard let latestPair = cameraManager.capturedStereoPairs.last else {
            showError("No images to export")
            return
        }

        let format: ExportFormat
        switch exportSegmentedControl.selectedSegmentIndex {
        case 0:
            format = .sideBySide
        case 1:
            format = .anaglyph
        case 2:
            format = .separate
        default:
            format = .sideBySide
        }

        do {
            try cameraManager.saveStereoPair(latestPair, format: format)
            showSuccess("Stereo image exported and saved!")
        } catch {
            showError("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - UI Updates

    private func updateConnectionStatus(_ isConnected: Bool) {
        statusLabel.text = isConnected ? "✅ Connected (Dual Camera)" : "Not Connected"
        statusLabel.textColor = isConnected ? .systemGreen : .systemRed
        captureButton.isEnabled = isConnected
        capture3Button.isEnabled = isConnected

        var config = connectButton.configuration
        config?.title = isConnected ? "Disconnect" : "Connect to Glasses"
        config?.baseBackgroundColor = isConnected ? .systemGray : .systemBlue
        connectButton.configuration = config
    }

    private func updateStereoPreview(_ pairs: [StereoPair]) {
        if let latest = pairs.last {
            (leftImageView.subviews.first as? UIImageView)?.image = latest.leftImage
            (rightImageView.subviews.first as? UIImageView)?.image = latest.rightImage
            exportButton.isEnabled = true
        }

        imageCountLabel.text = "\(pairs.count) stereo pair\(pairs.count == 1 ? "" : "s") captured"
    }

    private func updateCapturingStatus(_ isCapturing: Bool) {
        if isCapturing {
            activityIndicator.startAnimating()
            progressView.isHidden = false
            captureButton.isEnabled = false
            capture3Button.isEnabled = false
            exportButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            progressView.isHidden = true
            captureButton.isEnabled = cameraManager.isConnected
            capture3Button.isEnabled = cameraManager.isConnected
            exportButton.isEnabled = !cameraManager.capturedStereoPairs.isEmpty
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showSuccess(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
