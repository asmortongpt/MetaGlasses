import Foundation
import UIKit
import Vision
import CoreML
import CoreLocation

/// Predictive Photo Suggestions System
/// ML-based photo-worthiness scoring, aesthetic quality prediction, and intelligent timing
@MainActor
public class PredictivePhotoSuggestions: ObservableObject {

    // MARK: - Singleton
    public static let shared = PredictivePhotoSuggestions()

    // MARK: - Published Properties
    @Published public var currentScore: Float = 0
    @Published public var shouldTakePhoto: Bool = false
    @Published public var suggestions: [PhotoSuggestion] = []
    @Published public var learningStats: LearningStatistics

    // MARK: - Private Properties
    private var userPreferences: UserPhotoPreferences
    private var photoHistory: [PhotoHistoryEntry] = []
    private let ragMemory = ProductionRAGMemory.shared
    private let maxHistorySize = 1000

    // Real-time analysis
    private var recentScores: [Float] = []
    private let scoreWindowSize = 10

    // MARK: - Initialization
    private init() {
        self.userPreferences = UserPhotoPreferences()
        self.learningStats = LearningStatistics()
        print("📸 PredictivePhotoSuggestions initialized")
        loadPhotoHistory()
    }

    // MARK: - Real-time Photo Scoring

    /// Analyze current scene for photo-worthiness in real-time
    public func analyzePhotoWorthiness(
        image: UIImage,
        location: CLLocation? = nil,
        timeOfDay: TimeOfDay? = nil
    ) async throws -> PhotoWorthinessScore {
        // Parallel analysis
        async let aestheticScore = evaluateAestheticQuality(image: image)
        async let compositionScore = evaluateComposition(image: image)
        async let lightingScore = evaluateLighting(image: image)
        async let interestScore = evaluateInterestLevel(image: image)
        async let contextScore = evaluateContextualRelevance(
            location: location,
            timeOfDay: timeOfDay ?? getCurrentTimeOfDay()
        )

        // Wait for all scores
        let scores = try await (
            aesthetic: aestheticScore,
            composition: compositionScore,
            lighting: lightingScore,
            interest: interestScore,
            context: contextScore
        )

        // Calculate weighted overall score
        let overallScore = calculateOverallScore(
            aesthetic: scores.aesthetic,
            composition: scores.composition,
            lighting: scores.lighting,
            interest: scores.interest,
            context: scores.context
        )

        // Apply user preferences
        let personalizedScore = applyUserPreferences(score: overallScore, image: image)

        // Create photo worthiness score
        let worthiness = PhotoWorthinessScore(
            overallScore: personalizedScore,
            aestheticScore: scores.aesthetic,
            compositionScore: scores.composition,
            lightingScore: scores.lighting,
            interestScore: scores.interest,
            contextScore: scores.context,
            confidence: calculateConfidence(scores: scores),
            timestamp: Date()
        )

        // Update real-time tracking
        updateRealtimeScores(personalizedScore)
        currentScore = personalizedScore

        // Check if should suggest photo
        shouldTakePhoto = personalizedScore >= userPreferences.photoThreshold

        // Generate suggestion if score is high
        if shouldTakePhoto {
            await generatePhotoSuggestion(worthiness: worthiness, image: image)
        }

        return worthiness
    }

    // MARK: - Aesthetic Quality Evaluation

    private func evaluateAestheticQuality(image: UIImage) async throws -> Float {
        guard let cgImage = image.cgImage else {
            throw PhotoError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use Vision's aesthetic scoring
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])

                    guard let results = request.results else {
                        continuation.resume(returning: 0.5)
                        return
                    }

                    // Analyze classification results for aesthetic indicators
                    var aestheticScore: Float = 0

                    let aestheticKeywords = [
                        "landscape", "sunset", "portrait", "architecture",
                        "nature", "flower", "art", "beautiful"
                    ]

                    for result in results.prefix(10) {
                        let identifier = result.identifier.lowercased()
                        let hasAesthetic = aestheticKeywords.contains { identifier.contains($0) }

                        if hasAesthetic {
                            aestheticScore += Float(result.confidence)
                        }
                    }

