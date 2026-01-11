import Foundation
import UIKit
import Vision
import CoreML

/// Advanced AI Vision Analysis Service combining Apple Vision + OpenAI Vision
@MainActor
class VisionAnalysisService: ObservableObject {
    // MARK: - Published Properties
    @Published var isAnalyzing = false
    @Published var analysisResult: VisionAnalysisResult?
    @Published var detectedObjects: [DetectedObject] = []
    @Published var sceneDescription: String = ""
    @Published var smartSuggestions: [String] = []

    // MARK: - Services
    private let openAI: OpenAIService
    private let visionQueue = DispatchQueue(label: "com.metaglasses.vision", qos: .userInitiated)

    // MARK: - Initialization
    init(openAIService: OpenAIService? = nil) {
        self.openAI = openAIService ?? OpenAIService()
        print("✅ Vision Analysis Service initialized")
    }

    // MARK: - Comprehensive Image Analysis
    func analyzeImage(_ image: UIImage, mode: AnalysisMode = .comprehensive) async throws -> VisionAnalysisResult {
        isAnalyzing = true
        defer { isAnalyzing = false }

        print("🔍 Starting \(mode) analysis...")

        var result = VisionAnalysisResult(originalImage: image)

        // Run analyses in parallel for better performance
        async let appleVisionResults = performAppleVisionAnalysis(image)
        async let openAIResults = performOpenAIAnalysis(image, mode: mode)

        let (visionData, aiDescription) = try await (appleVisionResults, openAIResults)

        result.appleVisionData = visionData
        result.aiDescription = aiDescription
        result.timestamp = Date()

        // Generate smart suggestions based on analysis
        result.suggestions = await generateSmartSuggestions(from: result)

        analysisResult = result
        sceneDescription = aiDescription

        print("✅ Analysis completed successfully")
        return result
    }

    // MARK: - Real-time Stream Analysis
    func analyzeVideoFrame(_ image: UIImage) async {
        // Lightweight analysis for real-time video
        guard !isAnalyzing else { return }

        do {
            let objects = try await detectObjectsQuick(image)
            await MainActor.run {
                self.detectedObjects = objects
            }
        } catch {
            print("❌ Video frame analysis error: \(error.localizedDescription)")
        }
    }

