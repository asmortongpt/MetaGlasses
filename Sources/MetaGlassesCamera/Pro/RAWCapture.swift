import AVFoundation
import Photos
import UIKit

/// Professional RAW Photo Capture
/// Capture uncompressed RAW photos for maximum editing flexibility
@MainActor
public class RAWCapture {

    // MARK: - Singleton
    public static let shared = RAWCapture()

    // MARK: - Properties
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentSettings: AVCapturePhotoSettings?

    // Callbacks
    public var onPhotoCaptured: ((URL, UIImage?) -> Void)?
    public var onError: ((Error) -> Void)?

    // MARK: - Initialization
    private init() {
        print("📸 RAWCapture initialized")
    }

    // MARK: - Setup

    /// Setup RAW capture session
    public func setupCaptureSession() async throws {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw RAWCaptureError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw RAWCaptureError.cannotAddInput
        }
        session.addInput(input)

        // Add photo output
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw RAWCaptureError.cannotAddOutput
        }
        session.addOutput(output)

        // Enable RAW capture if supported
        guard output.availableRawPhotoPixelFormatTypes.count > 0 else {
            throw RAWCaptureError.rawNotSupported
        }

        self.captureSession = session
        self.photoOutput = output

        print("✅ RAW capture session configured")
    }

    /// Start capture session
    public func startSession() {
        captureSession?.startRunning()
        print("▶️ RAW capture session started")
    }

    /// Stop capture session
    public func stopSession() {
        captureSession?.stopRunning()
        print("⏹️ RAW capture session stopped")
    }

    // MARK: - Capture

    /// Capture RAW photo
    public func captureRAWPhoto() throws {
        guard let photoOutput = photoOutput else {
            throw RAWCaptureError.outputNotConfigured
        }

        // Create photo settings
        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: photoOutput.availableRawPhotoPixelFormatTypes.first!)

        // Enable processed photo alongside RAW
        photoSettings.isHighResolutionPhotoEnabled = true

        // Set flash mode
        if photoOutput.supportedFlashModes.contains(.auto) {
            photoSettings.flashMode = .auto
        }

        currentSettings = photoSettings

        // Capture photo
        photoOutput.capturePhoto(with: photoSettings, delegate: self)

        print("📸 Capturing RAW photo...")
    }

    /// Capture RAW + JPEG combo
    public func captureRAWPlusJPEG() throws {
        guard let photoOutput = photoOutput else {
            throw RAWCaptureError.outputNotConfigured
        }

        guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            throw RAWCaptureError.rawNotSupported
        }

        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)

        // Enable processed JPEG
        if let processedFormat = photoOutput.availablePhotoCodecTypes.first {
            photoSettings.processedFileType = .jpg
        }

        photoSettings.isHighResolutionPhotoEnabled = true

        currentSettings = photoSettings
        photoOutput.capturePhoto(with: photoSettings, delegate: self)

        print("📸 Capturing RAW + JPEG...")
    }

    // MARK: - Preview

    /// Get preview layer
    public func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension RAWCapture: AVCapturePhotoCaptureDelegate {

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("❌ Photo capture error: \(error.localizedDescription)")
            onError?(error)
            return
        }

        // Save RAW data
        if let rawData = photo.fileDataRepresentation() {
            saveRAWPhoto(data: rawData, photo: photo)
        }
    }

    private func saveRAWPhoto(data: Data, photo: AVCapturePhoto) {
        // Generate filename
        let filename = "RAW_\(Date().timeIntervalSince1970).dng"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            print("✅ RAW photo saved: \(filename)")

            // Generate preview
            let previewImage = generatePreview(from: photo)

            onPhotoCaptured?(url, previewImage)

            // Save to Photos library
            saveToPhotoLibrary(url: url, image: previewImage)
        } catch {
            print("❌ Failed to save RAW photo: \(error.localizedDescription)")
            onError?(error)
        }
    }

    private func generatePreview(from photo: AVCapturePhoto) -> UIImage? {
        if let cgImage = photo.cgImageRepresentation() {
            return UIImage(cgImage: cgImage.takeUnretainedValue())
        }
        return nil
    }

    private func saveToPhotoLibrary(url: URL, image: UIImage?) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("❌ Photo library access denied")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: url, options: nil)

                if let image = image {
                    creationRequest.addResource(with: .alternatePhoto, data: image.jpegData(compressionQuality: 0.9)!, options: nil)
                }
            } completionHandler: { success, error in
                if success {
                    print("✅ RAW photo saved to library")
                } else if let error = error {
                    print("❌ Failed to save to library: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Supporting Types

public enum RAWCaptureError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case rawNotSupported
    case outputNotConfigured
    case captureFailed

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "Camera is not available"
        case .cannotAddInput: return "Cannot add camera input"
        case .cannotAddOutput: return "Cannot add photo output"
        case .rawNotSupported: return "RAW capture not supported on this device"
        case .outputNotConfigured: return "Photo output not configured"
        case .captureFailed: return "Photo capture failed"
        }
    }
}
