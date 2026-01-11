import UIKit
import Vision
import CoreML

/// Advanced Hand Gesture Recognition
/// Detect and interpret hand gestures for touchless control
@MainActor
public class GestureRecognizer {

    // MARK: - Singleton
    public static let shared = GestureRecognizer()

    // MARK: - Properties
    private let queue = DispatchQueue(label: "com.metaglasses.gesture", qos: .userInitiated)
    private var gestureHistory: [RecognizedGesture] = []
    private let historyLimit = 10

    // MARK: - Initialization
    private init() {
        print("👋 GestureRecognizer initialized - Ready to recognize gestures")
    }

    // MARK: - Gesture Recognition

    /// Recognize hand gestures in image
    public func recognizeGesture(in image: UIImage) async throws -> GestureResult {
        guard let cgImage = image.cgImage else {
            throw GestureError.invalidImage
        }

        print("✋ Recognizing hand gestures...")

        // Detect hand pose
        let hands = try await detectHandPose(in: cgImage)

        guard !hands.isEmpty else {
            return GestureResult(gestures: [], confidence: 0.0)
        }

        // Analyze gestures from hand poses
        var recognizedGestures: [RecognizedGesture] = []

        for hand in hands {
            if let gesture = analyzeHandGesture(hand: hand) {
                recognizedGestures.append(gesture)
            }
        }

        // Update gesture history
        gestureHistory.append(contentsOf: recognizedGestures)
        if gestureHistory.count > historyLimit {
            gestureHistory.removeFirst(gestureHistory.count - historyLimit)
        }

        let avgConfidence = recognizedGestures.map { $0.confidence }.reduce(0, +) / Double(max(recognizedGestures.count, 1))

        print("✅ Recognized \(recognizedGestures.count) gestures")

        return GestureResult(
            gestures: recognizedGestures,
            confidence: avgConfidence
        )
    }

    /// Detect continuous gestures across multiple frames
    public func recognizeContinuousGesture(in frames: [UIImage]) async throws -> ContinuousGesture? {
        var allGestures: [[RecognizedGesture]] = []

        for frame in frames {
            let result = try await recognizeGesture(in: frame)
            allGestures.append(result.gestures)
        }

        // Analyze gesture sequence
        return analyzeContinuousGesture(gestureSequence: allGestures)
    }

    // MARK: - Gesture Analysis

    private func analyzeHandGesture(hand: HandPose) -> RecognizedGesture? {
        // Analyze finger positions and hand orientation
        let fingersExtended = countExtendedFingers(hand: hand)

        // Detect common gestures
        if fingersExtended == 0 {
            // Fist
            return RecognizedGesture(
                type: .fist,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date()
            )
        } else if fingersExtended == 1 && isIndexFingerExtended(hand: hand) {
            // Pointing
            return RecognizedGesture(
                type: .pointing,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date()
            )
        } else if fingersExtended == 2 && areIndexAndMiddleExtended(hand: hand) {
            // Peace sign / Victory
            return RecognizedGesture(
                type: .peace,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date()
            )
        } else if fingersExtended == 5 {
            // Open palm
            return RecognizedGesture(
                type: .openPalm,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date()
            )
        } else if fingersExtended == 1 && isThumbExtended(hand: hand) {
            // Thumbs up/down
            let direction = getThumbDirection(hand: hand)
            return RecognizedGesture(
                type: direction > 0 ? .thumbsUp : .thumbsDown,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date()
            )
        }

        return nil
    }

    private func countExtendedFingers(hand: HandPose) -> Int {
        var count = 0

        // Check each finger
        if isThumbExtended(hand: hand) { count += 1 }
        if isIndexFingerExtended(hand: hand) { count += 1 }
        if isMiddleFingerExtended(hand: hand) { count += 1 }
        if isRingFingerExtended(hand: hand) { count += 1 }
        if isPinkyExtended(hand: hand) { count += 1 }

        return count
    }

    private func isThumbExtended(hand: HandPose) -> Bool {
        guard let tip = hand.points[.thumbTip],
              let ip = hand.points[.thumbIP],
              let mp = hand.points[.thumbMP] else {
            return false
        }

        // Thumb is extended if tip is farther from palm than IP
        let tipDistance = distance(tip.location, hand.points[.wrist]?.location ?? .zero)
        let ipDistance = distance(ip.location, hand.points[.wrist]?.location ?? .zero)

        return tipDistance > ipDistance
    }

    private func isIndexFingerExtended(hand: HandPose) -> Bool {
        return isFingerExtended(finger: .indexFinger, hand: hand)
    }

    private func isMiddleFingerExtended(hand: HandPose) -> Bool {
        return isFingerExtended(finger: .middleFinger, hand: hand)
    }

    private func isRingFingerExtended(hand: HandPose) -> Bool {
        return isFingerExtended(finger: .ringFinger, hand: hand)
    }

    private func isPinkyExtended(hand: HandPose) -> Bool {
        return isFingerExtended(finger: .littleFinger, hand: hand)
    }

