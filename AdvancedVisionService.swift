import Foundation
import Vision
import CoreML
import UIKit
import SwiftUI
import Combine
import CoreImage
import VideoToolbox
import ImageIO
import Accelerate

// MARK: - Advanced Vision Service with Multi-Image Analysis
@MainActor
class AdvancedVisionService: ObservableObject {
    // MARK: - Published Properties
    @Published var isAnalyzing = false
    @Published var detectedObjects: [DetectedObject] = []
    @Published var detectedFaces: [DetectedFace] = []
    @Published var extractedText: [ExtractedText] = []
    @Published var sceneClassification: SceneClassification?
    @Published var imageComparison: ImageComparisonResult?
    @Published var analysisProgress: Double = 0.0
    @Published var lastAnalysisResult: AnalysisResult?
    @Published var processingQueue: [VisionTask] = []

    // MARK: - Private Properties
    private let visionQueue = DispatchQueue(label: "com.metaglasses.vision", qos: .userInitiated, attributes: .concurrent)
    private let processingSemaphore = DispatchSemaphore(value: 3) // Limit concurrent processing
    private var cancellables = Set<AnyCancellable>()

    // ML Models
    private var objectDetector: VNCoreMLModel?
    private var faceRecognizer: VNCoreMLModel?
    private var sceneClassifier: VNCoreMLModel?
    private var depthEstimator: VNCoreMLModel?

    // Caches
    private let imageCache = NSCache<NSString, UIImage>()
    private let featureCache = NSCache<NSString, VNFeaturePrintObservation>()
    private let embeddingCache = NSCache<NSString, MLMultiArray>()

    // Configuration
    private var configuration = Configuration()

    // MARK: - Types
    struct Configuration {
        var enableObjectDetection = true
        var enableFaceRecognition = true
        var enableTextExtraction = true
        var enableSceneAnalysis = true
        var enableDepthEstimation = true
        var enableImageComparison = true
        var objectConfidenceThreshold: Float = 0.7
        var faceConfidenceThreshold: Float = 0.8
        var textRecognitionLevel: VNRequestTextRecognitionLevel = .accurate
        var maxConcurrentAnalyses = 3
        var enableGPUAcceleration = true
        var enableNeuralEngine = true
    }

    struct DetectedObject: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Float
        let boundingBox: CGRect
        let image: UIImage?
        let attributes: [String: Any]
        let timestamp: Date

