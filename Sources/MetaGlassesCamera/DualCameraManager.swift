import Foundation
import UIKit
import Combine
import AVFoundation

/// Manages dual camera capture using AVFoundation's multi-camera API for stereoscopic 3D imaging
/// Supports both iPhone multi-camera systems and Meta Ray-Ban glasses via external hardware
@MainActor
public class DualCameraManager: ObservableObject {

    // MARK: - Camera Types

    public enum CameraType {
        case front      // Front-facing camera
        case back       // Primary back camera
        case ultraWide  // Ultra-wide back camera
        case telephoto  // Telephoto back camera (if available)

        var avPosition: AVCaptureDevice.Position {
            switch self {
            case .front: return .front
            case .back, .ultraWide, .telephoto: return .back
            }
        }

        var avDeviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .front: return .builtInWideAngleCamera
            case .back: return .builtInWideAngleCamera
            case .ultraWide: return .builtInUltraWideCamera
            case .telephoto: return .builtInTelephotoCamera
            }
        }
    }

    // MARK: - Published Properties

    @Published public var isConnected: Bool = false
    @Published public var capturedStereoPairs: [StereoPair] = []
    @Published public var errorMessage: String?
    @Published public var isCapturing: Bool = false
    @Published public var captureProgress: Double = 0.0
    @Published public var availableCameras: [CameraType] = []

    // MARK: - Private Properties

    private var multiCamSession: AVCaptureMultiCamSession?
    private var captureDevices: [CameraType: AVCaptureDevice] = [:]
    private var photoOutputs: [CameraType: AVCapturePhotoOutput] = [:]
    private var videoDataOutputs: [CameraType: AVCaptureVideoDataOutput] = [:]
    private let sessionQueue = DispatchQueue(label: "com.metaglasses.camera.session")
    private var cancellables = Set<AnyCancellable>()
    private var capturedPhotos: [CameraType: Data] = [:]
    private var photoContinuations: [CameraType: CheckedContinuation<Data, Error>] = [:]

    // MARK: - Initialization

    public init() {
        setupSession()
    }

    // MARK: - Setup

    private func setupSession() {
        // Check if multi-camera is supported
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            errorMessage = "Multi-camera not supported on this device"
            print("❌ Multi-camera not supported")
            return
        }

        // Discover available cameras
        discoverAvailableCameras()

        print("✅ Dual camera manager initialized with \(availableCameras.count) cameras")
    }

    private func discoverAvailableCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        availableCameras.removeAll()

        for device in discoverySession.devices {
            switch device.deviceType {
            case .builtInWideAngleCamera:
                if device.position == .back {
                    availableCameras.append(.back)
                } else if device.position == .front {
                    availableCameras.append(.front)
                }
            case .builtInUltraWideCamera:
                availableCameras.append(.ultraWide)
            case .builtInTelephotoCamera:
                availableCameras.append(.telephoto)
            default:
                break
            }
        }

        print("📷 Available cameras: \(availableCameras)")
    }

    // MARK: - Connection

    public func connectToGlasses() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DualCameraError.sessionNotInitialized)
                    return
                }

                do {
                    // Create multi-cam session
                    let session = AVCaptureMultiCamSession()
                    session.beginConfiguration()

                    // Try to configure at least two cameras for stereo
                    let camerasToUse = self.selectOptimalCameraPair()
                    guard camerasToUse.count >= 2 else {
                        throw DualCameraError.insufficientCameras
                    }

                    // Configure each camera
                    for cameraType in camerasToUse {
                        try self.addCamera(cameraType, to: session)
                    }

                    session.commitConfiguration()
                    self.multiCamSession = session

                    // Start running
                    session.startRunning()

                    Task { @MainActor in
                        self.isConnected = true
                        print("✅ Connected to multi-camera system: \(camerasToUse)")
                    }

                    continuation.resume()
                } catch {
                    Task { @MainActor in
                        self.errorMessage = "Failed to connect: \(error.localizedDescription)"
                    }
                    continuation.resume(throwing: DualCameraError.connectionFailed(error))
                }
            }
        }
    }

    private func selectOptimalCameraPair() -> [CameraType] {
        // Prefer back + ultraWide for best stereo effect
        if availableCameras.contains(.back) && availableCameras.contains(.ultraWide) {
            return [.back, .ultraWide]
        }
        // Fallback to back + telephoto
        else if availableCameras.contains(.back) && availableCameras.contains(.telephoto) {
            return [.back, .telephoto]
        }
        // Last resort: front + back
        else if availableCameras.contains(.front) && availableCameras.contains(.back) {
            return [.front, .back]
        }
        // Return whatever is available
        return Array(availableCameras.prefix(2))
    }

    private func addCamera(_ cameraType: CameraType, to session: AVCaptureMultiCamSession) throws {
        // Find the device
        guard let device = AVCaptureDevice.default(
            cameraType.avDeviceType,
            for: .video,
            position: cameraType.avPosition
        ) else {
            throw DualCameraError.cameraNotAvailable(cameraType)
        }

        // Configure device for optimal quality
        try device.lockForConfiguration()

        // Set highest quality preset
        if device.activeFormat.isHighestQualityFormat {
            // Already using highest quality
        } else {
            // Find and set highest resolution format
            if let bestFormat = device.formats.max(by: { format1, format2 in
                let dims1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
                let dims2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)
                return (dims1.width * dims1.height) < (dims2.width * dims2.height)
            }) {
                device.activeFormat = bestFormat
            }
        }

        // Enable auto-focus and exposure if available
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        device.unlockForConfiguration()

        // Create device input
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw DualCameraError.cannotAddInput(cameraType)
        }
        session.addInput(input)
        captureDevices[cameraType] = device

        // Add photo output
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .quality

        guard session.canAddOutput(photoOutput) else {
            throw DualCameraError.cannotAddOutput(cameraType)
        }
        session.addOutput(photoOutput)

        // Configure connection
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        photoOutputs[cameraType] = photoOutput

        print("✅ Added camera: \(cameraType)")
    }

    public func disconnect() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.multiCamSession?.stopRunning()
                self?.multiCamSession = nil
                self?.captureDevices.removeAll()
                self?.photoOutputs.removeAll()

                Task { @MainActor in
                    self?.isConnected = false
                    print("🔌 Disconnected from camera system")
                }

                continuation.resume()
            }
        }
    }

    // MARK: - Dual Camera Capture

    /// Capture images from both cameras simultaneously for 3D imaging
    public func captureStereoImage() async throws -> StereoPair {
        guard isConnected else {
            throw DualCameraError.notConnected
        }

        guard let session = multiCamSession, session.isRunning else {
            throw DualCameraError.sessionNotRunning
        }

        isCapturing = true
        captureProgress = 0.0
        capturedPhotos.removeAll()

        do {
            print("📸 Starting dual camera capture...")

            // Get the camera pair to use
            let camerasToUse = photoOutputs.keys.sorted { $0.description < $1.description }
            guard camerasToUse.count >= 2 else {
                throw DualCameraError.insufficientCameras
            }

            let leftCamera = camerasToUse[0]
            let rightCamera = camerasToUse[1]

            // Capture from both cameras simultaneously using Task groups
            let (leftData, rightData) = try await withThrowingTaskGroup(of: (CameraType, Data).self) { group in

                // Capture from left camera
                group.addTask {
                    print("📷 Capturing from \(leftCamera)...")
                    let data = try await self.captureFromCamera(leftCamera)
                    return (leftCamera, data)
                }

                // Capture from right camera
                group.addTask {
                    print("📷 Capturing from \(rightCamera)...")
                    let data = try await self.captureFromCamera(rightCamera)
                    return (rightCamera, data)
                }

                var leftImageData: Data?
                var rightImageData: Data?

                // Collect results
                for try await (cameraType, imageData) in group {
                    if cameraType == leftCamera {
                        leftImageData = imageData
                        await MainActor.run {
                            self.captureProgress = 0.5
                        }
                        print("✅ Left camera (\(leftCamera)) captured: \(imageData.count) bytes")
                    } else if cameraType == rightCamera {
                        rightImageData = imageData
                        await MainActor.run {
                            self.captureProgress = 1.0
                        }
                        print("✅ Right camera (\(rightCamera)) captured: \(imageData.count) bytes")
                    }
                }

                guard let left = leftImageData, let right = rightImageData else {
                    throw DualCameraError.incompleteStereoCapture
                }

                return (left, right)
            }

            // Convert data to images
            guard let leftImage = UIImage(data: leftData),
                  let rightImage = UIImage(data: rightData) else {
                throw DualCameraError.invalidImageData
            }

            let stereoPair = StereoPair(
                leftImage: leftImage,
                rightImage: rightImage,
                timestamp: Date(),
                metadata: StereoPairMetadata(
                    leftCamera: leftCamera.toGeneric(),
                    rightCamera: rightCamera.toGeneric(),
                    captureMode: .simultaneous
                )
            )

            capturedStereoPairs.append(stereoPair)
            isCapturing = false
            captureProgress = 0.0

            print("✅ Stereo pair captured successfully")
            return stereoPair

        } catch {
            isCapturing = false
            captureProgress = 0.0
            errorMessage = "Failed to capture stereo image: \(error.localizedDescription)"
            throw DualCameraError.captureFailed(error)
        }
    }

    private func captureFromCamera(_ cameraType: CameraType) async throws -> Data {
        guard let photoOutput = photoOutputs[cameraType] else {
            throw DualCameraError.cameraNotAvailable(cameraType)
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DualCameraError.sessionNotInitialized)
                    return
                }

                // Store continuation for callback
                self.photoContinuations[cameraType] = continuation

                // Configure photo settings
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality

                // Enable HEIF if available for better quality
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings.photoCodecType = .hevc
                }

                // Create delegate handler
                let delegate = PhotoCaptureDelegate(cameraType: cameraType) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let data):
                            self.photoContinuations[cameraType]?.resume(returning: data)
                        case .failure(let error):
                            self.photoContinuations[cameraType]?.resume(throwing: error)
                        }
                        self.photoContinuations.removeValue(forKey: cameraType)
                    }
                }

                // Capture photo
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// Capture multiple stereo pairs for 3D reconstruction
    public func captureMultipleStereoPairs(count: Int = 3, delay: TimeInterval = 2.0) async throws -> [StereoPair] {
        var pairs: [StereoPair] = []

        for i in 1...count {
            print("📸 Capturing stereo pair \(i) of \(count)")
            let pair = try await captureStereoImage()
            pairs.append(pair)

            if i < count {
                print("⏳ Waiting \(delay)s before next capture...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        print("✅ Captured \(pairs.count) stereo pairs")
        return pairs
    }

    // MARK: - Preview Support

    /// Get preview layer for a specific camera (for UI display)
    public func previewLayer(for cameraType: CameraType) -> AVCaptureVideoPreviewLayer? {
        guard let session = multiCamSession,
              let device = captureDevices[cameraType] else {
            return nil
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill

        return previewLayer
    }

    /// Export stereo pair for 3D viewing (side-by-side format)
    public func exportSideBySide(_ stereoPair: StereoPair) -> UIImage? {
        let leftImage = stereoPair.leftImage
        let rightImage = stereoPair.rightImage

        // Determine output size (side by side)
        let width = leftImage.size.width + rightImage.size.width
        let height = max(leftImage.size.height, rightImage.size.height)
        let size = CGSize(width: width, height: height)

        // Create combined image
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Draw left image
        leftImage.draw(in: CGRect(x: 0, y: 0, width: leftImage.size.width, height: leftImage.size.height))

        // Draw right image
        rightImage.draw(in: CGRect(x: leftImage.size.width, y: 0, width: rightImage.size.width, height: rightImage.size.height))

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Export stereo pair for 3D viewing (anaglyph red/cyan format)
    public func exportAnaglyph(_ stereoPair: StereoPair) -> UIImage? {
        guard let leftCIImage = CIImage(image: stereoPair.leftImage),
              let rightCIImage = CIImage(image: stereoPair.rightImage) else {
            return nil
        }

        let context = CIContext()

        // Extract red channel from left image
        let leftRed = leftCIImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])

        // Extract cyan channels from right image
        let rightCyan = rightCIImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])

        // Combine channels
        guard let combined = leftRed.composited(over: rightCyan) as CIImage?,
              let cgImage = context.createCGImage(combined, from: combined.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Save stereo pair to photo library
    public func saveStereoPair(_ stereoPair: StereoPair, format: ExportFormat = .sideBySide) throws {
        let imageToSave: UIImage?

        switch format {
        case .sideBySide:
            imageToSave = exportSideBySide(stereoPair)
        case .anaglyph:
            imageToSave = exportAnaglyph(stereoPair)
        case .separate:
            // Save both images separately
            UIImageWriteToSavedPhotosAlbum(stereoPair.leftImage, nil, nil, nil)
            UIImageWriteToSavedPhotosAlbum(stereoPair.rightImage, nil, nil, nil)
            print("💾 Both images saved separately")
            return
        }

        if let image = imageToSave {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            print("💾 Stereo image saved (\(format))")
        }
    }

    public func clearCapturedImages() {
        capturedStereoPairs.removeAll()
    }
}

// MARK: - Supporting Extensions

extension DualCameraManager.CameraType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        case .ultraWide: return "UltraWide"
        case .telephoto: return "Telephoto"
        }
    }

    func toGeneric() -> CameraTypeGeneric {
        switch self {
        case .front: return .imaging
        case .back: return .imaging
        case .ultraWide: return .navigation
        case .telephoto: return .imaging
        }
    }
}

