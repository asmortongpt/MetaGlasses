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
        // Calculate bounding box for hand
        let boundingBox = calculateHandBoundingBox(hand: hand)

        // Check for pinch gesture first (higher priority)
        if let pinchDistance = detectPinch(hand: hand), pinchDistance < 0.05 {
            return RecognizedGesture(
                type: .pinch,
                handedness: hand.chirality,
                confidence: hand.confidence * 0.95, // Slightly reduce confidence for precision gestures
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
            )
        }

        // Analyze finger positions and hand orientation
        let fingersExtended = countExtendedFingers(hand: hand)

        // Detect common gestures
        if fingersExtended == 0 {
            // Fist or Grab
            let gestureType: GestureType = isGrabGesture(hand: hand) ? .grab : .fist
            return RecognizedGesture(
                type: gestureType,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
            )
        } else if fingersExtended == 1 && isIndexFingerExtended(hand: hand) {
            // Pointing
            return RecognizedGesture(
                type: .pointing,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
            )
        } else if fingersExtended == 2 && areIndexAndMiddleExtended(hand: hand) {
            // Peace sign / Victory
            return RecognizedGesture(
                type: .peace,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
            )
        } else if fingersExtended == 5 {
            // Open palm
            return RecognizedGesture(
                type: .openPalm,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
            )
        } else if fingersExtended == 1 && isThumbExtended(hand: hand) {
            // Thumbs up/down
            let direction = getThumbDirection(hand: hand)
            return RecognizedGesture(
                type: direction > 0 ? .thumbsUp : .thumbsDown,
                handedness: hand.chirality,
                confidence: hand.confidence,
                timestamp: Date(),
                boundingBox: boundingBox,
                handPose: hand
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

    // MARK: - Advanced Gesture Detection

    private func detectPinch(hand: HandPose) -> CGFloat? {
        // Detect pinch by measuring distance between thumb tip and index finger tip
        guard let thumbTip = hand.points[.thumbTip],
              let indexTip = hand.points[.indexTip] else {
            return nil
        }

        // Both points must have high confidence
        guard thumbTip.confidence > 0.7 && indexTip.confidence > 0.7 else {
            return nil
        }

        let pinchDistance = distance(thumbTip.location, indexTip.location)
        return pinchDistance
    }

    private func isGrabGesture(hand: HandPose) -> Bool {
        // Distinguish between fist (static) and grab (fingers curled around object)
        // Check if all fingertips are close together and curled
        guard let thumbTip = hand.points[.thumbTip],
              let indexTip = hand.points[.indexTip],
              let middleTip = hand.points[.middleTip],
              let ringTip = hand.points[.ringTip],
              let littleTip = hand.points[.littleTip],
              let wrist = hand.points[.wrist] else {
            return false
        }

        // Calculate centroid of fingertips
        let centroidX = (thumbTip.location.x + indexTip.location.x + middleTip.location.x +
                        ringTip.location.x + littleTip.location.x) / 5
        let centroidY = (thumbTip.location.y + indexTip.location.y + middleTip.location.y +
                        ringTip.location.y + littleTip.location.y) / 5
        let centroid = CGPoint(x: centroidX, y: centroidY)

        // Check if fingertips are clustered (grab) vs spread (fist)
        let avgDistanceFromCentroid = [thumbTip, indexTip, middleTip, ringTip, littleTip]
            .map { distance($0.location, centroid) }
            .reduce(0, +) / 5

        // Grab has tighter clustering than fist
        return avgDistanceFromCentroid < 0.08
    }

    private func calculateHandBoundingBox(hand: HandPose) -> CGRect {
        // Calculate bounding box encompassing all hand points
        var minX: CGFloat = 1.0
        var maxX: CGFloat = 0.0
        var minY: CGFloat = 1.0
        var maxY: CGFloat = 0.0

        for (_, point) in hand.points {
            let location = point.location
            minX = min(minX, location.x)
            maxX = max(maxX, location.x)
            minY = min(minY, location.y)
            maxY = max(maxY, location.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Continuous Gesture Analysis

    private func analyzeContinuousGesture(gestureSequence: [[RecognizedGesture]]) -> ContinuousGesture? {
        // Detect continuous gestures like swipes, waves, etc.

        guard gestureSequence.count >= 3 else { return nil }

        // Check for two-handed gestures (zoom, rotate) with higher priority
        if let zoomGesture = detectZoomGesture(gestureSequence) {
            return zoomGesture
        }

        if let rotateGesture = detectRotateGesture(gestureSequence) {
            return rotateGesture
        }

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
        // Track finger tip positions across frames to detect swipe direction
        guard sequence.count >= 3 else { return nil }

        var horizontalMovements: [CGFloat] = []
        var verticalMovements: [CGFloat] = []

        // Analyze movement across consecutive frames
        for i in 0..<sequence.count - 1 {
            let currentGestures = sequence[i]
            let nextGestures = sequence[i + 1]

            // Find pointing gestures to track finger tip
            if let currentPointing = currentGestures.first(where: { $0.type == .pointing }),
               let nextPointing = nextGestures.first(where: { $0.type == .pointing }) {

                // Calculate movement delta
                let deltaX = nextPointing.boundingBox.midX - currentPointing.boundingBox.midX
                let deltaY = nextPointing.boundingBox.midY - currentPointing.boundingBox.midY

                horizontalMovements.append(deltaX)
                verticalMovements.append(deltaY)
            }
        }

        guard !horizontalMovements.isEmpty else { return nil }

        // Calculate average movement
        let avgHorizontal = horizontalMovements.reduce(0, +) / CGFloat(horizontalMovements.count)
        let avgVertical = verticalMovements.reduce(0, +) / CGFloat(verticalMovements.count)

        // Determine dominant direction
        let threshold: CGFloat = 0.05

        if abs(avgHorizontal) > abs(avgVertical) && abs(avgHorizontal) > threshold {
            return avgHorizontal > 0 ? .right : .left
        } else if abs(avgVertical) > threshold {
            return avgVertical > 0 ? .down : .up
        }

        return nil
    }

    private func detectZoomGesture(_ sequence: [[RecognizedGesture]]) -> ContinuousGesture? {
        // Detect pinch-to-zoom or two-finger zoom gesture
        guard sequence.count >= 3 else { return nil }

        var pinchDistances: [CGFloat] = []

        for gestures in sequence {
            // Look for two hands with pinch gestures or open palms
            let leftHand = gestures.first { $0.handedness == .left }
            let rightHand = gestures.first { $0.handedness == .right }

            guard let left = leftHand, let right = rightHand else { continue }

            // Calculate distance between hands
            let distance = self.distance(left.boundingBox.center, right.boundingBox.center)
            pinchDistances.append(distance)
        }

        guard pinchDistances.count >= 3 else { return nil }

        // Calculate change in distance (zoom in/out)
        let initialDistance = pinchDistances.first!
        let finalDistance = pinchDistances.last!
        let distanceChange = finalDistance - initialDistance

        // Significant change indicates zoom
        if abs(distanceChange) > 0.1 {
            return ContinuousGesture(
                type: .zoom,
                duration: Double(sequence.count) * 0.033,
                confidence: 0.75
            )
        }

        return nil
    }

    private func detectRotateGesture(_ sequence: [[RecognizedGesture]]) -> ContinuousGesture? {
        // Detect rotation gesture using two fingers/hands
        guard sequence.count >= 3 else { return nil }

        var angles: [CGFloat] = []

        for gestures in sequence {
            // Look for two hands
            let leftHand = gestures.first { $0.handedness == .left }
            let rightHand = gestures.first { $0.handedness == .right }

            guard let left = leftHand, let right = rightHand else { continue }

            // Calculate angle between hands
            let dx = right.boundingBox.midX - left.boundingBox.midX
            let dy = right.boundingBox.midY - left.boundingBox.midY
            let angle = atan2(dy, dx)
            angles.append(angle)
        }

        guard angles.count >= 3 else { return nil }

        // Calculate total rotation
        var totalRotation: CGFloat = 0
        for i in 0..<angles.count - 1 {
            var delta = angles[i + 1] - angles[i]

            // Normalize angle difference to -π to π
            if delta > .pi {
                delta -= 2 * .pi
            } else if delta < -.pi {
                delta += 2 * .pi
            }

            totalRotation += delta
        }

        // Significant rotation detected
        if abs(totalRotation) > 0.3 { // ~17 degrees
            return ContinuousGesture(
                type: .rotate,
                duration: Double(sequence.count) * 0.033,
                confidence: 0.7
            )
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
    public let boundingBox: CGRect
    public let handPose: HandPose?

    public init(type: GestureType, handedness: VNChirality, confidence: Double, timestamp: Date, boundingBox: CGRect = .zero, handPose: HandPose? = nil) {
        self.type = type
        self.handedness = handedness
        self.confidence = confidence
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        self.handPose = handPose
    }
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

// MARK: - Helper Extensions

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
