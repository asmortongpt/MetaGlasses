import Foundation
import UIKit
import Vision
import AVFoundation

/// Real-time Caption Generation System
/// Live photo captioning with multiple styles, accessibility features, and history
@MainActor
public class RealTimeCaptionGeneration: ObservableObject {

    // MARK: - Singleton
    public static let shared = RealTimeCaptionGeneration()

    // MARK: - Published Properties
    @Published public var currentCaption: Caption?
    @Published public var captionHistory: [Caption] = []
    @Published public var isGenerating = false
    @Published public var captionStyle: CaptionStyle = .descriptive
    @Published public var voiceOverEnabled = false

    // MARK: - Private Properties
    private let llmRouter = EnhancedLLMRouter.shared
    private let sceneUnderstanding = AdvancedSceneUnderstanding.shared
    private let ragMemory = ProductionRAGMemory.shared

    private var captionCache: [String: Caption] = [:]
    private let maxCacheSize = 100
    private let maxHistorySize = 500

    // Voice synthesis
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechQueue: [AVSpeechUtterance] = []

    // Performance tracking
    private var generationTimes: [TimeInterval] = []

    // MARK: - Initialization
    private init() {
        print("📝 RealTimeCaptionGeneration initialized")
        loadCaptionHistory()
        setupAccessibility()
    }

    // MARK: - Caption Generation

    /// Generate caption for image in real-time
    public func generateCaption(
        for image: UIImage,
        style: CaptionStyle? = nil,
        priority: CaptionPriority = .normal,
        includeContext: Bool = true
    ) async throws -> Caption {
        isGenerating = true
        defer { isGenerating = false }

        let startTime = Date()
        let selectedStyle = style ?? captionStyle

        // Check cache first
        let cacheKey = generateCacheKey(image: image, style: selectedStyle)
        if let cached = captionCache[cacheKey] {
            print("📝 Using cached caption")
            return cached
        }

        // Analyze scene
        let sceneAnalysis = try await sceneUnderstanding.analyzeScene(image: image)

        // Generate caption based on style
        let captionText = try await generateCaptionText(
            sceneAnalysis: sceneAnalysis,
            style: selectedStyle,
            includeContext: includeContext
        )

        // Create caption object
        let caption = Caption(
            id: UUID(),
            text: captionText,
            style: selectedStyle,
            timestamp: Date(),
            image: image,
            confidence: sceneAnalysis.classification.confidence,
            sceneAnalysis: sceneAnalysis,
            metadata: CaptionMetadata(
                objectCount: sceneAnalysis.objects.count,
                primarySubjects: sceneAnalysis.objects.prefix(3).map { $0.label },
                environment: sceneAnalysis.classification.environment.rawValue
            )
        )

        // Update state
        currentCaption = caption
        captionHistory.append(caption)
        if captionHistory.count > maxHistorySize {
            captionHistory.removeFirst(captionHistory.count - maxHistorySize)
        }

        // Cache caption
        cacheCaption(caption, key: cacheKey)

        // Store in RAG memory
        try await storeCaptionInMemory(caption)

        // Speak if VoiceOver enabled
        if voiceOverEnabled {
            await speakCaption(caption)
        }

        // Track performance
        let generationTime = Date().timeIntervalSince(startTime)
        generationTimes.append(generationTime)
        if generationTimes.count > 50 {
            generationTimes.removeFirst()
        }

        print("✅ Caption generated in \(String(format: "%.2f", generationTime))s")
        saveCaptionHistory()

        return caption
    }

    // MARK: - Caption Text Generation

    private func generateCaptionText(
        sceneAnalysis: SceneAnalysis,
        style: CaptionStyle,
        includeContext: Bool
    ) async throws -> String {
        switch style {
        case .descriptive:
            return try await generateDescriptiveCaption(sceneAnalysis: sceneAnalysis)

        case .creative:
            return try await generateCreativeCaption(sceneAnalysis: sceneAnalysis)

        case .technical:
            return try await generateTechnicalCaption(sceneAnalysis: sceneAnalysis)

        case .concise:
            return generateConciseCaption(sceneAnalysis: sceneAnalysis)

        case .storytelling:
            return try await generateStorytellingCaption(
                sceneAnalysis: sceneAnalysis,
                includeContext: includeContext
            )

        case .accessibility:
            return generateAccessibilityCaption(sceneAnalysis: sceneAnalysis)
        }
    }