    private func isFingerExtended(finger: FingerType, hand: HandPose) -> Bool {
        let tipKey = jointKey(finger: finger, joint: "Tip")
        let dipKey = jointKey(finger: finger, joint: "DIP")
        let pipKey = jointKey(finger: finger, joint: "PIP")

        guard let tip = hand.points[tipKey],
              let dip = hand.points[dipKey],
              let pip = hand.points[pipKey] else {
            return false
        }

        // Finger is extended if tip is higher than PIP
        return tip.location.y < pip.location.y
    }

    private func areIndexAndMiddleExtended(hand: HandPose) -> Bool {
        return isIndexFingerExtended(hand: hand) &&
               isMiddleFingerExtended(hand: hand) &&
               !isRingFingerExtended(hand: hand) &&
               !isPinkyExtended(hand: hand)
    }

    private func getThumbDirection(hand: HandPose) -> Double {
        guard let tip = hand.points[.thumbTip],
              let wrist = hand.points[.wrist] else {
            return 0
        }

        // Positive = up, negative = down
        return Double(tip.location.y - wrist.location.y)
    }

    private func jointKey(finger: FingerType, joint: String) -> VNHumanHandPoseObservation.JointName {
        let fingerName: String
        switch finger {
        case .thumb: fingerName = "thumb"
        case .indexFinger: fingerName = "indexFinger"
        case .middleFinger: fingerName = "middleFinger"
        case .ringFinger: fingerName = "ringFinger"
        case .littleFinger: fingerName = "littleFinger"
        }

        return VNHumanHandPoseObservation.JointName(rawValue: "\(fingerName)\(joint)")
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Continuous Gesture Analysis

    private func analyzeContinuousGesture(gestureSequence: [[RecognizedGesture]]) -> ContinuousGesture? {
        // Detect continuous gestures like swipes, waves, etc.

        guard gestureSequence.count >= 3 else { return nil }

        // Check for wave (open palm moving side to side)
        if isWaveGesture(gestureSequence) {
            return ContinuousGesture(
                type: .wave,
                duration: Double(gestureSequence.count) * 0.033, // 30fps
                confidence: 0.8
            )
        }

        // Check for swipe (pointing finger moving consistently)
        if let direction = isSwipeGesture(gestureSequence) {
            return ContinuousGesture(
                type: .swipe(direction),
                duration: Double(gestureSequence.count) * 0.033,
                confidence: 0.7
            )
        }

        return nil
    }

    private func isWaveGesture(_ sequence: [[RecognizedGesture]]) -> Bool {
        // Check if open palm appears in multiple frames
        let openPalmCount = sequence.filter { gestures in
            gestures.contains { $0.type == .openPalm }
        }.count

        return Double(openPalmCount) / Double(sequence.count) > 0.6
    }

    private func isSwipeGesture(_ sequence: [[RecognizedGesture]]) -> SwipeDirection? {
        // Simplified swipe detection
        // In production, track finger tip positions across frames
        let pointingCount = sequence.filter { gestures in
            gestures.contains { $0.type == .pointing }
        }.count

        if Double(pointingCount) / Double(sequence.count) > 0.7 {
            return .right // Placeholder
        }

        return nil
    }

    // MARK: - Hand Pose Detection

    private func detectHandPose(in cgImage: CGImage) async throws -> [HandPose] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform([request])

                    var hands: [HandPose] = []

                    if let observations = request.results {
                        for observation in observations {
                            guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
                                continue
                            }

                            hands.append(HandPose(
                                confidence: observation.confidence,
                                points: recognizedPoints,
                                chirality: observation.chirality
                            ))
                        }
                    }

                    continuation.resume(returning: hands)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Supporting Types

public struct GestureResult {
    public let gestures: [RecognizedGesture]
    public let confidence: Double
}

public struct RecognizedGesture {
    public let type: GestureType
    public let handedness: VNChirality
    public let confidence: Double
    public let timestamp: Date
}

public struct HandPose {
    public let confidence: Double
    public let points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]
    public let chirality: VNChirality
}

public struct ContinuousGesture {
    public let type: ContinuousGestureType
    public let duration: TimeInterval
    public let confidence: Double
}

public enum GestureType {
    case fist
    case openPalm
    case pointing
    case peace
    case thumbsUp
    case thumbsDown
    case pinch
    case grab
}

public enum ContinuousGestureType {
    case wave
    case swipe(SwipeDirection)
    case zoom
    case rotate
}

public enum SwipeDirection {
    case up, down, left, right
}

public enum FingerType {
    case thumb
    case indexFinger
    case middleFinger
    case ringFinger
    case littleFinger
}

public enum GestureError: LocalizedError {
    case invalidImage
    case detectionFailed
    case noHandsDetected

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image provided"
        case .detectionFailed: return "Gesture detection failed"
        case .noHandsDetected: return "No hands detected in image"
        }
    }
}