    // MARK: - Apple Vision Framework Analysis
    private func performAppleVisionAnalysis(_ image: UIImage) async throws -> AppleVisionData {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            var data = AppleVisionData()

            // Create multiple Vision requests
            let objectRequest = VNRecognizeAnimalsRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true

            let sceneRequest = VNClassifyImageRequest()
            let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            visionQueue.async {
                do {
                    // Perform all requests
                    try handler.perform([objectRequest, textRequest, sceneRequest, saliencyRequest])

                    // Process object detection
                    if let objects = objectRequest.results {
                        data.detectedObjects = objects.map { obs in
                            DetectedObject(
                                identifier: obs.labels.first?.identifier ?? "unknown",
                                confidence: obs.labels.first?.confidence ?? 0,
                                boundingBox: obs.boundingBox
                            )
                        }
                    }

                    // Process text recognition
                    if let texts = textRequest.results {
                        data.recognizedText = texts.compactMap { $0.topCandidates(1).first?.string }
                    }

                    // Process scene classification
                    if let scenes = sceneRequest.results?.prefix(5) {
                        data.sceneClassifications = scenes.map { obs in
                            SceneClassification(identifier: obs.identifier, confidence: obs.confidence)
                        }
                    }

                    // Process saliency (attention areas)
                    if let saliency = saliencyRequest.results?.first {
                        data.attentionAreas = self.extractAttentionAreas(from: saliency)
                    }

                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - OpenAI Vision Analysis
    private func performOpenAIAnalysis(_ image: UIImage, mode: AnalysisMode) async throws -> String {
        let prompt: String

        switch mode {
        case .comprehensive:
            prompt = """
            Analyze this image in detail and provide:
            1. Main subject and context
            2. Notable objects, people, or text
            3. Scene setting (indoor/outdoor, time of day, etc.)
            4. Actions or activities happening
            5. Emotional tone or atmosphere
            6. Any safety concerns or important details
            7. Suggestions for better capturing this scene
            """

        case .quick:
            prompt = "Briefly describe what you see in this image (2-3 sentences)."

        case .accessibility:
            prompt = """
            Describe this image for accessibility purposes:
            - What is the main focus?
            - Describe people, if any (appearance, actions, expressions)
            - Describe the environment and setting
            - List any text visible in the image
            - Note colors and lighting
            """

        case .technical:
            prompt = """
            Provide a technical analysis of this image:
            - Image composition and framing
            - Lighting quality and direction
            - Focus and depth of field
            - Color balance and saturation
            - Technical improvements that could be made
            """
        }

        return try await openAI.analyzeImage(image, prompt: prompt)
    }

    // MARK: - Quick Object Detection (for real-time)
    private func detectObjectsQuick(_ image: UIImage) async throws -> [DetectedObject] {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeAnimalsRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let objects = results.map { obs in
                    DetectedObject(
                        identifier: obs.labels.first?.identifier ?? "unknown",
                        confidence: obs.labels.first?.confidence ?? 0,
                        boundingBox: obs.boundingBox
                    )
                }

                continuation.resume(returning: objects)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage)
            visionQueue.async {
                try? handler.perform([request])
            }
        }
    }

    // MARK: - Smart Suggestions
    private func generateSmartSuggestions(from result: VisionAnalysisResult) async -> [String] {
        var suggestions: [String] = []

        // Analyze scene classifications
        if let topScene = result.appleVisionData?.sceneClassifications.first {
            if topScene.identifier.contains("outdoor") {
                suggestions.append("💡 Try HDR mode for better outdoor lighting")
            }
            if topScene.identifier.contains("portrait") {
                suggestions.append("👤 Portrait mode available for better depth effect")
            }
            if topScene.identifier.contains("low_light") || topScene.identifier.contains("night") {
                suggestions.append("🌙 Night mode recommended for low light conditions")
            }
        }

        // Analyze detected text
        if let texts = result.appleVisionData?.recognizedText, !texts.isEmpty {
            suggestions.append("📝 Text detected - tap to copy or translate")
        }

        // Analyze objects
        if let objects = result.appleVisionData?.detectedObjects {
            if objects.contains(where: { $0.identifier.contains("person") }) {
                suggestions.append("👥 Face recognition available")
            }
            if objects.count > 5 {
                suggestions.append("🎯 Multiple subjects - try different angles")
            }
        }

        return suggestions
    }

    // MARK: - Attention Areas Extraction
    private func extractAttentionAreas(from saliency: VNSaliencyImageObservation) -> [CGRect] {
        guard let salientObjects = saliency.salientObjects else {
            return []
        }
        return salientObjects.map { $0.boundingBox }
    }
}

// MARK: - Analysis Modes
enum AnalysisMode {
    case comprehensive  // Full AI + Vision analysis
    case quick         // Fast description only
    case accessibility // Optimized for screen readers
    case technical     // Photography/videography insights
}

// MARK: - Result Models
struct VisionAnalysisResult {
    var originalImage: UIImage
    var appleVisionData: AppleVisionData?
    var aiDescription: String = ""
    var suggestions: [String] = []
    var timestamp: Date = Date()

    var summary: String {
        var parts: [String] = []

        if let objects = appleVisionData?.detectedObjects, !objects.isEmpty {
            parts.append("\(objects.count) objects detected")
        }

        if let texts = appleVisionData?.recognizedText, !texts.isEmpty {
            parts.append("\(texts.count) text items")
        }

        if let scenes = appleVisionData?.sceneClassifications, !scenes.isEmpty {
            parts.append("Scene: \(scenes.first?.identifier ?? "unknown")")
        }

        return parts.isEmpty ? "No analysis data" : parts.joined(separator: " • ")
    }
}

struct AppleVisionData {
    var detectedObjects: [DetectedObject] = []
    var recognizedText: [String] = []
    var sceneClassifications: [SceneClassification] = []
    var attentionAreas: [CGRect] = []
}

struct DetectedObject: Identifiable {
    let id = UUID()
    let identifier: String
    let confidence: Float
    let boundingBox: CGRect

    var displayName: String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var confidencePercent: Int {
        Int(confidence * 100)
    }
}

struct SceneClassification: Identifiable {
    let id = UUID()
    let identifier: String
    let confidence: Float

    var displayName: String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Errors
enum VisionError: LocalizedError {
    case invalidImage
    case analysisFailure
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image format"
        case .analysisFailure: return "Vision analysis failed"
        case .noResults: return "No analysis results available"
        }
    }
}
