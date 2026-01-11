import Foundation
import UIKit

/// Mock implementation of Meta Wearables DAT Session for simulator testing
/// This allows testing without physical Meta Ray-Ban glasses
public class MockDATSession {

    // MARK: - Singleton

    public static let shared = MockDATSession()

    // MARK: - Properties

    public weak var delegate: MockDATSessionDelegate?
    public private(set) var isConnected = false

    private var simulatedDelay: TimeInterval = 1.0

    // MARK: - Initialization

    private init() {
        print("🧪 MockDATSession initialized - Simulator mode enabled")
    }

    // MARK: - Connection

    public func connect() async throws {
        print("🧪 Mock: Simulating connection to glasses...")

        // Simulate connection delay
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        isConnected = true
        await delegate?.sessionDidConnect(self)

        print("✅ Mock: Connected successfully")
    }

    public func disconnect() async {
        print("🧪 Mock: Disconnecting...")
        isConnected = false
        await delegate?.sessionDidDisconnect(self, error: nil)
    }

    // MARK: - Camera Capture

    /// Captures a photo from the specified camera (mock implementation)
    public func capturePhoto(from camera: MockCameraType) async throws -> Data {
        guard isConnected else {
            throw MockDATError.notConnected
        }

        print("🧪 Mock: Capturing from \(camera)...")

        // Simulate capture delay
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 0.5 * 1_000_000_000))

        // Generate a mock image
        let image = generateMockImage(for: camera)

        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw MockDATError.imageConversionFailed
        }

        print("✅ Mock: Captured \(imageData.count) bytes from \(camera)")
        return imageData
    }

    // MARK: - Mock Image Generation

    private func generateMockImage(for camera: MockCameraType) -> UIImage {
        // Use realistic mock images instead of simple colored rectangles
        let (leftImage, rightImage) = RealisticMockImages.generateStereoImages()
        return camera == .navigation ? leftImage : rightImage

    }
}

// MARK: - Mock Camera Type

public enum MockCameraType: String {
    case navigation = "Navigation Camera"
    case imaging = "Imaging Camera"
}

// MARK: - Mock Delegate Protocol

@MainActor
public protocol MockDATSessionDelegate: AnyObject {
    func sessionDidConnect(_ session: MockDATSession)
    func sessionDidDisconnect(_ session: MockDATSession, error: Error?)
    func session(_ session: MockDATSession, didFailWithError error: Error)
}

// MARK: - Mock Errors

public enum MockDATError: LocalizedError {
    case notConnected
    case imageConversionFailed
    case simulationError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Mock session not connected"
        case .imageConversionFailed:
            return "Failed to convert mock image to data"
        case .simulationError(let message):
            return "Simulation error: \(message)"
        }
    }
}