extension DualCameraManager.CameraType: Comparable {
    public static func < (lhs: DualCameraManager.CameraType, rhs: DualCameraManager.CameraType) -> Bool {
        return lhs.description < rhs.description
    }
}

// MARK: - AVCaptureFormat Extension

extension AVCaptureDevice.Format {
    var isHighestQualityFormat: Bool {
        // Check if this format is already one of the highest quality available
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return dimensions.width >= 3840 || dimensions.height >= 2160 // 4K or higher
    }
}

// MARK: - Error Types

public enum DualCameraError: LocalizedError {
    case sessionNotInitialized
    case notConnected
    case sessionNotRunning
    case connectionFailed(Error)
    case captureFailed(Error)
    case invalidImageData
    case incompleteStereoCapture
    case insufficientCameras
    case cameraNotAvailable(DualCameraManager.CameraType)
    case cannotAddInput(DualCameraManager.CameraType)
    case cannotAddOutput(DualCameraManager.CameraType)
    case photoDataUnavailable

    public var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Camera session not initialized"
        case .notConnected:
            return "Not connected to camera system"
        case .sessionNotRunning:
            return "Camera session is not running"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .captureFailed(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .invalidImageData:
            return "Invalid image data from camera"
        case .incompleteStereoCapture:
            return "Failed to capture from both cameras"
        case .insufficientCameras:
            return "Insufficient cameras available for stereo capture (need at least 2)"
        case .cameraNotAvailable(let type):
            return "Camera not available: \(type)"
        case .cannotAddInput(let type):
            return "Cannot add input for camera: \(type)"
        case .cannotAddOutput(let type):
            return "Cannot add output for camera: \(type)"
        case .photoDataUnavailable:
            return "Photo data unavailable from capture"
        }
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let cameraType: DualCameraManager.CameraType
    private let completion: (Result<Data, Error>) -> Void

    init(cameraType: DualCameraManager.CameraType, completion: @escaping (Result<Data, Error>) -> Void) {
        self.cameraType = cameraType
        self.completion = completion
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            completion(.failure(DualCameraError.captureFailed(error)))
            return
        }

        guard let photoData = photo.fileDataRepresentation() else {
            completion(.failure(DualCameraError.photoDataUnavailable))
            return
        }

        completion(.success(photoData))
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("📸 Photo captured from \(cameraType)")
    }
}
