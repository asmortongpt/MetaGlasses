import UIKit
import Combine
// All Meta SDK dependencies are in CameraManager

/// Main view controller for capturing images from Meta glasses
public class CaptureViewController: UIViewController {

    // MARK: - Properties

    private let cameraManager = CameraManager()
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

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Capture Image"
        config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "camera.fill")
        config.imagePadding = 8

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var capture3ImagesButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Capture 3 Images"
        config.baseBackgroundColor = .systemPurple
        config.cornerStyle = .medium
        config.image = UIImage(systemName: "camera.stack.fill")
        config.imagePadding = 8

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(capture3ImagesButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var imagePreview: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var imageCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0 images captured"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .systemGray
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
        title = "Meta Glasses Camera"
        view.backgroundColor = .systemBackground

        view.addSubview(statusLabel)
        view.addSubview(connectButton)
        view.addSubview(imagePreview)
        view.addSubview(captureButton)
        view.addSubview(capture3ImagesButton)
        view.addSubview(activityIndicator)
        view.addSubview(imageCountLabel)

        NSLayoutConstraint.activate([
            // Status Label
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Connect Button
            connectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 250),
            connectButton.heightAnchor.constraint(equalToConstant: 50),

            // Image Preview
            imagePreview.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 30),
            imagePreview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            imagePreview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            imagePreview.heightAnchor.constraint(equalTo: imagePreview.widthAnchor, multiplier: 0.75),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: imagePreview.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: imagePreview.centerYAnchor),

            // Image Count Label
            imageCountLabel.topAnchor.constraint(equalTo: imagePreview.bottomAnchor, constant: 12),
            imageCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Capture Button
            captureButton.topAnchor.constraint(equalTo: imageCountLabel.bottomAnchor, constant: 30),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 250),
            captureButton.heightAnchor.constraint(equalToConstant: 50),

            // Capture 3 Images Button
            capture3ImagesButton.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 16),
            capture3ImagesButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            capture3ImagesButton.widthAnchor.constraint(equalToConstant: 250),
            capture3ImagesButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupBindings() {
        // Connection status
        cameraManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.updateConnectionStatus(isConnected)
            }
            .store(in: &cancellables)

        // Captured images
        cameraManager.$capturedImages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] images in
                self?.updateImagePreview(images)
            }
            .store(in: &cancellables)

        // Capturing status
        cameraManager.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                self?.updateCapturingStatus(isCapturing)
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
                _ = try await cameraManager.captureImage()
            } catch {
                showError("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func capture3ImagesButtonTapped() {
        Task {
            do {
                let images = try await cameraManager.captureMultipleImages(count: 3, delay: 1.5)
                showSuccess("Captured \(images.count) images successfully!")
            } catch {
                showError("Multi-capture failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI Updates

    private func updateConnectionStatus(_ isConnected: Bool) {
        statusLabel.text = isConnected ? "✅ Connected" : "Not Connected"
        statusLabel.textColor = isConnected ? .systemGreen : .systemRed
        captureButton.isEnabled = isConnected
        capture3ImagesButton.isEnabled = isConnected

        var config = connectButton.configuration
        config?.title = isConnected ? "Disconnect" : "Connect to Glasses"
        config?.baseBackgroundColor = isConnected ? .systemGray : .systemBlue
        connectButton.configuration = config
    }

    private func updateImagePreview(_ images: [UIImage]) {
        imagePreview.image = images.last
        imageCountLabel.text = "\(images.count) image\(images.count == 1 ? "" : "s") captured"
    }

    private func updateCapturingStatus(_ isCapturing: Bool) {
        if isCapturing {
            activityIndicator.startAnimating()
            captureButton.isEnabled = false
            capture3ImagesButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            captureButton.isEnabled = cameraManager.isConnected
            capture3ImagesButton.isEnabled = cameraManager.isConnected
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
