import Foundation
import UIKit
import Combine

/// Test version of DualCameraManager that works in the simulator
/// Uses MockDATSession instead of real Meta SDK
@MainActor
public class TestDualCameraManager: ObservableObject {

    // MARK: - Camera Types

    public enum CameraType {
        case navigation
        case imaging
    }

    // MARK: - Published Properties

    @Published public var isConnected: Bool = false
    @Published public var capturedStereoPairs: [StereoPair] = []
    @Published public var errorMessage: String?
    @Published public var isCapturing: Bool = false
    @Published public var captureProgress: Double = 0.0

    // MARK: - Private Properties

    private var mockSession: MockDATSession?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        setupSession()
    }

    // MARK: - Setup

    private func setupSession() {
        mockSession = MockDATSession.shared
        mockSession?.delegate = self
        print("✅ Test session initialized (Mock mode)")
    }

    // MARK: - Connection

    public func connectToGlasses() async throws {
        guard let session = mockSession else {
            throw TestCameraError.sessionNotInitialized
        }

        do {
            try await session.connect()
            isConnected = true
            print("✅ Test: Connected to mock glasses")
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            throw TestCameraError.connectionFailed(error)
        }
    }

    public func disconnect() async {
        await mockSession?.disconnect()
        isConnected = false
        print("🔌 Test: Disconnected from mock glasses")
    }

    // MARK: - Dual Camera Capture

    public func captureStereoImage() async throws -> StereoPair {
        guard isConnected else {
            throw TestCameraError.notConnected
        }

        guard let session = mockSession else {
            throw TestCameraError.sessionNotInitialized
        }

        isCapturing = true
        captureProgress = 0.0

        do {
            print("📸 Test: Starting mock dual camera capture...")

            // Capture from both cameras simultaneously
            let stereoPair = try await withThrowingTaskGroup(of: (CameraType, Data).self) { group in

                // Navigation camera
                group.addTask {
                    print("📷 Test: Capturing from navigation camera...")
                    let data = try await session.capturePhoto(from: .navigation)
                    return (.navigation, data)
                }

                // Imaging camera
                group.addTask {
                    print("📷 Test: Capturing from imaging camera...")
                    let data = try await session.capturePhoto(from: .imaging)
                    return (.imaging, data)
                }

                var navigationImage: UIImage?
                var imagingImage: UIImage?

                // Collect results
                for try await (cameraType, imageData) in group {
                    guard let image = UIImage(data: imageData) else {
                        throw TestCameraError.invalidImageData
                    }

                    switch cameraType {
                    case .navigation:
                        navigationImage = image
                        captureProgress = 0.5
                        print("✅ Test: Navigation camera captured")
                    case .imaging:
                        imagingImage = image
                        captureProgress = 1.0
                        print("✅ Test: Imaging camera captured")
                    }
                }

                guard let navImage = navigationImage, let imgImage = imagingImage else {
                    throw TestCameraError.incompleteStereoCapture
                }

                return StereoPair(
                    leftImage: navImage,
                    rightImage: imgImage,
                    timestamp: Date(),
                    metadata: StereoPairMetadata(
                        leftCamera: .navigation,
                        rightCamera: .imaging,
                        captureMode: .simultaneous
                    )
                )
            }

            capturedStereoPairs.append(stereoPair)
            isCapturing = false
            captureProgress = 0.0

            print("✅ Test: Stereo pair captured successfully")
            return stereoPair

        } catch {
            isCapturing = false
            captureProgress = 0.0
            errorMessage = "Failed to capture: \(error.localizedDescription)"
            throw TestCameraError.captureFailed(error)
        }
    }

    public func captureMultipleStereoPairs(count: Int = 3, delay: TimeInterval = 2.0) async throws -> [StereoPair] {
        var pairs: [StereoPair] = []

        for i in 1...count {
            print("📸 Test: Capturing stereo pair \(i) of \(count)")
            let pair = try await captureStereoImage()
            pairs.append(pair)

            if i < count {
                print("⏳ Test: Waiting \(delay)s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        return pairs
    }

    // MARK: - Export Methods

    public func exportSideBySide(_ stereoPair: StereoPair) -> UIImage? {
        let leftImage = stereoPair.leftImage
        let rightImage = stereoPair.rightImage

        let width = leftImage.size.width + rightImage.size.width
        let height = max(leftImage.size.height, rightImage.size.height)
        let size = CGSize(width: width, height: height)

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        leftImage.draw(in: CGRect(x: 0, y: 0, width: leftImage.size.width, height: leftImage.size.height))
        rightImage.draw(in: CGRect(x: leftImage.size.width, y: 0, width: rightImage.size.width, height: rightImage.size.height))

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    public func exportAnaglyph(_ stereoPair: StereoPair) -> UIImage? {
        guard let leftCIImage = CIImage(image: stereoPair.leftImage),
              let rightCIImage = CIImage(image: stereoPair.rightImage) else {
            return nil
        }

        let context = CIContext()

        let leftRed = leftCIImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])

        let rightCyan = rightCIImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])

        guard let combined = leftRed.composited(over: rightCyan) as CIImage?,
              let cgImage = context.createCGImage(combined, from: combined.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    public func saveStereoPair(_ stereoPair: StereoPair, format: ExportFormat = .sideBySide) throws {
        let imageToSave: UIImage?

        switch format {
        case .sideBySide:
            imageToSave = exportSideBySide(stereoPair)
        case .anaglyph:
            imageToSave = exportAnaglyph(stereoPair)
        case .separate:
            UIImageWriteToSavedPhotosAlbum(stereoPair.leftImage, nil, nil, nil)
            UIImageWriteToSavedPhotosAlbum(stereoPair.rightImage, nil, nil, nil)
            print("💾 Test: Both images saved")
            return
        }

        if let image = imageToSave {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            print("💾 Test: Stereo image saved (\(format))")
        }
    }

    public func clearCapturedImages() {
        capturedStereoPairs.removeAll()
    }
}

// MARK: - MockDATSessionDelegate

extension TestDualCameraManager: MockDATSessionDelegate {

    public func sessionDidConnect(_ session: MockDATSession) {
        isConnected = true
        print("✅ Test: Session connected")
    }

    public func sessionDidDisconnect(_ session: MockDATSession, error: Error?) {
        isConnected = false
        if let error = error {
            errorMessage = "Disconnected: \(error.localizedDescription)"
        }
    }

    public func session(_ session: MockDATSession, didFailWithError error: Error) {
        errorMessage = "Session error: \(error.localizedDescription)"
    }
}

// MARK: - Supporting Types (reused from main app)




// MARK: - Error Types

public enum TestCameraError: LocalizedError {
    case sessionNotInitialized
    case notConnected
    case connectionFailed(Error)
    case captureFailed(Error)
    case invalidImageData
    case incompleteStereoCapture

    public var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Test session not initialized"
        case .notConnected:
            return "Not connected to mock glasses"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .captureFailed(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .invalidImageData:
            return "Invalid test image data"
        case .incompleteStereoCapture:
            return "Failed to capture from both cameras"
        }
    }
}
