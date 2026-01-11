import UIKit
import CoreLocation
import Photos

/// Intelligent Automation System
/// Auto-capture, tagging, organization, and smart suggestions
@MainActor
public class SmartAutomation {

    // MARK: - Singleton
    public static let shared = SmartAutomation()

    // MARK: - Properties
    private let personalAI = PersonalAI.shared
    private let objectDetector = ObjectDetector.shared
    private let ocr = AdvancedOCR.shared
    private var isMonitoring = false
    private var captureQueue: [CaptureTask] = []

    // Settings
    public var autoCapture Enabled = false
    public var autoTagEnabled = true
    public var autoOrganizeEnabled = true
    public var momentScoreThreshold: Double = 0.75

    // Callbacks
    public var onMomentDetected: ((MomentScore) -> Void)?
    public var onAutoCapture: ((UIImage) -> Void)?
    public var onSuggestion: ((SmartSuggestion) -> Void)?

    // MARK: - Initialization
    private init() {
        print("🤖 SmartAutomation initialized")
    }

    // MARK: - Monitoring

    /// Start monitoring for auto-capture moments
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        print("👁️ Smart monitoring started - watching for important moments")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        isMonitoring = false
        print("👁️ Smart monitoring stopped")
    }

    // MARK: - Auto-Capture

    /// Analyze frame for auto-capture worthiness
    public func analyzeFrame(_ image: UIImage) async -> MomentScore {
        // Get personal context
        let context = await personalAI.getCurrentContext()

        // Detect objects and people
        let objects = try? await objectDetector.detectObjects(in: image)
        let faces = try? await personalAI.analyzeWithContext(image)

        var score: Double = 0.0
        var reasons: [String] = []

        // VIP detection (high priority)
        if let recognizedPeople = faces?.recognizedPeople, !recognizedPeople.isEmpty {
            score += 0.3
            reasons.append("\(recognizedPeople.count) VIP(s) detected")
        }

        // Interesting scene
        if let objects = objects, !objects.isEmpty {
            score += Double(min(objects.count, 5)) * 0.05
            reasons.append("\(objects.count) objects detected")
        }

        // Perfect lighting
        let brightness = analyzeBrightness(image)
        if brightness > 0.4 && brightness < 0.7 {
            score += 0.15
            reasons.append("Perfect lighting")
        }

        // Special location
        if let location = context.location {
            // Check if it's a new or interesting location
            score += 0.1
            reasons.append("Interesting location")
        }

        // Golden hour
        if context.timeOfDay == .evening {
            score += 0.1
            reasons.append("Golden hour")
        }

        // Action detected
        if let objects = objects {
            if objects.contains(where: { $0.category == .animal }) {
                score += 0.15
                reasons.append("Animals present")
            }
        }

        let momentScore = MomentScore(
            score: min(score, 1.0),
            reasons: reasons,
            timestamp: Date()
        )

        // Auto-capture if score is high enough
        if autoCaptureEnabled && momentScore.score >= momentScoreThreshold {
            print("📸 Auto-capturing moment (score: \(String(format: "%.2f", momentScore.score)))")
            onAutoCapture?(image)
        }

        onMomentDetected?(momentScore)

        return momentScore
    }

    // MARK: - Auto-Tagging

    /// Automatically tag photo with detected content
    public func autoTag(_ image: UIImage) async -> [String] {
        guard autoTagEnabled else { return [] }

        var tags: [String] = []

        // Detect objects
        if let objects = try? await objectDetector.detectObjects(in: image) {
            tags.append(contentsOf: objects.map { $0.label })
        }

        // Recognize text
        if let ocrResult = try? await ocr.recognizeText(in: image) {
            if !ocrResult.fullText.isEmpty {
                tags.append("text")
            }
            if let language = ocrResult.detectedLanguage {
                tags.append("language:\(language)")
            }
        }

        // Location tag
        let context = await personalAI.getCurrentContext()
        if let location = context.location {
            tags.append("location")
        }

        // Time-based tags
        switch context.timeOfDay {
        case .morning: tags.append("morning")
        case .afternoon: tags.append("afternoon")
        case .evening: tags.append("evening")
        case .night: tags.append("night")
        }

        print("🏷️ Auto-tagged with \(tags.count) tags")

        return Array(Set(tags)) // Remove duplicates
    }

    // MARK: - Auto-Organization

    /// Organize photos into smart albums
    public func organizeIntoAlbums(_ photos: [PhotoAsset]) async -> [SmartAlbum] {
        guard autoOrganizeEnabled else { return [] }

        var albums: [String: [PhotoAsset]] = [:]

        for photo in photos {
            // Organize by people
            if !photo.recognizedPeople.isEmpty {
                for person in photo.recognizedPeople {
                    albums["People: \(person)", default: []].append(photo)
                }
            }

            // Organize by date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateKey = dateFormatter.string(from: photo.timestamp)
            albums["Date: \(dateKey)", default: []].append(photo)

            // Organize by location
            if let location = photo.location {
                albums["Location: \(location)", default: []].append(photo)
            }

            // Organize by content
            for tag in photo.tags {
                albums["Tag: \(tag)", default: []].append(photo)
            }
        }

        let smartAlbums = albums.map { SmartAlbum(name: $0.key, photos: $0.value) }

        print("📁 Organized into \(smartAlbums.count) smart albums")

        return smartAlbums
    }

    // MARK: - Smart Suggestions

    /// Generate contextual suggestions
    public func generateSuggestions() async -> [SmartSuggestion] {
        let context = await personalAI.getCurrentContext()
        var suggestions: [SmartSuggestion] = []

        // Suggest capturing VIPs if nearby
        if !context.nearbyVIPs.isEmpty {
            suggestions.append(SmartSuggestion(
                type: .captureVIP,
                message: "Capture moment with \(context.nearbyVIPs.joined(separator: ", "))",
                priority: .high
            ))
        }

        // Suggest based on time of day
        switch context.timeOfDay {
        case .evening:
            suggestions.append(SmartSuggestion(
                type: .goldenHour,
                message: "Perfect golden hour lighting for portraits!",
                priority: .high
            ))
        case .morning:
            suggestions.append(SmartSuggestion(
                type: .lighting,
                message: "Great morning light for landscape photos",
                priority: .medium
            ))
        default:
            break
        }

        // Suggest based on upcoming events
        if let event = context.upcomingEvents.first {
            suggestions.append(SmartSuggestion(
                type: .event,
                message: "Document '\(event.title)' coming up?",
                priority: .medium
            ))
        }

        // Suggest creating highlight reel
        // In production, check if there are enough recent photos
        suggestions.append(SmartSuggestion(
            type: .highlightReel,
            message: "Create highlight reel from today's photos?",
            priority: .low
        ))

        for suggestion in suggestions {
            onSuggestion?(suggestion)
        }

        return suggestions
    }

    // MARK: - Image Analysis

    private func analyzeBrightness(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0.0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Calculate average brightness
        var totalBrightness: UInt64 = 0
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = UInt64(pixelData[i])
            let g = UInt64(pixelData[i + 1])
            let b = UInt64(pixelData[i + 2])
            totalBrightness += (r + g + b) / 3
        }

        let pixelCount = width * height
        let averageBrightness = Double(totalBrightness) / Double(pixelCount) / 255.0

        return averageBrightness
    }
}

// MARK: - Supporting Types

public struct MomentScore {
    public let score: Double
    public let reasons: [String]
    public let timestamp: Date

    public var shouldCapture: Bool {
        return score >= 0.75
    }
}

public struct CaptureTask {
    public let id: UUID
    public let reason: String
    public let priority: Priority
    public let timestamp: Date

    public enum Priority {
        case low, medium, high, urgent
    }
}

public struct SmartAlbum {
    public let name: String
    public let photos: [PhotoAsset]
}

public struct PhotoAsset {
    public let id: UUID
    public let timestamp: Date
    public let recognizedPeople: [String]
    public let location: String?
    public let tags: [String]
}

public struct SmartSuggestion {
    public let type: SuggestionType
    public let message: String
    public let priority: Priority

    public enum SuggestionType {
        case captureVIP
        case goldenHour
        case lighting
        case event
        case highlightReel
        case share
        case edit
    }

    public enum Priority {
        case low, medium, high
    }
}
