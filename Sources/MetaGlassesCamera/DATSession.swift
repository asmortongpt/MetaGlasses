import Foundation
import AVFoundation

/// Production-ready camera session wrapper
/// Can be replaced with Meta Wearables DAT SDK when available
/// Currently uses AVFoundation's AVCaptureSession for iPhone cameras
public class DATSession {
    public static var shared: DATSession = DATSession()
    public weak var delegate: DATSessionDelegate?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.metaglasses.datsession")
    private var isSessionRunning = false

    private init() {}

    // MARK: - Connection Management

    public func connect() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DATSessionError.sessionNotInitialized)
                    return
                }

                do {
                    // Create capture session
                    let session = AVCaptureSession()
                    session.beginConfiguration()

                    // Configure for high quality photo capture
                    if session.canSetSessionPreset(.photo) {
                        session.sessionPreset = .photo
                    }

                    // Get default camera (back camera)
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw DATSessionError.cameraNotAvailable
                    }

                    // Configure camera
                    try camera.lockForConfiguration()

                    if camera.isFocusModeSupported(.continuousAutoFocus) {
                        camera.focusMode = .continuousAutoFocus
                    }
                    if camera.isExposureModeSupported(.continuousAutoExposure) {
                        camera.exposureMode = .continuousAutoExposure
                    }
                    if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        camera.whiteBalanceMode = .continuousAutoWhiteBalance
                    }

                    camera.unlockForConfiguration()

                    // Add camera input
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(input) else {
                        throw DATSessionError.cannotAddInput
                    }
                    session.addInput(input)
                    self.currentDevice = camera

                    // Add photo output
                    let output = AVCapturePhotoOutput()
                    output.maxPhotoQualityPrioritization = .quality

                    guard session.canAddOutput(output) else {
                        throw DATSessionError.cannotAddOutput
                    }
                    session.addOutput(output)
                    self.photoOutput = output

                    session.commitConfiguration()
                    self.captureSession = session

                    // Start session
                    session.startRunning()
                    self.isSessionRunning = true

                    // Notify delegate
                    Task { @MainActor in
                        self.delegate?.sessionDidConnect(self)
                    }

                    print("✅ DATSession connected successfully")
                    continuation.resume()

                } catch {
                    print("❌ DATSession connection failed: \(error)")
                    Task { @MainActor in
                        self.delegate?.session(self, didFailWithError: error)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                self.captureSession?.stopRunning()
                self.captureSession = nil
                self.photoOutput = nil
                self.currentDevice = nil
                self.isSessionRunning = false

                Task { @MainActor in
                    self.delegate?.sessionDidDisconnect(self, error: nil)
                }

                print("🔌 DATSession disconnected")
                continuation.resume()
            }
        }
    }

    // MARK: - Photo Capture

    public func capturePhoto() async throws -> Data {
        guard isSessionRunning, let photoOutput = photoOutput else {
            throw DATSessionError.sessionNotRunning
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality

                // Enable HEIF if available
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings.photoCodecType = .hevc
                }

                let delegate = SimplePhotoCaptureDelegate { result in
                    switch result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: - Device Information

    public var isConnected: Bool {
        return isSessionRunning && captureSession != nil
    }

    public var deviceName: String {
        return currentDevice?.localizedName ?? "Unknown Device"
    }
}

// MARK: - Delegate Protocol

@MainActor
public protocol DATSessionDelegate: AnyObject {
    func sessionDidConnect(_ session: DATSession)
    func sessionDidDisconnect(_ session: DATSession, error: Error?)
    func session(_ session: DATSession, didFailWithError error: Error)
}

// MARK: - Errors

public enum DATSessionError: LocalizedError {
    case sessionNotInitialized
    case sessionNotRunning
    case cameraNotAvailable
    case cannotAddInput
    case cannotAddOutput
    case captureFailedError(Error)
    case photoDataUnavailable

    public var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Session not initialized"
        case .sessionNotRunning:
            return "Session is not running"
        case .cameraNotAvailable:
            return "Camera not available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add photo output to session"
        case .captureFailedError(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .photoDataUnavailable:
            return "Photo data unavailable"
        }
    }
}

// MARK: - Simple Photo Capture Delegate

private class SimplePhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            completion(.failure(DATSessionError.captureFailedError(error)))
            return
        }

        guard let photoData = photo.fileDataRepresentation() else {
            completion(.failure(DATSessionError.photoDataUnavailable))
            return
        }

        completion(.success(photoData))
    }
}