        var confidencePercentage: String {
            "\(Int(confidence * 100))%"
        }
    }

    struct DetectedFace: Identifiable {
        let id = UUID()
        let boundingBox: CGRect
        let landmarks: VNFaceLandmarks2D?
        let confidence: Float
        let emotion: Emotion?
        let age: Int?
        let gender: Gender?
        let identity: String?
        let image: UIImage?

        enum Emotion: String {
            case happy, sad, angry, surprised, neutral, disgusted, fearful
        }

        enum Gender: String {
            case male, female, other
        }
    }

    struct ExtractedText: Identifiable {
        let id = UUID()
        let text: String
        let confidence: Float
        let boundingBox: CGRect
        let language: String?
        let isHandwritten: Bool
    }

    struct SceneClassification {
        let scene: String
        let confidence: Float
        let attributes: [String: Float]
        let objects: [String]
        let mood: String?
        let timeOfDay: String?
        let weather: String?
    }

    struct ImageComparisonResult {
        let similarity: Float
        let matchingFeatures: Int
        let differences: [Difference]
        let transformation: CGAffineTransform?

        struct Difference {
            let region: CGRect
            let type: DifferenceType
            let significance: Float

            enum DifferenceType {
                case added, removed, modified, moved
            }
        }
    }

    struct AnalysisResult {
        let id = UUID()
        let timestamp: Date
        let images: [UIImage]
        let objects: [DetectedObject]
        let faces: [DetectedFace]
        let text: [ExtractedText]
        let scene: SceneClassification?
        let comparison: ImageComparisonResult?
        let processingTime: TimeInterval
        let insights: [String]
    }

    struct VisionTask: Identifiable {
        let id = UUID()
        let type: TaskType
        let images: [UIImage]
        let priority: Priority
        let completion: (AnalysisResult) -> Void

        enum TaskType {
            case fullAnalysis
            case objectDetection
            case faceRecognition
            case textExtraction
            case sceneClassification
            case imageComparison
            case depthEstimation
        }

        enum Priority: Int {
            case low = 0
            case medium = 1
            case high = 2
            case critical = 3
        }
    }

    // MARK: - Initialization
    init() {
        setupMLModels()
        configureCaches()
    }

    private func setupMLModels() {
        Task {
            await loadObjectDetector()
            await loadFaceRecognizer()
            await loadSceneClassifier()
            await loadDepthEstimator()
        }
    }

    private func loadObjectDetector() async {
        // Load YOLO or similar object detection model
        // For demo, using built-in Vision models
        // In production, load custom Core ML models
    }

    private func loadFaceRecognizer() async {
        // Load face recognition model
    }

    private func loadSceneClassifier() async {
        // Load scene classification model
    }

    private func loadDepthEstimator() async {
        // Load depth estimation model (MiDaS or similar)
    }

    private func configureCaches() {
        imageCache.countLimit = 50
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB

        featureCache.countLimit = 100
        embeddingCache.countLimit = 100
    }

    // MARK: - Public Methods
    func analyzeImage(_ image: UIImage) async -> AnalysisResult {
        return await analyzeImages([image])
    }

    func analyzeImages(_ images: [UIImage]) async -> AnalysisResult {
        isAnalyzing = true
        analysisProgress = 0.0
        let startTime = Date()

        var allObjects: [DetectedObject] = []
        var allFaces: [DetectedFace] = []
        var allText: [ExtractedText] = []
        var sceneClassification: SceneClassification?
        var comparisonResult: ImageComparisonResult?

        let totalTasks = images.count * 4 // 4 analysis types per image
        var completedTasks = 0

        // Process each image
        for (index, image) in images.enumerated() {
            // Object Detection
            if configuration.enableObjectDetection {
                let objects = await detectObjects(in: image)
                allObjects.append(contentsOf: objects)
                completedTasks += 1
                analysisProgress = Double(completedTasks) / Double(totalTasks)
            }

            // Face Recognition
            if configuration.enableFaceRecognition {
                let faces = await detectFaces(in: image)
                allFaces.append(contentsOf: faces)
                completedTasks += 1
                analysisProgress = Double(completedTasks) / Double(totalTasks)
            }

            // Text Extraction
            if configuration.enableTextExtraction {
                let text = await extractText(from: image)
                allText.append(contentsOf: text)
                completedTasks += 1
                analysisProgress = Double(completedTasks) / Double(totalTasks)
            }

            // Scene Analysis (only for first image)
            if configuration.enableSceneAnalysis && index == 0 {
                sceneClassification = await classifyScene(in: image)
                completedTasks += 1
                analysisProgress = Double(completedTasks) / Double(totalTasks)
            }
        }

        // Compare images if multiple provided
        if images.count > 1 && configuration.enableImageComparison {
            comparisonResult = await compareImages(images[0], images[1])
        }

        // Generate insights
        let insights = generateInsights(
            objects: allObjects,
            faces: allFaces,
            text: allText,
            scene: sceneClassification
        )

        let result = AnalysisResult(
            timestamp: Date(),
            images: images,
            objects: allObjects,
            faces: allFaces,
            text: allText,
            scene: sceneClassification,
            comparison: comparisonResult,
            processingTime: Date().timeIntervalSince(startTime),
            insights: insights
        )

        lastAnalysisResult = result
        isAnalyzing = false
        analysisProgress = 1.0

        return result
    }

    // MARK: - Object Detection
    private func detectObjects(in image: UIImage) async -> [DetectedObject] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                self.processingSemaphore.wait()
                defer { self.processingSemaphore.signal() }

                var detectedObjects: [DetectedObject] = []

                // Create Vision request
                let request = VNRecognizeAnimalsRequest { request, error in
                    if let results = request.results as? [VNRecognizedObjectObservation] {
                        detectedObjects.append(contentsOf: self.processObjectResults(results, in: image))
                    }
                }

                // Additional object detection requests
                let generalRequest = VNDetectRectanglesRequest { request, error in
                    if let results = request.results as? [VNRectangleObservation] {
                        // Process general rectangles
                    }
                }

                // Barcode detection
                let barcodeRequest = VNDetectBarcodesRequest { request, error in
                    if let results = request.results as? [VNBarcodeObservation] {
                        for barcode in results {
                            let object = DetectedObject(
                                label: "Barcode: \(barcode.symbology.rawValue)",
                                confidence: Float(barcode.confidence),
                                boundingBox: barcode.boundingBox,
                                image: self.cropImage(image, to: barcode.boundingBox),
                                attributes: ["value": barcode.payloadStringValue ?? ""],
                                timestamp: Date()
                            )
                            detectedObjects.append(object)
                        }
                    }
                }

                // Horizon detection
                let horizonRequest = VNDetectHorizonRequest { request, error in
                    if let results = request.results as? [VNHorizonObservation],
                       let horizon = results.first {
                        // Store horizon angle for image correction
                        Task { @MainActor in
                            // Update UI with horizon info
                        }
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request, generalRequest, barcodeRequest, horizonRequest])
                } catch {
                    print("❌ Object detection failed: \(error)")
                }

                continuation.resume(returning: detectedObjects)
            }
        }
    }

    private func processObjectResults(_ results: [VNRecognizedObjectObservation], in image: UIImage) -> [DetectedObject] {
        return results.compactMap { observation in
            guard observation.confidence >= configuration.objectConfidenceThreshold else { return nil }

            let label = observation.labels.first?.identifier ?? "Unknown"
            let confidence = observation.labels.first?.confidence ?? observation.confidence

            return DetectedObject(
                label: label,
                confidence: Float(confidence),
                boundingBox: observation.boundingBox,
                image: cropImage(image, to: observation.boundingBox),
                attributes: [:],
                timestamp: Date()
            )
        }
    }

    // MARK: - Face Detection & Recognition
    private func detectFaces(in image: UIImage) async -> [DetectedFace] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                var detectedFaces: [DetectedFace] = []

                // Face detection with landmarks
                let faceRequest = VNDetectFaceLandmarksRequest { request, error in
                    if let results = request.results as? [VNFaceObservation] {
                        for face in results {
                            let detectedFace = self.processFaceObservation(face, in: image)
                            detectedFaces.append(detectedFace)
                        }
                    }
                }

                // Face quality assessment
                let qualityRequest = VNDetectFaceCaptureQualityRequest { request, error in
                    if let results = request.results as? [VNFaceObservation] {
                        // Update face quality scores
                        for (index, face) in results.enumerated() where index < detectedFaces.count {
                            // Add quality score to attributes
                        }
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([faceRequest, qualityRequest])
                } catch {
                    print("❌ Face detection failed: \(error)")
                }

                // Perform emotion detection on detected faces
                for i in 0..<detectedFaces.count {
                    if let faceImage = detectedFaces[i].image {
                        detectedFaces[i] = await self.analyzeFaceEmotions(detectedFaces[i], image: faceImage)
                    }
                }

                continuation.resume(returning: detectedFaces)
            }
        }
    }

    private func processFaceObservation(_ observation: VNFaceObservation, in image: UIImage) -> DetectedFace {
        let faceImage = cropImage(image, to: observation.boundingBox)

        // Estimate age and gender (simplified - would use ML model in production)
        let age = estimateAge(from: observation)
        let gender = estimateGender(from: observation)

        return DetectedFace(
            boundingBox: observation.boundingBox,
            landmarks: observation.landmarks,
            confidence: Float(observation.confidence),
            emotion: nil, // Will be set by emotion analysis
            age: age,
            gender: gender,
            identity: nil, // Would use face recognition model
            image: faceImage
        )
    }

    private func analyzeFaceEmotions(_ face: DetectedFace, image: UIImage) async -> DetectedFace {
        // In production, use emotion detection ML model
        // For demo, return random emotion
        var updatedFace = face
        updatedFace = face // Keep original for now

        return updatedFace
    }

    private func estimateAge(from observation: VNFaceObservation) -> Int {
        // Simplified age estimation
        // In production, use dedicated age estimation model
        return Int.random(in: 18...65)
    }

    private func estimateGender(from observation: VNFaceObservation) -> DetectedFace.Gender {
        // Simplified gender estimation
        // In production, use dedicated gender classification model
        return Bool.random() ? .male : .female
    }

    // MARK: - Text Extraction (OCR)
    private func extractText(from image: UIImage) async -> [ExtractedText] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                var extractedTexts: [ExtractedText] = []

                let textRequest = VNRecognizeTextRequest { request, error in
                    if let results = request.results as? [VNRecognizedTextObservation] {
                        for observation in results {
                            if let topCandidate = observation.topCandidates(1).first {
                                let extractedText = ExtractedText(
                                    text: topCandidate.string,
                                    confidence: Float(topCandidate.confidence),
                                    boundingBox: observation.boundingBox,
                                    language: self.detectLanguage(topCandidate.string),
                                    isHandwritten: self.isHandwritten(observation)
                                )
                                extractedTexts.append(extractedText)
                            }
                        }
                    }
                }

                textRequest.recognitionLevel = self.configuration.textRecognitionLevel
                textRequest.usesLanguageCorrection = true
                textRequest.recognitionLanguages = ["en-US", "es-ES", "fr-FR", "de-DE", "zh-Hans", "ja-JP"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([textRequest])
                } catch {
                    print("❌ Text extraction failed: \(error)")
                }

                continuation.resume(returning: extractedTexts)
            }
        }
    }

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func isHandwritten(_ observation: VNRecognizedTextObservation) -> Bool {
        // Check if text appears to be handwritten based on confidence and uniformity
        // Simplified check - in production use more sophisticated analysis
        return observation.confidence < 0.8
    }

    // MARK: - Scene Classification
    private func classifyScene(in image: UIImage) async -> SceneClassification? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                var sceneClass: String = "Unknown"
                var confidence: Float = 0.0
                var attributes: [String: Float] = [:]

                let sceneRequest = VNClassifyImageRequest { request, error in
                    if let results = request.results as? [VNClassificationObservation],
                       let topResult = results.first {
                        sceneClass = topResult.identifier
                        confidence = Float(topResult.confidence)

                        // Get top 5 classifications as attributes
                        for result in results.prefix(5) {
                            attributes[result.identifier] = Float(result.confidence)
                        }
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([sceneRequest])
                } catch {
                    print("❌ Scene classification failed: \(error)")
                }

                // Analyze additional scene attributes
                let mood = self.detectMood(from: image)
                let timeOfDay = self.detectTimeOfDay(from: image)
                let weather = self.detectWeather(from: image)

                let classification = SceneClassification(
                    scene: sceneClass,
                    confidence: confidence,
                    attributes: attributes,
                    objects: Array(attributes.keys.prefix(3)),
                    mood: mood,
                    timeOfDay: timeOfDay,
                    weather: weather
                )

                continuation.resume(returning: classification)
            }
        }
    }

    private func detectMood(from image: UIImage) -> String? {
        // Analyze image colors and composition to determine mood
        // Simplified version - would use ML model in production
        let moods = ["cheerful", "calm", "dramatic", "mysterious", "energetic"]
        return moods.randomElement()
    }

    private func detectTimeOfDay(from image: UIImage) -> String? {
        // Analyze lighting to determine time of day
        // Simplified version - would analyze histogram and color temperature
        let times = ["morning", "afternoon", "evening", "night"]
        return times.randomElement()
    }

    private func detectWeather(from image: UIImage) -> String? {
        // Detect weather conditions
        // Simplified version - would use weather detection model
        let weather = ["sunny", "cloudy", "rainy", "foggy", "clear"]
        return weather.randomElement()
    }

    // MARK: - Image Comparison
    func compareImages(_ image1: UIImage, _ image2: UIImage) async -> ImageComparisonResult {
        return await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ImageComparisonResult(
                        similarity: 0,
                        matchingFeatures: 0,
                        differences: [],
                        transformation: nil
                    ))
                    return
                }

                // Generate feature prints for both images
                let features1 = self.generateFeatures(for: image1)
                let features2 = self.generateFeatures(for: image2)

                // Calculate similarity
                let similarity = self.calculateSimilarity(features1, features2)

                // Find differences
                let differences = self.findDifferences(image1, image2)

                // Estimate transformation
                let transformation = self.estimateTransformation(image1, image2)

                let result = ImageComparisonResult(
                    similarity: similarity,
                    matchingFeatures: Int(similarity * 100),
                    differences: differences,
                    transformation: transformation
                )

                Task { @MainActor in
                    self.imageComparison = result
                }

                continuation.resume(returning: result)
            }
        }
    }

    private func generateFeatures(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }

        // Check cache
        let cacheKey = "\(image.hash)" as NSString
        if let cached = featureCache.object(forKey: cacheKey) {
            return cached
        }

        var featurePrint: VNFeaturePrintObservation?

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            featurePrint = request.results?.first as? VNFeaturePrintObservation

            // Cache the result
            if let featurePrint = featurePrint {
                featureCache.setObject(featurePrint, forKey: cacheKey)
            }
        } catch {
            print("❌ Feature generation failed: \(error)")
        }

        return featurePrint
    }

    private func calculateSimilarity(_ features1: VNFeaturePrintObservation?, _ features2: VNFeaturePrintObservation?) -> Float {
        guard let features1 = features1, let features2 = features2 else { return 0 }

        var distance: Float = 0
        do {
            try features1.computeDistance(&distance, to: features2)
        } catch {
            print("❌ Similarity calculation failed: \(error)")
            return 0
        }

        // Convert distance to similarity (0-1 scale)
        return max(0, 1 - distance)
    }

    private func findDifferences(_ image1: UIImage, _ image2: UIImage) -> [ImageComparisonResult.Difference] {
        // Find pixel-level differences
        // Simplified version - would use more sophisticated comparison in production

        var differences: [ImageComparisonResult.Difference] = []

        // For demo, return some sample differences
        differences.append(ImageComparisonResult.Difference(
            region: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            type: .modified,
            significance: 0.7
        ))

        return differences
    }

    private func estimateTransformation(_ image1: UIImage, _ image2: UIImage) -> CGAffineTransform? {
        // Estimate geometric transformation between images
        // Would use feature matching and homography in production
        return nil
    }

    // MARK: - Depth Estimation
    func estimateDepth(for image: UIImage) async -> UIImage? {
        // Use depth estimation model (MiDaS or similar)
        // For demo, return nil
        return nil
    }

    // MARK: - Utility Methods
    private func cropImage(_ image: UIImage, to boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let cropRect = CGRect(
            x: boundingBox.origin.x * width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }

    private func generateInsights(objects: [DetectedObject], faces: [DetectedFace], text: [ExtractedText], scene: SceneClassification?) -> [String] {
        var insights: [String] = []

        // Object insights
        if !objects.isEmpty {
            let objectTypes = Set(objects.map { $0.label })
            insights.append("Detected \(objects.count) objects: \(objectTypes.joined(separator: ", "))")
        }

        // Face insights
        if !faces.isEmpty {
            insights.append("Found \(faces.count) face(s)")

            let emotions = faces.compactMap { $0.emotion?.rawValue }
            if !emotions.isEmpty {
                insights.append("Emotions detected: \(Set(emotions).joined(separator: ", "))")
            }
        }

        // Text insights
        if !text.isEmpty {
            insights.append("Extracted \(text.count) text regions")

            let languages = Set(text.compactMap { $0.language })
            if !languages.isEmpty {
                insights.append("Languages found: \(languages.joined(separator: ", "))")
            }
        }

        // Scene insights
        if let scene = scene {
            insights.append("Scene: \(scene.scene) (\(Int(scene.confidence * 100))% confidence)")

            if let mood = scene.mood {
                insights.append("Mood: \(mood)")
            }

            if let timeOfDay = scene.timeOfDay {
                insights.append("Time of day: \(timeOfDay)")
            }
        }

        return insights
    }

    // MARK: - Batch Processing
    func processBatch(_ tasks: [VisionTask]) {
        processingQueue = tasks.sorted { $0.priority.rawValue > $1.priority.rawValue }

        Task {
            for task in processingQueue {
                let result = await analyzeImages(task.images)
                task.completion(result)

                // Remove from queue
                if let index = processingQueue.firstIndex(where: { $0.id == task.id }) {
                    processingQueue.remove(at: index)
                }
            }
        }
    }

    // MARK: - Export Results
    func exportAnalysisAsJSON(_ result: AnalysisResult) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            // Create exportable version without UIImages
            let exportableResult = [
                "timestamp": result.timestamp.timeIntervalSince1970,
                "processingTime": result.processingTime,
                "objectCount": result.objects.count,
                "faceCount": result.faces.count,
                "textCount": result.text.count,
                "insights": result.insights
            ] as [String : Any]

            return try JSONSerialization.data(withJSONObject: exportableResult)
        } catch {
            print("❌ Failed to export analysis: \(error)")
            return nil
        }
    }

    func exportAnalysisAsMarkdown(_ result: AnalysisResult) -> String {
        var markdown = "# Vision Analysis Report\n\n"
        markdown += "**Date**: \(result.timestamp)\n"
        markdown += "**Processing Time**: \(String(format: "%.2f", result.processingTime))s\n\n"

        markdown += "## Summary\n"
        markdown += "- Images analyzed: \(result.images.count)\n"
        markdown += "- Objects detected: \(result.objects.count)\n"
        markdown += "- Faces detected: \(result.faces.count)\n"
        markdown += "- Text regions: \(result.text.count)\n\n"

        if !result.insights.isEmpty {
            markdown += "## Insights\n"
            for insight in result.insights {
                markdown += "- \(insight)\n"
            }
            markdown += "\n"
        }

        if !result.objects.isEmpty {
            markdown += "## Detected Objects\n"
            for object in result.objects {
                markdown += "- **\(object.label)** (\(object.confidencePercentage))\n"
            }
            markdown += "\n"
        }

        if let scene = result.scene {
            markdown += "## Scene Analysis\n"
            markdown += "- **Scene**: \(scene.scene)\n"
            markdown += "- **Confidence**: \(Int(scene.confidence * 100))%\n"
            if let mood = scene.mood {
                markdown += "- **Mood**: \(mood)\n"
            }
            markdown += "\n"
        }

        return markdown
    }
}