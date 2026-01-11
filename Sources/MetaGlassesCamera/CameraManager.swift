import Foundation
import UIKit
import Combine
// import MetaWearablesDAT  // Commented for simulator testing

/// Manages connection and image capture from Meta Ray-Ban smart glasses
@MainActor
public class CameraManager: ObservableObject {

    // MARK: - Published Properties

    @Published public var isConnected: Bool = false
    @Published public var capturedImages: [UIImage] = []
    @Published public var errorMessage: String?
    @Published public var isCapturing: Bool = false

    // MARK: - Private Properties

    private var wearablesSession: DATSession?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        setupSession()
    }

    // MARK: - Setup

    private func setupSession() {
        do {
            // Initialize Meta Wearables DAT Session
            wearablesSession = try DATSession.shared

            // Configure session
            wearablesSession?.delegate = self

            print("✅ Meta Wearables session initialized")
        } catch {
            errorMessage = "Failed to initialize wearables session: \(error.localizedDescription)"
            print("❌ Session initialization error: \(error)")
        }
    }

    // MARK: - Public Methods

    /// Connect to Meta Ray-Ban glasses
    public func connectToGlasses() async throws {
        guard let session = wearablesSession else {
            throw CameraError.sessionNotInitialized
        }

        do {
            // Request connection to glasses
            try await session.connect()
            isConnected = true
            print("✅ Connected to Meta glasses")
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            throw CameraError.connectionFailed(error)
        }
    }

    /// Disconnect from glasses
    public func disconnect() async {
        await wearablesSession?.disconnect()
        isConnected = false
        print("🔌 Disconnected from glasses")
    }

    /// Capture a single image from the glasses camera
    public func captureImage() async throws -> UIImage {
        guard isConnected else {
            throw CameraError.notConnected
        }

        guard let session = wearablesSession else {
            throw CameraError.sessionNotInitialized
        }

        isCapturing = true

        do {
            // Request photo capture from glasses
            let imageData = try await session.capturePhoto()

            guard let image = UIImage(data: imageData) else {
                throw CameraError.invalidImageData
            }

            capturedImages.append(image)
            isCapturing = false

            print("✅ Image captured successfully")
            return image

        } catch {
            isCapturing = false
            errorMessage = "Failed to capture image: \(error.localizedDescription)"
            throw CameraError.captureFailed(error)
        }
    }

    /// Capture multiple images in sequence
    public func captureMultipleImages(count: Int = 3, delay: TimeInterval = 1.0) async throws -> [UIImage] {
        var images: [UIImage] = []

        for i in 1...count {
            print("📸 Capturing image \(i) of \(count)")
            let image = try await captureImage()
            images.append(image)

            if i < count {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        return images
    }

    /// Save image to photo library
    public func saveToPhotoLibrary(_ image: UIImage) throws {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        print("💾 Image saved to photo library")
    }

    /// Clear all captured images
    public func clearCapturedImages() {
        capturedImages.removeAll()
    }
}

// MARK: - DATSessionDelegate

extension CameraManager: DATSessionDelegate {

    public func sessionDidConnect(_ session: DATSession) {
        isConnected = true
        print("✅ Session connected")
    }

    public func sessionDidDisconnect(_ session: DATSession, error: Error?) {
        isConnected = false
        if let error = error {
            errorMessage = "Disconnected with error: \(error.localizedDescription)"
            print("❌ Disconnected with error: \(error)")
        } else {
            print("🔌 Session disconnected")
        }
    }

    public func session(_ session: DATSession, didFailWithError error: Error) {
        errorMessage = "Session error: \(error.localizedDescription)"
        print("❌ Session error: \(error)")
    }
}

// MARK: - Error Types

public enum CameraError: LocalizedError {
    case sessionNotInitialized
    case notConnected
    case connectionFailed(Error)
    case captureFailed(Error)
    case invalidImageData

    public var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Camera session not initialized"
        case .notConnected:
            return "Not connected to glasses"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .captureFailed(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .invalidImageData:
            return "Invalid image data received"
        }
    }
}
