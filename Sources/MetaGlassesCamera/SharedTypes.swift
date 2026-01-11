import Foundation
import UIKit

// Shared types used across the application
// Defined once to avoid ambiguity

public struct StereoPair: Identifiable {
    public let id = UUID()
    public let leftImage: UIImage
    public let rightImage: UIImage
    public let timestamp: Date
    public let metadata: StereoPairMetadata

    public init(leftImage: UIImage, rightImage: UIImage, timestamp: Date, metadata: StereoPairMetadata) {
        self.leftImage = leftImage
        self.rightImage = rightImage
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public struct StereoPairMetadata {
    public let leftCamera: CameraTypeGeneric
    public let rightCamera: CameraTypeGeneric
    public let captureMode: CaptureMode

    public enum CaptureMode {
        case simultaneous
        case sequential
    }

    public init(leftCamera: CameraTypeGeneric, rightCamera: CameraTypeGeneric, captureMode: CaptureMode) {
        self.leftCamera = leftCamera
        self.rightCamera = rightCamera
        self.captureMode = captureMode
    }
}

public enum CameraTypeGeneric {
    case navigation
    case imaging
}

public enum ExportFormat {
    case sideBySide
    case anaglyph
    case separate
}
