import SwiftUI
import UIKit
import AVFoundation

/// SwiftUI wrapper for DualCaptureViewController
public struct CameraViewWrapper: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    @ObservedObject var bluetoothManager: BluetoothManager

    public init(isPresented: Binding<Bool>, bluetoothManager: BluetoothManager) {
        self._isPresented = isPresented
        self.bluetoothManager = bluetoothManager
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let cameraVC = DualCaptureViewController()
        cameraVC.coordinator = context.coordinator

        let navController = UINavigationController(rootViewController: cameraVC)
        navController.navigationBar.prefersLargeTitles = false

        // Add close button
        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.dismissCamera)
        )
        cameraVC.navigationItem.leftBarButtonItem = closeButton

        return navController
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Update if needed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public class Coordinator: NSObject {
        var parent: CameraViewWrapper

        init(parent: CameraViewWrapper) {
            self.parent = parent
        }

        @objc func dismissCamera() {
            parent.isPresented = false
        }
    }
}

/// Simple camera view using iPhone's camera directly
public struct LiveCameraView: UIViewControllerRepresentable {

    @Binding var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public func makeUIViewController(context: Context) -> LiveCameraViewController {
        let controller = LiveCameraViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: LiveCameraViewController, context: Context) {
        // Update if needed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public class Coordinator: NSObject {
        var parent: LiveCameraView

        init(parent: LiveCameraView) {
            self.parent = parent
        }

        func dismissCamera() {
            parent.isPresented = false
        }
    }
}

/// Live camera view controller using AVFoundation
public class LiveCameraViewController: UIViewController {

    weak var coordinator: LiveCameraView.Coordinator?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Camera Ready"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCamera()
        setupUI()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCamera()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCamera()
    }

    private func setupCamera() {
        // Request camera permission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.showPermissionAlert()
                }
                return
            }

            DispatchQueue.main.async {
                self?.configureCaptureSession()
            }
        }
    }

    private func configureCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo

        guard let captureSession = captureSession else { return }

        // Add camera input
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: backCamera) else {
            print("❌ Failed to setup camera input")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Add photo output
        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Setup preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds

        if let previewLayer = previewLayer {
            view.layer.insertSublayer(previewLayer, at: 0)
        }

        print("✅ Camera configured")
    }

    private func setupUI() {
        view.addSubview(closeButton)
        view.addSubview(captureButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 50),
            closeButton.heightAnchor.constraint(equalToConstant: 50),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 200),
            statusLabel.heightAnchor.constraint(equalToConstant: 40),

            // Capture button
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }

    private func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.statusLabel.text = "📸 Camera Ready"
            }
        }
    }

    private func stopCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    @objc private func closeButtonTapped() {
        coordinator?.dismissCamera()
    }

    @objc private func captureButtonTapped() {
        guard let photoOutput = photoOutput else {
            print("❌ Photo output not available")
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto

        photoOutput.capturePhoto(with: settings, delegate: self)

        // Visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.view.alpha = 0.5
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.view.alpha = 1.0
            }
        }

        statusLabel.text = "📸 Photo Captured!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusLabel.text = "📸 Camera Ready"
        }
    }

    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to use this feature.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension LiveCameraViewController: AVCapturePhotoCaptureDelegate {

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("❌ Photo capture error: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("❌ Failed to convert photo data to UIImage")
            return
        }

        // Save to photo library
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        print("✅ Photo saved to library")
    }
}
