import Foundation
import UIKit
import Combine
// import MetaWearablesDAT  // Commented for simulator testing

/// Manages dual camera capture from Meta Ray-Ban glasses for stereoscopic 3D imaging
@MainActor
public class DualCameraManager: ObservableObject {

    // MARK: - Camera Types

    public enum CameraType {
        case navigation  // Lower resolution camera for navigation/tracking
        case imaging     // High resolution camera for photography (12 MP)
    }

    // MARK: - Published Properties

    @Published public var isConnected: Bool = false
    @Published public var capturedStereoPairs: [StereoPair] = []
    @Published public var errorMessage: String?
    @Published public var isCapturing: Bool = false
    @Published public var captureProgress: Double = 0.0

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
            wearablesSession = try DATSession.shared
            wearablesSession?.delegate = self
            print("✅ Dual camera session initialized")
        } catch {
            errorMessage = "Failed to initialize session: \(error.localizedDescription)"
            print("❌ Session initialization error: \(error)")
        }
    }

    // MARK: - Connection

    public func connectToGlasses() async throws {
        guard let session = wearablesSession else {
            throw DualCameraError.sessionNotInitialized
        }

        do {
            try await session.connect()
            isConnected = true
            print("✅ Connected to Meta glasses (dual camera mode)")
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            throw DualCameraError.connectionFailed(error)
        }
    }

    public func disconnect() async {
        await wearablesSession?.disconnect()
        isConnected = false
        print("🔌 Disconnected from glasses")
    }

    // MARK: - Dual Camera Capture

    /// Capture images from both cameras simultaneously for 3D imaging
    public func captureStereoImage() async throws -> StereoPair {
        guard isConnected else {
            throw DualCameraError.notConnected
        }

        guard let session = wearablesSession else {
            throw DualCameraError.sessionNotInitialized
        }

        isCapturing = true
        captureProgress = 0.0

        do {
            print("📸 Starting dual camera capture...")

            // Capture from both cameras simultaneously using Task groups
            let stereoPair = try await withThrowingTaskGroup(of: (CameraType, Data).self) { group in

                // Capture from navigation camera
                group.addTask {
                    print("📷 Capturing from navigation camera...")
                    let data = try await session.captureFromCamera(.navigation)
                    return (.navigation, data)
                }

                // Capture from imaging camera
                group.addTask {
                    print("📷 Capturing from imaging camera...")
                    let data = try await session.captureFromCamera(.imaging)
                    return (.imaging, data)
                }

                var navigationImage: UIImage?
                var imagingImage: UIImage?

                // Collect results
                for try await (cameraType, imageData) in group {
                    guard let image = UIImage(data: imageData) else {
                        throw DualCameraError.invalidImageData
                    }

                    switch cameraType {
                    case .navigation:
                        navigationImage = image
                        captureProgress = 0.5
                        print("✅ Navigation camera captured")
                    case .imaging:
                        imagingImage = image
                        captureProgress = 1.0
                        print("✅ Imaging camera captured")
                    }
                }

                guard let navImage = navigationImage, let imgImage = imagingImage else {
                    throw DualCameraError.incompleteStereoCapture
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

            print("✅ Stereo pair captured successfully")
            return stereoPair

        } catch {
            isCapturing = false
            captureProgress = 0.0
            errorMessage = "Failed to capture stereo image: \(error.localizedDescription)"
            throw DualCameraError.captureFailed(error)
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

// MARK: - DATSessionDelegate

extension DualCameraManager: DATSessionDelegate {

    public func sessionDidConnect(_ session: DATSession) {
        isConnected = true
        print("✅ Dual camera session connected")
    }

    public func sessionDidDisconnect(_ session: DATSession, error: Error?) {
        isConnected = false
        if let error = error {
            errorMessage = "Disconnected: \(error.localizedDescription)"
        }
    }

    public func session(_ session: DATSession, didFailWithError error: Error) {
        errorMessage = "Session error: \(error.localizedDescription)"
    }
}

// MARK: - Supporting Types




// MARK: - Error Types

public enum DualCameraError: LocalizedError {
    case sessionNotInitialized
    case notConnected
    case connectionFailed(Error)
    case captureFailed(Error)
    case invalidImageData
    case incompleteStereoCapture

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
            return "Invalid image data from camera"
        case .incompleteStereoCapture:
            return "Failed to capture from both cameras"
        }
    }
}

// MARK: - DATSession Extensions (Mock API - replace with actual SDK methods)

extension DATSession {
    /// Capture from specific camera
    func captureFromCamera(_ cameraType: DualCameraManager.CameraType) async throws -> Data {
        // This is a placeholder for the actual Meta SDK API
        // Replace with actual SDK method when available
        // Example: try await self.capturePhoto(from: cameraType == .navigation ? .navigationCamera : .imagingCamera)

        // For now, this would use the SDK's actual camera selection API
        fatalError("Replace with actual Meta SDK camera selection API")
    }
}