                    // Normalize to 0-1
                    let normalizedScore = min(max(aestheticScore, 0), 1)
                    continuation.resume(returning: normalizedScore)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Composition Evaluation

    private func evaluateComposition(image: UIImage) async throws -> Float {
        guard let cgImage = image.cgImage else {
            throw PhotoError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            var compositionScore: Float = 0.5

            // Evaluate saliency (rule of thirds)
            let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([saliencyRequest])

                    if let result = saliencyRequest.results?.first,
                       let salientObjects = result.salientObjects {
                        // Check if salient objects follow rule of thirds
                        let ruleOfThirdsScore = self.evaluateRuleOfThirds(
                            salientObjects: salientObjects
                        )

                        // Check balance
                        let balanceScore = self.evaluateBalance(
                            salientObjects: salientObjects
                        )

                        compositionScore = (ruleOfThirdsScore + balanceScore) / 2
                    }

                    continuation.resume(returning: compositionScore)
                } catch {
                    continuation.resume(returning: 0.5)
                }
            }
        }
    }

    private func evaluateRuleOfThirds(salientObjects: [VNSaliencyImageObservation.SalientObject]) -> Float {
        // Rule of thirds: ideal positions at 1/3 and 2/3
        let idealPositions: [CGFloat] = [0.33, 0.67]
        var bestScore: Float = 0

        for obj in salientObjects {
            let centerX = obj.boundingBox.midX
            let centerY = obj.boundingBox.midY

            // Check how close to ideal positions
            let xScore = idealPositions.map { abs(centerX - $0) }.min() ?? 1
            let yScore = idealPositions.map { abs(centerY - $0) }.min() ?? 1

            let score = Float(1.0 - ((xScore + yScore) / 2))
            bestScore = max(bestScore, score)
        }

        return bestScore
    }

    private func evaluateBalance(salientObjects: [VNSaliencyImageObservation.SalientObject]) -> Float {
        guard !salientObjects.isEmpty else { return 0.5 }

        // Calculate center of mass
        var totalX: CGFloat = 0
        var totalY: CGFloat = 0

        for obj in salientObjects {
            totalX += obj.boundingBox.midX
            totalY += obj.boundingBox.midY
        }

        let avgX = totalX / CGFloat(salientObjects.count)
        let avgY = totalY / CGFloat(salientObjects.count)

        // Ideal center is 0.5, 0.5
        let xDeviation = abs(avgX - 0.5)
        let yDeviation = abs(avgY - 0.5)

        return Float(1.0 - ((xDeviation + yDeviation) / 2))
    }

    // MARK: - Lighting Evaluation

    private func evaluateLighting(image: UIImage) async throws -> Float {
        guard let cgImage = image.cgImage else {
            throw PhotoError.invalidImage
        }

        // Analyze brightness and contrast
        let brightness = calculateAverageBrightness(cgImage: cgImage)
        let contrast = calculateContrast(cgImage: cgImage)

        // Ideal brightness: 0.4-0.6, ideal contrast: 0.5-0.8
        let brightnessScore = 1.0 - abs(brightness - 0.5) * 2
        let contrastScore = min(max((contrast - 0.3) / 0.5, 0), 1)

        return Float((brightnessScore + contrastScore) / 2)
    }

    private func calculateAverageBrightness(cgImage: CGImage) -> CGFloat {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }

        let length = CFDataGetLength(data)
        var totalBrightness: CGFloat = 0
        var count = 0

        // Sample every 1000th pixel for performance
        stride(from: 0, to: length, by: 4000).forEach { i in
            let r = CGFloat(bytes[i]) / 255.0
            let g = CGFloat(bytes[i + 1]) / 255.0
            let b = CGFloat(bytes[i + 2]) / 255.0

            // Calculate perceived brightness
            totalBrightness += (0.299 * r + 0.587 * g + 0.114 * b)
            count += 1
        }

        return count > 0 ? totalBrightness / CGFloat(count) : 0.5
    }

    private func calculateContrast(cgImage: CGImage) -> CGFloat {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }

        let length = CFDataGetLength(data)
        var brightnesses: [CGFloat] = []

        // Sample pixels
        stride(from: 0, to: length, by: 4000).forEach { i in
            let r = CGFloat(bytes[i]) / 255.0
            let g = CGFloat(bytes[i + 1]) / 255.0
            let b = CGFloat(bytes[i + 2]) / 255.0
            brightnesses.append(0.299 * r + 0.587 * g + 0.114 * b)
        }

        guard !brightnesses.isEmpty else { return 0.5 }

        let min = brightnesses.min() ?? 0
        let max = brightnesses.max() ?? 1

        return max - min
    }

    // MARK: - Interest Level Evaluation

    private func evaluateInterestLevel(image: UIImage) async throws -> Float {
        guard let cgImage = image.cgImage else {
            throw PhotoError.invalidImage
        }

        var interestScore: Float = 0

        // Detect interesting subjects
        let requests: [VNRequest] = [
            VNRecognizeAnimalsRequest(),
            VNDetectHumanRectanglesRequest(),
            VNDetectFaceRectanglesRequest()
        ]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform(requests)

                    // Animals are interesting
                    if let animals = (requests[0] as? VNRecognizeAnimalsRequest)?.results,
                       !animals.isEmpty {
                        interestScore += 0.3
                    }

                    // People are interesting
                    if let humans = (requests[1] as? VNDetectHumanRectanglesRequest)?.results,
                       !humans.isEmpty {
                        interestScore += 0.3
                    }

                    // Faces are very interesting
                    if let faces = (requests[2] as? VNDetectFaceRectanglesRequest)?.results,
                       !faces.isEmpty {
                        interestScore += 0.4
                    }

                    continuation.resume(returning: min(interestScore, 1.0))
                } catch {
                    continuation.resume(returning: 0.3)
                }
            }
        }
    }

    // MARK: - Contextual Relevance

    private func evaluateContextualRelevance(
        location: CLLocation?,
        timeOfDay: TimeOfDay
    ) async -> Float {
        var contextScore: Float = 0.5

        // Golden hour bonus
        if timeOfDay == .goldenHour || timeOfDay == .sunset {
            contextScore += 0.3
        }

        // Blue hour bonus
        if timeOfDay == .blueHour {
            contextScore += 0.2
        }

        // Location-based scoring (if at interesting location)
        if let location = location {
            let interestingLocation = await isInterestingLocation(location)
            if interestingLocation {
                contextScore += 0.2
            }
        }

        return min(contextScore, 1.0)
    }

    private func isInterestingLocation(_ location: CLLocation) async -> Bool {
        // Check if location is near known interesting places
        // In production, would query location database
        return false
    }

    // MARK: - Score Calculation

    private func calculateOverallScore(
        aesthetic: Float,
        composition: Float,
        lighting: Float,
        interest: Float,
        context: Float
    ) -> Float {
        // Weighted average
        let weights: [Float] = [0.25, 0.2, 0.25, 0.2, 0.1]
        let scores = [aesthetic, composition, lighting, interest, context]

        return zip(weights, scores).map { $0 * $1 }.reduce(0, +)
    }

    private func calculateConfidence(
        scores: (aesthetic: Float, composition: Float, lighting: Float, interest: Float, context: Float)
    ) -> Float {
        // Confidence based on variance
        let scoreArray = [scores.aesthetic, scores.composition, scores.lighting, scores.interest, scores.context]
        let mean = scoreArray.reduce(0, +) / Float(scoreArray.count)
        let variance = scoreArray.map { pow($0 - mean, 2) }.reduce(0, +) / Float(scoreArray.count)

        // Lower variance = higher confidence
        return 1.0 - min(variance * 2, 1.0)
    }

    // MARK: - User Preferences

    private func applyUserPreferences(score: Float, image: UIImage) -> Float {
        var adjustedScore = score

        // Learn from user's photo history
        let historicalBonus = calculateHistoricalBonus(image: image)
        adjustedScore += historicalBonus * 0.2

        return min(max(adjustedScore, 0), 1)
    }

    private func calculateHistoricalBonus(image: UIImage) -> Float {
        // Compare current image to accepted photos
        let acceptedPhotos = photoHistory.filter { $0.userAccepted }

        guard !acceptedPhotos.isEmpty else { return 0 }

        // Simple feature matching (in production, use ML embeddings)
        var similaritySum: Float = 0

        for entry in acceptedPhotos.prefix(20) {
            // Placeholder similarity calculation
            similaritySum += 0.5
        }

        return similaritySum / Float(min(acceptedPhotos.count, 20))
    }

    // MARK: - Photo Suggestions

    private func generatePhotoSuggestion(
        worthiness: PhotoWorthinessScore,
        image: UIImage
    ) async {
        // Generate timing suggestions
        let timingSuggestions = await generateTimingSuggestions(worthiness: worthiness)

        // Generate composition suggestions
        let compositionTips = generateCompositionTips(score: worthiness)

        let suggestion = PhotoSuggestion(
            timestamp: Date(),
            score: worthiness.overallScore,
            reason: generateSuggestionReason(worthiness: worthiness),
            timingSuggestions: timingSuggestions,
            compositionTips: compositionTips,
            optimalTiming: determineOptimalTiming()
        )

        suggestions.append(suggestion)
        if suggestions.count > 50 {
            suggestions.removeFirst(suggestions.count - 50)
        }

        print("📸 Photo suggestion: \(suggestion.reason)")
    }

    private func generateSuggestionReason(worthiness: PhotoWorthinessScore) -> String {
        var reasons: [String] = []

        if worthiness.aestheticScore > 0.7 {
            reasons.append("Great aesthetic quality")
        }
        if worthiness.compositionScore > 0.7 {
            reasons.append("Excellent composition")
        }
        if worthiness.lightingScore > 0.7 {
            reasons.append("Perfect lighting")
        }
        if worthiness.interestScore > 0.7 {
            reasons.append("Interesting subject")
        }

        return reasons.isEmpty ? "Good photo opportunity" : reasons.joined(separator: ", ")
    }

    private func generateTimingSuggestions(worthiness: PhotoWorthinessScore) async -> [String] {
        var suggestions: [String] = []

        let currentTime = getCurrentTimeOfDay()

        if currentTime == .goldenHour {
            suggestions.append("Perfect golden hour lighting!")
        } else if worthiness.lightingScore < 0.5 {
            suggestions.append("Wait for better lighting")
        }

        if worthiness.compositionScore < 0.6 {
            suggestions.append("Adjust framing slightly")
        }

        return suggestions
    }

    private func generateCompositionTips(score: PhotoWorthinessScore) -> [String] {
        var tips: [String] = []

        if score.compositionScore < 0.6 {
            tips.append("Try centering your subject on rule of thirds")
        }

        if score.lightingScore < 0.5 {
            tips.append("Face toward the light source")
        }

        return tips
    }

    private func determineOptimalTiming() -> Date {
        // Calculate next golden hour
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // Next golden hour is around sunset (approximate)
        if hour < 18 {
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        } else {
            // Tomorrow morning
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 6, minute: 30, second: 0, of: tomorrow) ?? now
        }
    }

    // MARK: - Learning System

    /// Record user's decision on a photo
    public func recordUserDecision(
        image: UIImage,
        score: PhotoWorthinessScore,
        accepted: Bool
    ) {
        let entry = PhotoHistoryEntry(
            timestamp: Date(),
            score: score,
            userAccepted: accepted,
            timeOfDay: getCurrentTimeOfDay()
        )

        photoHistory.append(entry)
        if photoHistory.count > maxHistorySize {
            photoHistory.removeFirst(photoHistory.count - maxHistorySize)
        }

        // Update preferences
        updateUserPreferences(entry: entry)

        // Update statistics
        updateLearningStatistics(accepted: accepted)

        savePhotoHistory()

        print("📊 Recorded user decision: \(accepted ? "✅" : "❌")")
    }

    private func updateUserPreferences(entry: PhotoHistoryEntry) {
        // Adjust threshold based on user behavior
        if entry.userAccepted {
            // Lower threshold if user accepts photos with lower scores
            if entry.score.overallScore < userPreferences.photoThreshold {
                userPreferences.photoThreshold = max(0.3, userPreferences.photoThreshold - 0.05)
            }
        } else {
            // Raise threshold if user rejects photos
            if entry.score.overallScore >= userPreferences.photoThreshold {
                userPreferences.photoThreshold = min(0.9, userPreferences.photoThreshold + 0.05)
            }
        }
    }

    private func updateLearningStatistics(accepted: Bool) {
        learningStats.totalEvaluations += 1

        if accepted {
            learningStats.photosAccepted += 1
        } else {
            learningStats.photosRejected += 1
        }

        learningStats.acceptanceRate = Float(learningStats.photosAccepted) / Float(learningStats.totalEvaluations)
        learningStats.lastUpdated = Date()
    }

    // MARK: - Real-time Tracking

    private func updateRealtimeScores(_ score: Float) {
        recentScores.append(score)
        if recentScores.count > scoreWindowSize {
            recentScores.removeFirst()
        }
    }

    public func getRecentTrend() -> PhotoTrend {
        guard recentScores.count >= 3 else {
            return .stable
        }

        let recent = recentScores.suffix(3)
        let earlier = recentScores.prefix(recentScores.count - 3)

        let recentAvg = recent.reduce(0, +) / Float(recent.count)
        let earlierAvg = earlier.reduce(0, +) / Float(max(earlier.count, 1))

        if recentAvg > earlierAvg + 0.1 {
            return .improving
        } else if recentAvg < earlierAvg - 0.1 {
            return .declining
        } else {
            return .stable
        }
    }

    // MARK: - Utilities

    private func getCurrentTimeOfDay() -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let timeValue = Float(hour) + Float(minute) / 60.0

        if timeValue >= 6 && timeValue < 7 {
            return .goldenHour
        } else if timeValue >= 17.5 && timeValue < 19 {
            return .goldenHour
        } else if timeValue >= 19 && timeValue < 20 {
            return .blueHour
        } else if timeValue >= 12 && timeValue < 16 {
            return .midday
        } else {
            return .other
        }
    }

    // MARK: - Persistence

    private var historyFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("photo_history.json")
    }

    private func savePhotoHistory() {
        if let data = try? JSONEncoder().encode(photoHistory) {
            try? data.write(to: historyFileURL)
        }
    }

    private func loadPhotoHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let loaded = try? JSONDecoder().decode([PhotoHistoryEntry].self, from: data) else {
            return
        }

        photoHistory = loaded
        print("📚 Loaded \(photoHistory.count) photo history entries")
    }
}