    // MARK: - Style-Specific Generation

    private func generateDescriptiveCaption(sceneAnalysis: SceneAnalysis) async throws -> String {
        let prompt = """
        Generate a detailed, descriptive photo caption for this scene.
        Be factual and comprehensive.

        Scene: \(sceneAnalysis.semanticDescription)
        Objects detected: \(sceneAnalysis.objects.map { $0.label }.joined(separator: ", "))
        Environment: \(sceneAnalysis.classification.environment.rawValue)
        Activities: \(sceneAnalysis.context.activities.joined(separator: ", "))

        Caption (1-2 sentences):
        """

        let response = try await llmRouter.route(
            messages: [["role": "user", "content": prompt]],
            task: .creative,
            priority: .normal
        )

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateCreativeCaption(sceneAnalysis: SceneAnalysis) async throws -> String {
        let prompt = """
        Generate a creative, artistic photo caption that captures the mood and essence.
        Be poetic and evocative.

        Scene: \(sceneAnalysis.semanticDescription)
        Time of day: \(sceneAnalysis.context.timeOfDay)
        Social context: \(sceneAnalysis.context.socialContext)

        Creative caption (1 sentence):
        """

        let response = try await llmRouter.route(
            messages: [["role": "user", "content": prompt]],
            task: .creative,
            priority: .normal
        )

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateTechnicalCaption(sceneAnalysis: SceneAnalysis) async throws -> String {
        var technical = "Scene analysis: "

        technical += "\(sceneAnalysis.objects.count) objects detected ("
        technical += sceneAnalysis.objects.prefix(5).map { "\($0.label) @\(Int($0.confidence * 100))%" }.joined(separator: ", ")
        technical += "). "

        technical += "Environment: \(sceneAnalysis.classification.environment.rawValue). "

        if let saliency = sceneAnalysis.saliencyMap {
            technical += "\(saliency.salientObjects.count) salient regions. "
        }

        if !sceneAnalysis.relationships.isEmpty {
            technical += "\(sceneAnalysis.relationships.count) spatial relationships detected."
        }

        return technical
    }

    private func generateConciseCaption(sceneAnalysis: SceneAnalysis) -> String {
        // Ultra-concise, 3-5 words
        let topObjects = sceneAnalysis.objects.prefix(2).map { $0.label }

        if topObjects.isEmpty {
            return sceneAnalysis.classification.environment.rawValue.capitalized + " scene"
        }

        return topObjects.joined(separator: " and ") + " " + sceneAnalysis.classification.environment.rawValue
    }

    private func generateStorytellingCaption(
        sceneAnalysis: SceneAnalysis,
        includeContext: Bool
    ) async throws -> String {
        var contextInfo = ""

        if includeContext {
            // Retrieve related memories
            let relatedMemories = try await ragMemory.retrieveRelevant(
                query: sceneAnalysis.semanticDescription,
                limit: 3,
                threshold: 0.6
            )

            if !relatedMemories.isEmpty {
                contextInfo = "\nRelated memories: " + relatedMemories.map { $0.memory.text }.joined(separator: "; ")
            }
        }

        let prompt = """
        Generate a storytelling caption that weaves this moment into a narrative.
        Make it personal and engaging.

        Current scene: \(sceneAnalysis.semanticDescription)
        Time: \(sceneAnalysis.context.timeOfDay)
        \(contextInfo)

        Storytelling caption (1-2 sentences):
        """

        let response = try await llmRouter.route(
            messages: [["role": "user", "content": prompt]],
            task: .creative,
            priority: .normal
        )

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateAccessibilityCaption(sceneAnalysis: SceneAnalysis) -> String {
        // Optimized for screen readers
        var caption = "Image shows: "

        // Primary subjects first
        let subjects = sceneAnalysis.objects.prefix(3)
        if !subjects.isEmpty {
            caption += subjects.map { $0.label }.joined(separator: ", ") + ". "
        }

        // Environment
        caption += "Environment: \(sceneAnalysis.classification.environment.rawValue). "

        // Activities
        if !sceneAnalysis.context.activities.isEmpty {
            caption += "Activities: \(sceneAnalysis.context.activities.joined(separator: ", ")). "
        }

        // Social context
        caption += "Social context: \(sceneAnalysis.context.socialContext)."

        return caption
    }

    // MARK: - Batch Processing

    /// Generate captions for multiple images
    public func generateBatchCaptions(
        images: [UIImage],
        style: CaptionStyle,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        var captions: [Caption] = []

        for (index, image) in images.enumerated() {
            let caption = try await generateCaption(for: image, style: style)
            captions.append(caption)

            progressHandler?(index + 1, images.count)
        }

        return captions
    }

    // MARK: - Caption Search

    /// Search caption history
    public func searchCaptions(
        query: String,
        style: CaptionStyle? = nil,
        limit: Int = 20
    ) async throws -> [Caption] {
        // Generate query embedding
        let queryEmbedding = try await ragMemory.generateEmbedding(for: query)

        var results: [(Caption, Float)] = []

        for caption in captionHistory {
            // Filter by style if specified
            if let style = style, caption.style != style {
                continue
            }

            // Calculate similarity
            let captionEmbedding = try await ragMemory.generateEmbedding(for: caption.text)
            let similarity = cosineSimilarity(queryEmbedding, captionEmbedding)

            if similarity > 0.5 {
                results.append((caption, similarity))
            }
        }

        // Sort by similarity
        results.sort { $0.1 > $1.1 }

        return Array(results.prefix(limit).map { $0.0 })
    }

    // MARK: - Caption Editing

    /// Regenerate caption with different style
    public func regenerateCaption(
        _ caption: Caption,
        withStyle style: CaptionStyle
    ) async throws -> Caption {
        guard let image = caption.image else {
            throw CaptionError.imageNotAvailable
        }

        return try await generateCaption(for: image, style: style, includeContext: true)
    }

    /// Refine caption with user feedback
    public func refineCaption(
        _ caption: Caption,
        userFeedback: String
    ) async throws -> Caption {
        let prompt = """
        Refine this photo caption based on user feedback.

        Original caption: \(caption.text)
        User feedback: \(userFeedback)

        Refined caption:
        """

        let response = try await llmRouter.route(
            messages: [["role": "user", "content": prompt]],
            task: .creative,
            priority: .normal
        )

        var refined = caption
        refined.text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        refined.timestamp = Date()

        return refined
    }

    // MARK: - Accessibility Features

    private func setupAccessibility() {
        // Monitor VoiceOver status
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.voiceOverEnabled = UIAccessibility.isVoiceOverRunning
        }

        voiceOverEnabled = UIAccessibility.isVoiceOverRunning
    }

    private func speakCaption(_ caption: Caption) async {
        let utterance = AVSpeechUtterance(string: caption.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        speechSynthesizer.speak(utterance)
        print("🔊 Speaking caption via VoiceOver")
    }

    /// Speak caption on demand
    public func speakCaptionAloud(_ caption: Caption) async {
        await speakCaption(caption)
    }

    // MARK: - Caption Analytics

    /// Get caption statistics
    public func getCaptionStatistics() -> CaptionStatistics {
        let avgGenerationTime = generationTimes.isEmpty ? 0 : generationTimes.reduce(0, +) / Double(generationTimes.count)

        var styleDistribution: [CaptionStyle: Int] = [:]
        for caption in captionHistory {
            styleDistribution[caption.style, default: 0] += 1
        }

        return CaptionStatistics(
            totalCaptions: captionHistory.count,
            averageGenerationTime: avgGenerationTime,
            styleDistribution: styleDistribution,
            cacheHitRate: calculateCacheHitRate()
        )
    }

    private func calculateCacheHitRate() -> Double {
        // Simplified - would track actual cache hits in production
        return 0.25
    }

    // MARK: - Caching

    private func generateCacheKey(image: UIImage, style: CaptionStyle) -> String {
        // Use image hash + style
        let imageHash = image.hashValue
        return "\(imageHash)_\(style.rawValue)"
    }

    private func cacheCaption(_ caption: Caption, key: String) {
        captionCache[key] = caption

        if captionCache.count > maxCacheSize {
            // Remove oldest
            let oldestKey = captionCache.keys.first
            captionCache.removeValue(forKey: oldestKey!)
        }
    }

    // MARK: - Memory Integration

    private func storeCaptionInMemory(_ caption: Caption) async throws {
        let memoryText = """
        Photo caption (\(caption.style.rawValue)): \(caption.text)
        Objects: \(caption.metadata.primarySubjects.joined(separator: ", "))
        Environment: \(caption.metadata.environment)
        """

        let context = MemoryContext(
            timestamp: caption.timestamp,
            activity: "photo_captioning",
            tags: [caption.style.rawValue] + caption.metadata.primarySubjects
        )

        _ = try await ragMemory.storeMemory(
            text: memoryText,
            type: .observation,
            context: context
        )
    }

    // MARK: - Persistence

    private var historyFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("caption_history.json")
    }

    private func saveCaptionHistory() {
        // Save without images to reduce size
        let lightweightHistory = captionHistory.map { caption in
            var light = caption
            light.image = nil
            return light
        }

        if let data = try? JSONEncoder().encode(lightweightHistory) {
            try? data.write(to: historyFileURL)
        }
    }

    private func loadCaptionHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let loaded = try? JSONDecoder().decode([Caption].self, from: data) else {
            return
        }

        captionHistory = loaded
        print("📚 Loaded \(captionHistory.count) caption history entries")
    }

    // MARK: - Utilities

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map { $0.0 * $0.1 }.reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Export

    /// Export captions to text file
    public func exportCaptions(captions: [Caption]) -> String {
        var export = "Photo Captions Export\n"
        export += "Generated: \(Date())\n"
        export += String(repeating: "=", count: 50) + "\n\n"

        for (index, caption) in captions.enumerated() {
            export += "[\(index + 1)] \(caption.timestamp)\n"
            export += "Style: \(caption.style.rawValue)\n"
            export += "Caption: \(caption.text)\n"
            export += "Objects: \(caption.metadata.primarySubjects.joined(separator: ", "))\n"
            export += "\n"
        }

        return export
    }
}

// MARK: - Supporting Types

public struct Caption: Codable, Identifiable {
    public let id: UUID
    public var text: String
    public let style: CaptionStyle
    public let timestamp: Date
    public var image: UIImage?
    public let confidence: Float
    public let sceneAnalysis: SceneAnalysis?
    public let metadata: CaptionMetadata

