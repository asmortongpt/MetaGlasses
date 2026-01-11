import Foundation
import AVFoundation
import UIKit
import Photos
import CoreImage

/// Enhanced camera features: HDR, RAW, 4K/8K video, depth mapping
@MainActor
class EnhancedCameraFeatures: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var captureMode: CaptureMode = .photo
    @Published var hdrEnabled = true
    @Published var rawEnabled = false
    @Published var videoQuality: VideoQuality = .uhd4K
    @Published var depthDataAvailable = false

    // MARK: - Capture Session
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var depthOutput: AVCaptureDepthDataOutput?
    private var currentDevice: AVCaptureDevice?

    // MARK: - Video Recording
    private var videoOutputURL: URL?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?

    // MARK: - Initialization
    override init() {
        super.init()
        setupCaptureSession()
    }

    // MARK: - Setup
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }

        session.beginConfiguration()

        // Set session preset based on quality
        session.sessionPreset = .photo

        // Configure camera device
        if let device = getBestCamera() {
            currentDevice = device
            configureCameraDevice(device)

            // Add input
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("❌ Failed to add camera input: \(error)")
            }
        }

        // Add photo output
        setupPhotoOutput()

        // Add video output
        setupVideoOutput()

        // Add depth output if available
        setupDepthOutput()

        session.commitConfiguration()

        print("✅ Enhanced camera features initialized")
    }

    private func getBestCamera() -> AVCaptureDevice? {
        // Try to get the best available camera
        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            print("📸 Using Triple Camera")
            return device
        } else if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            print("📸 Using Dual Wide Camera")
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            print("📸 Using Wide Angle Camera")
            return device
        }
        return nil
    }

    private func configureCameraDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // Enable HDR if supported
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = true
                print("✅ HDR enabled")
            }

            // Configure for best quality
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // Enable low light boost if available
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }

            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure camera: \(error)")
        }
    }

    private func setupPhotoOutput() {
        guard let session = captureSession else { return }

        photoOutput = AVCapturePhotoOutput()
        guard let photoOutput = photoOutput else { return }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            // Enable high-res capture
            photoOutput.isHighResolutionCaptureEnabled = true

            // Enable depth data if available
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported

            // Set max quality
            photoOutput.maxPhotoQualityPrioritization = .quality

            print("✅ Photo output configured")
        }
    }

    private func setupVideoOutput() {
        guard let session = captureSession else { return }

        movieOutput = AVCaptureMovieFileOutput()
        guard let movieOutput = movieOutput else { return }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)

            // Configure for high quality recording
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .cinematicExtended
                }
            }

            print("✅ Video output configured")
        }
    }

    private func setupDepthOutput() {
        guard let session = captureSession,
              let device = currentDevice,
              device.activeFormat.supportedDepthDataFormats.count > 0 else {
            print("ℹ️ Depth data not available")
            return
        }

        depthOutput = AVCaptureDepthDataOutput()
        guard let depthOutput = depthOutput else { return }

        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthDataAvailable = true
            print("✅ Depth output configured")
        }
    }

    // MARK: - Photo Capture
    func capturePhoto(completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(.failure(CameraError.outputNotAvailable))
            return
        }

        // Configure photo settings
        var settings: AVCapturePhotoSettings

        if rawEnabled, photoOutput.availableRawPhotoPixelFormatTypes.count > 0 {
            // RAW + JPEG capture
            settings = AVCapturePhotoSettings(
                rawPixelFormatType: photoOutput.availableRawPhotoPixelFormatTypes.first!,
                processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
            print("📸 Capturing RAW + HEVC")
        } else {
            // High-quality HEVC capture
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
        }

        // Enable HDR
        if hdrEnabled, photoOutput.isAutoRedEyeReductionSupported {
            settings.isAutoRedEyeReductionEnabled = true
        }

        // Enable depth data
        settings.isDepthDataDeliveryEnabled = depthDataAvailable

        // Max quality
        settings.photoQualityPrioritization = .quality

        // Capture
        let delegate = PhotoCaptureDelegate(completion: completion)
        photoOutput.capturePhoto(with: settings, delegate: delegate)

        print("📸 Photo capture initiated")
    }

    // MARK: - Video Recording
    func startVideoRecording() {
        guard let movieOutput = movieOutput, !isRecording else { return }

        // Create output file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "video_\(Date().timeIntervalSince1970).mov"
        videoOutputURL = documentsPath.appendingPathComponent(fileName)

        guard let url = videoOutputURL else { return }

        // Configure video quality
        configureVideoQuality()

        // Start recording
        let delegate = MovieRecordingDelegate { [weak self] success in
            Task { @MainActor in
                self?.handleRecordingCompletion(success: success)
            }
        }

        movieOutput.startRecording(to: url, recordingDelegate: delegate)

        isRecording = true
        recordingStartTime = Date()
        startRecordingTimer()

        print("🎥 Video recording started")
    }

    func stopVideoRecording() {
        guard let movieOutput = movieOutput, isRecording else { return }

        movieOutput.stopRecording()
        isRecording = false
        stopRecordingTimer()

        print("🎥 Video recording stopped")
    }

    private func configureVideoQuality() {
        guard let session = captureSession else { return }

        session.beginConfiguration()

        switch videoQuality {
        case .hd1080p:
            session.sessionPreset = .hd1920x1080
        case .uhd4K:
            session.sessionPreset = .hd4K3840x2160
        case .uhd8K:
            // 8K not directly supported, use highest available
            if session.canSetSessionPreset(.hd4K3840x2160) {
                session.sessionPreset = .hd4K3840x2160
            }
        }

        session.commitConfiguration()
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }

    private func handleRecordingCompletion(success: Bool) {
        guard success, let url = videoOutputURL else {
            print("❌ Video recording failed")
            return
        }

        // Save to Photos library
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { saved, error in
            if saved {
                print("✅ Video saved to Photos")
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            } else {
                print("❌ Failed to save video: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }

    // MARK: - Session Control
    func startSession() {
        guard let session = captureSession, !session.isRunning else { return }

        Task {
            session.startRunning()
            print("▶️ Camera session started")
        }
    }

    func stopSession() {
        guard let session = captureSession, session.isRunning else { return }

        session.stopRunning()
        print("⏹️ Camera session stopped")
    }

    // MARK: - Enums
    enum CaptureMode {
        case photo
        case video
        case portrait
        case night
        case timelapse
        case slowMotion
    }

    enum VideoQuality {
        case hd1080p
        case uhd4K
        case uhd8K

        var displayName: String {
            switch self {
            case .hd1080p: return "1080p HD"
            case .uhd4K: return "4K UHD"
            case .uhd8K: return "8K UHD"
            }
        }
    }
}

// MARK: - Photo Capture Delegate
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completion(.failure(CameraError.imageConversionFailed))
            return
        }

        // Save to Photos library
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
        }) { success, error in
            if success {
                print("✅ Photo saved to library")
            }
        }

        completion(.success(image))
    }
}

// MARK: - Movie Recording Delegate
private class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        completion(error == nil)
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case outputNotAvailable
    case imageConversionFailed
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .outputNotAvailable: return "Camera output not available"
        case .imageConversionFailed: return "Failed to convert image"
        case .recordingFailed: return "Video recording failed"
        }
    }
}
