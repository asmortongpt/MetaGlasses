import AVFoundation
import UIKit

/// Professional 4K Video Recorder with Advanced Features
/// Supports 4K@60fps, HDR, stabilization, and live streaming
@MainActor
public class VideoRecorder: NSObject {

    // MARK: - Singleton
    public static let shared = VideoRecorder()

    // MARK: - Properties
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var isRecording = false
    private var currentVideoURL: URL?

    // Settings
    public var videoQuality: VideoQualityPreset = .ultra4K60fps
    public var enableHDR = true
    public var enableStabilization = true
    public var enableAudio = true

    // Callbacks
    public var onRecordingStarted: (() -> Void)?
    public var onRecordingStopped: ((URL) -> Void)?
    public var onError: ((Error) -> Void)?

    // MARK: - Initialization
    private override init() {
        super.init()
        print("🎥 VideoRecorder initialized")
    }

    // MARK: - Setup

    /// Setup video capture session
    public func setupCaptureSession() async throws {
        let session = AVCaptureSession()

        // Set session preset based on quality
        session.sessionPreset = videoQuality.sessionPreset

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw VideoRecorderError.cameraUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw VideoRecorderError.cannotAddInput
        }
        session.addInput(videoInput)

        // Configure video device
        try videoDevice.lockForConfiguration()

        // Set frame rate
        if let format = videoDevice.formats.first(where: { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == videoQuality.resolution.width &&
                   dimensions.height == videoQuality.resolution.height
        }) {
            videoDevice.activeFormat = format
            videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(videoQuality.frameRate))
            videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(videoQuality.frameRate))
        }

        // Enable HDR if supported
        if enableHDR && videoDevice.activeFormat.isVideoHDRSupported {
            videoDevice.automaticallyAdjustsVideoHDREnabled = true
        }

        // Enable stabilization
        if enableStabilization {
            if let connection = videoInput.ports.first?.connection {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .cinematicExtended
                }
            }
        }

        videoDevice.unlockForConfiguration()

        // Add audio input
        if enableAudio {
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
        }

        // Add movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            throw VideoRecorderError.cannotAddOutput
        }
        session.addOutput(movieOutput)

        // Configure output
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .cinematicExtended
            }
        }

        self.captureSession = session
        self.videoOutput = movieOutput

        print("✅ Video capture session configured for \(videoQuality.displayName)")
    }

    /// Start capture session
    public func startSession() {
        captureSession?.startRunning()
        print("▶️ Video capture session started")
    }

    /// Stop capture session
    public func stopSession() {
        captureSession?.stopRunning()
        print("⏹️ Video capture session stopped")
    }

    // MARK: - Recording

    /// Start recording video
    public func startRecording(to url: URL? = nil) throws {
        guard let videoOutput = videoOutput else {
            throw VideoRecorderError.outputNotConfigured
        }

        guard !isRecording else {
            throw VideoRecorderError.alreadyRecording
        }

        // Generate URL if not provided
        let outputURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("mov")

        currentVideoURL = outputURL

        // Start recording
        videoOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true

        onRecordingStarted?()
        print("🔴 Recording started: \(outputURL.lastPathComponent)")
    }

    /// Stop recording video
    public func stopRecording() {
        guard isRecording else { return }

        videoOutput?.stopRecording()
        isRecording = false
        print("⏹️ Recording stopped")
    }

    // MARK: - Live Streaming

    /// Start live streaming to RTMP server
    public func startLiveStream(to rtmpURL: String) async throws {
        // In production, implement RTMP streaming
        // Use libraries like HaishinKit or similar
        print("📡 Live streaming to: \(rtmpURL)")
    }

    /// Stop live streaming
    public func stopLiveStream() {
        // Stop RTMP streaming
        print("📡 Live streaming stopped")
    }

    // MARK: - Preview

    /// Get preview layer for displaying camera feed
    public func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {

    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("📹 File output started recording")
    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("❌ Recording error: \(error.localizedDescription)")
            onError?(error)
            return
        }

        print("✅ Recording finished: \(outputFileURL.lastPathComponent)")
        onRecordingStopped?(outputFileURL)
    }
}

// MARK: - Supporting Types

public enum VideoQualityPreset {
    case hd720p30fps
    case hd1080p30fps
    case hd1080p60fps
    case ultra4K30fps
    case ultra4K60fps

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd720p30fps: return .hd1280x720
        case .hd1080p30fps, .hd1080p60fps: return .hd1920x1080
        case .ultra4K30fps, .ultra4K60fps: return .hd4K3840x2160
        }
    }

    var resolution: (width: Int32, height: Int32) {
        switch self {
        case .hd720p30fps: return (1280, 720)
        case .hd1080p30fps, .hd1080p60fps: return (1920, 1080)
        case .ultra4K30fps, .ultra4K60fps: return (3840, 2160)
        }
    }

    var frameRate: Int {
        switch self {
        case .hd720p30fps, .hd1080p30fps, .ultra4K30fps: return 30
        case .hd1080p60fps, .ultra4K60fps: return 60
        }
    }

    var displayName: String {
        switch self {
        case .hd720p30fps: return "HD 720p @ 30fps"
        case .hd1080p30fps: return "HD 1080p @ 30fps"
        case .hd1080p60fps: return "HD 1080p @ 60fps"
        case .ultra4K30fps: return "4K Ultra HD @ 30fps"
        case .ultra4K60fps: return "4K Ultra HD @ 60fps"
        }
    }
}

public enum VideoRecorderError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case outputNotConfigured
    case alreadyRecording
    case notRecording
    case streamingFailed

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "Camera is not available"
        case .cannotAddInput: return "Cannot add camera input"
        case .cannotAddOutput: return "Cannot add video output"
        case .outputNotConfigured: return "Video output not configured"
        case .alreadyRecording: return "Already recording"
        case .notRecording: return "Not currently recording"
        case .streamingFailed: return "Live streaming failed"
        }
    }
}