// MARK: - Supporting Types

public struct PhotoWorthinessScore {
    public let overallScore: Float
    public let aestheticScore: Float
    public let compositionScore: Float
    public let lightingScore: Float
    public let interestScore: Float
    public let contextScore: Float
    public let confidence: Float
    public let timestamp: Date
}

public struct PhotoSuggestion {
    public let timestamp: Date
    public let score: Float
    public let reason: String
    public let timingSuggestions: [String]
    public let compositionTips: [String]
    public let optimalTiming: Date
}

private struct PhotoHistoryEntry: Codable {
    let timestamp: Date
    let score: PhotoWorthinessScore
    let userAccepted: Bool
    let timeOfDay: TimeOfDay
}

private struct UserPhotoPreferences {
    var photoThreshold: Float = 0.6
    var preferredTimeOfDay: TimeOfDay = .goldenHour
    var preferredSubjects: [String] = []
}

public struct LearningStatistics {
    public var totalEvaluations: Int = 0
    public var photosAccepted: Int = 0
    public var photosRejected: Int = 0
    public var acceptanceRate: Float = 0
    public var lastUpdated: Date = Date()
}

// MARK: - Codable Extensions

extension PhotoWorthinessScore: Codable {}
extension UserPhotoPreferences: Codable {}

// MARK: - Enums

public enum TimeOfDay: String, Codable {
    case goldenHour, blueHour, midday, sunset, other
}

public enum PhotoTrend {
    case improving, declining, stable
}

public enum PhotoError: LocalizedError {
    case invalidImage
    case scoringFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image"
        case .scoringFailed: return "Photo scoring failed"
        }
    }
}