    enum CodingKeys: String, CodingKey {
        case id, text, style, timestamp, confidence, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        style = try container.decode(CaptionStyle.self, forKey: .style)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        confidence = try container.decode(Float.self, forKey: .confidence)
        metadata = try container.decode(CaptionMetadata.self, forKey: .metadata)
        image = nil
        sceneAnalysis = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(style, forKey: .style)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(metadata, forKey: .metadata)
    }

    public init(id: UUID, text: String, style: CaptionStyle, timestamp: Date, image: UIImage?, confidence: Float, sceneAnalysis: SceneAnalysis?, metadata: CaptionMetadata) {
        self.id = id
        self.text = text
        self.style = style
        self.timestamp = timestamp
        self.image = image
        self.confidence = confidence
        self.sceneAnalysis = sceneAnalysis
        self.metadata = metadata
    }
}

public struct CaptionMetadata: Codable {
    public let objectCount: Int
    public let primarySubjects: [String]
    public let environment: String
}

public struct CaptionStatistics {
    public let totalCaptions: Int
    public let averageGenerationTime: TimeInterval
    public let styleDistribution: [CaptionStyle: Int]
    public let cacheHitRate: Double
}

// MARK: - Enums

public enum CaptionStyle: String, Codable, CaseIterable {
    case descriptive = "Descriptive"
    case creative = "Creative"
    case technical = "Technical"
    case concise = "Concise"
    case storytelling = "Storytelling"
    case accessibility = "Accessibility"
}

public enum CaptionPriority {
    case low, normal, high
}

public enum CaptionError: LocalizedError {
    case imageNotAvailable
    case generationFailed

    public var errorDescription: String? {
        switch self {
        case .imageNotAvailable: return "Image not available"
        case .generationFailed: return "Caption generation failed"
        }
    }
}
