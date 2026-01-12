import Foundation
import Vision
import CoreML
import UIKit
import CoreLocation

/// Advanced Scene Understanding System
/// Multi-object detection, tracking, relationships, and temporal analysis
@MainActor
public class AdvancedSceneUnderstanding: ObservableObject {

    // MARK: - Singleton
    public static let shared = AdvancedSceneUnderstanding()

    // MARK: - Published Properties
    @Published public var currentScene: SceneAnalysis?
    @Published public var sceneHistory: [SceneAnalysis] = []
    @Published public var isAnalyzing = false

    // MARK: - Private Properties
    private let queue = DispatchQueue(label: "com.metaglasses.scene", qos: .userInitiated)
    private var objectTracker: [UUID: TrackedSceneObject] = [:]
    private var sceneMemory: [SceneSnapshot] = []
    private let maxSceneHistory = 100
    private let maxMemorySnapshots = 50

    // Integration with RAG and LLM
    private let ragMemory = ProductionRAGMemory.shared
    private let llmOrchestrator = LLMOrchestrator()

    // MARK: - Initialization
    private init() {
        print("🎬 AdvancedSceneUnderstanding initialized")
    }

    // MARK: - Scene Analysis

    /// Comprehensive scene analysis with multi-object detection and relationships
    public func analyzeScene(
        image: UIImage,
        location: CLLocation? = nil,
        previousScene: SceneAnalysis? = nil
    ) async throws -> SceneAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let cgImage = image.cgImage else {
            throw SceneError.invalidImage
        }

        print("🔍 Analyzing scene comprehensively...")

        // Parallel detection tasks
        async let objects = detectAllObjects(cgImage: cgImage)
        async let classification = classifyScene(cgImage: cgImage)
        async let saliency = detectSaliency(cgImage: cgImage)
        async let depth = estimateDepth(cgImage: cgImage)

        // Wait for all detections
        let detectedObjects = try await objects
        let sceneClass = await classification
        let saliencyMap = await saliency
        let depthMap = await depth

        // Analyze relationships
        let relationships = analyzeObjectRelationships(objects: detectedObjects)

        // Determine scene context
        let context = determineSceneContext(
            classification: sceneClass,
            objects: detectedObjects,
            location: location
        )

        // Track objects if we have previous scene
        var temporalChanges: TemporalChanges?
        if let previous = previousScene {
            temporalChanges = analyzeTemporalChanges(
                previous: previous,
                current: detectedObjects
            )
        }

        // Generate semantic description
        let description = await generateSemanticDescription(
            objects: detectedObjects,
            relationships: relationships,
            context: context
        )

        // Create scene analysis
        let scene = SceneAnalysis(
            id: UUID(),
            timestamp: Date(),
            image: image,
            objects: detectedObjects,
            classification: sceneClass,
            relationships: relationships,
            context: context,
            saliencyMap: saliencyMap,
            depthMap: depthMap,
            temporalChanges: temporalChanges,
            semanticDescription: description,
            location: location
        )

        // Update state
        currentScene = scene
        sceneHistory.append(scene)
        if sceneHistory.count > maxSceneHistory {
            sceneHistory.removeFirst(sceneHistory.count - maxSceneHistory)
        }

        // Store in RAG memory
        try await storeSceneInMemory(scene)

        // Create snapshot for temporal tracking
        createSceneSnapshot(scene)

        print("✅ Scene analysis complete: \(description)")
        return scene
    }

    // MARK: - Object Detection

    private func detectAllObjects(cgImage: CGImage) async throws -> [SceneObject] {
        return try await withCheckedThrowingContinuation { continuation in
            var allObjects: [SceneObject] = []

            // Multiple detection requests for comprehensive coverage
            let requests: [VNRequest] = [
                VNRecognizeAnimalsRequest(),
                VNDetectHumanRectanglesRequest(),
                VNDetectFaceRectanglesRequest(),
                VNDetectBarcodesRequest(),
                VNRecognizeTextRequest()
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform(requests)

                    // Process animals
                    if let animalRequest = requests[0] as? VNRecognizeAnimalsRequest,
                       let animals = animalRequest.results {
                        for animal in animals {
                            allObjects.append(SceneObject(
                                id: UUID(),
                                label: animal.labels.first?.identifier ?? "Animal",
                                category: .animal,
                                confidence: Float(animal.confidence),
                                boundingBox: animal.boundingBox,
                                attributes: ["species": animal.labels.first?.identifier ?? "unknown"]
                            ))
                        }
                    }

                    // Process humans
                    if let humanRequest = requests[1] as? VNDetectHumanRectanglesRequest,
                       let humans = humanRequest.results {
                        for (index, human) in humans.enumerated() {
                            allObjects.append(SceneObject(
                                id: UUID(),
                                label: "Person \(index + 1)",
                                category: .person,
                                confidence: Float(human.confidence),
                                boundingBox: human.boundingBox,
                                attributes: ["upperBodyOnly": String(human.upperBodyOnly)]
                            ))
                        }
                    }

                    // Process faces
                    if let faceRequest = requests[2] as? VNDetectFaceRectanglesRequest,
                       let faces = faceRequest.results {
                        for (index, face) in faces.enumerated() {
                            allObjects.append(SceneObject(
                                id: UUID(),
                                label: "Face \(index + 1)",
                                category: .face,
                                confidence: Float(face.confidence),
                                boundingBox: face.boundingBox,
                                attributes: [:]
                            ))
                        }
                    }

                    // Process barcodes
                    if let barcodeRequest = requests[3] as? VNDetectBarcodesRequest,
                       let barcodes = barcodeRequest.results {
                        for barcode in barcodes {
                            allObjects.append(SceneObject(
                                id: UUID(),
                                label: "Barcode",
                                category: .barcode,
                                confidence: Float(barcode.confidence),
                                boundingBox: barcode.boundingBox,
                                attributes: [
                                    "payload": barcode.payloadStringValue ?? "unknown",
                                    "type": barcode.symbology.rawValue
                                ]
                            ))
                        }
                    }

                    // Process text
                    if let textRequest = requests[4] as? VNRecognizeTextRequest,
                       let textObservations = textRequest.results {
                        for text in textObservations {
                            if let topCandidate = text.topCandidates(1).first {
                                allObjects.append(SceneObject(
                                    id: UUID(),
                                    label: "Text: \(topCandidate.string)",
                                    category: .text,
                                    confidence: Float(text.confidence),
                                    boundingBox: text.boundingBox,
                                    attributes: ["content": topCandidate.string]
                                ))
                            }
                        }
                    }

                    print("🎯 Detected \(allObjects.count) objects")
                    continuation.resume(returning: allObjects)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Scene Classification

    private func classifyScene(cgImage: CGImage) async -> SceneClassification {
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform([request])

                    if let results = request.results,
                       let topResult = results.first {
                        let classification = SceneClassification(
                            primaryCategory: self.mapToSceneType(identifier: topResult.identifier),
                            confidence: Float(topResult.confidence),
                            environment: self.determineEnvironment(identifier: topResult.identifier),
                            lighting: .unknown,
                            weather: .unknown
                        )
                        continuation.resume(returning: classification)
                    } else {
                        continuation.resume(returning: SceneClassification.unknown)
                    }
                } catch {
                    continuation.resume(returning: SceneClassification.unknown)
                }
            }
        }
    }

    // MARK: - Saliency Detection

    private func detectSaliency(cgImage: CGImage) async -> SaliencyMap? {
        return await withCheckedContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform([request])

                    if let result = request.results?.first {
                        let map = SaliencyMap(
                            salientObjects: result.salientObjects?.map { observation in
                                SalientRegion(
                                    boundingBox: observation.boundingBox,
                                    confidence: Float(observation.confidence)
                                )
                            } ?? [],
                            highestAttentionRegion: result.salientObjects?.first?.boundingBox
                        )
                        continuation.resume(returning: map)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Depth Estimation

    private func estimateDepth(cgImage: CGImage) async -> DepthMap? {
        // Real depth estimation using Vision framework
        // In production, could use ARKit depth data if available
        return await withCheckedContinuation { continuation in
            // Vision doesn't have direct depth estimation
            // This would integrate with ARKit depth data in real implementation
            continuation.resume(returning: nil)
        }
    }

    // MARK: - Relationship Analysis

    private func analyzeObjectRelationships(objects: [SceneObject]) -> [ObjectRelationship] {
        var relationships: [ObjectRelationship] = []

        // Spatial relationships
        for i in 0..<objects.count {
            for j in (i+1)..<objects.count {
                let obj1 = objects[i]
                let obj2 = objects[j]

                // Determine spatial relationship
                let spatial = determineSpatialRelationship(obj1, obj2)

                // Check for interactions
                let interaction = detectInteraction(obj1, obj2)

                if spatial != .unrelated || interaction != nil {
                    relationships.append(ObjectRelationship(
                        object1: obj1.id,
                        object2: obj2.id,
                        type: spatial,
                        interaction: interaction,
                        confidence: (obj1.confidence + obj2.confidence) / 2
                    ))
                }
            }
        }

        return relationships
    }

    private func determineSpatialRelationship(_ obj1: SceneObject, _ obj2: SceneObject) -> RelationshipType {
        let box1 = obj1.boundingBox
        let box2 = obj2.boundingBox

        // Check if objects overlap
        if box1.intersects(box2) {
            return .overlapping
        }

        // Check vertical relationships
        if box1.maxY < box2.minY {
            return .above
        } else if box1.minY > box2.maxY {
            return .below
        }

        // Check horizontal relationships
        if box1.maxX < box2.minX {
            return .leftOf
        } else if box1.minX > box2.maxX {
            return .rightOf
        }

        // Check proximity
        let centerDist = hypot(box1.midX - box2.midX, box1.midY - box2.midY)
        if centerDist < 0.3 {
            return .near
        }

        return .unrelated
    }

    private func detectInteraction(_ obj1: SceneObject, _ obj2: SceneObject) -> String? {
        // Detect semantic interactions
        if obj1.category == .person && obj2.category == .animal {
            return "person with animal"
        }
        if obj1.category == .person && obj2.category == .text {
            return "person reading"
        }
        if obj1.category == .person && obj2.category == .barcode {
            return "person scanning"
        }

        return nil
    }

    // MARK: - Temporal Analysis

    private func analyzeTemporalChanges(
        previous: SceneAnalysis,
        current: [SceneObject]
    ) -> TemporalChanges {
        var appeared: [SceneObject] = []
        var disappeared: [SceneObject] = []
        var moved: [(SceneObject, CGPoint)] = []

        // Find new objects
        for obj in current {
            let matchingPrevious = previous.objects.first { prev in
                prev.label == obj.label &&
                distance(prev.boundingBox.center, obj.boundingBox.center) < 0.2
            }

            if matchingPrevious == nil {
                appeared.append(obj)
            } else if let match = matchingPrevious {
                let movement = CGPoint(
                    x: obj.boundingBox.midX - match.boundingBox.midX,
                    y: obj.boundingBox.midY - match.boundingBox.midY
                )
                if abs(movement.x) > 0.05 || abs(movement.y) > 0.05 {
                    moved.append((obj, movement))
                }
            }
        }

        // Find disappeared objects
        for prevObj in previous.objects {
            let stillPresent = current.contains { curr in
                curr.label == prevObj.label &&
                distance(prevObj.boundingBox.center, curr.boundingBox.center) < 0.2
            }

            if !stillPresent {
                disappeared.append(prevObj)
            }
        }

        return TemporalChanges(
            objectsAppeared: appeared,
            objectsDisappeared: disappeared,
            objectsMoved: moved,
            significantChange: !appeared.isEmpty || !disappeared.isEmpty || moved.count > 2
        )
    }

    // MARK: - Context Determination

    private func determineSceneContext(
        classification: SceneClassification,
        objects: [SceneObject],
        location: CLLocation?
    ) -> SceneContext {
        var activities: [String] = []
        var tags: [String] = []

        // Activity detection
        if objects.contains(where: { $0.category == .person && $0.category == .animal }) {
            activities.append("interacting with animals")
        }
        if objects.contains(where: { $0.category == .barcode }) {
            activities.append("shopping or scanning")
        }
        if objects.contains(where: { $0.category == .text }) {
            activities.append("reading")
        }

        // Scene tags
        tags.append(classification.primaryCategory.rawValue)
        tags.append(classification.environment.rawValue)

        return SceneContext(
            environment: classification.environment,
            activities: activities,
            timeOfDay: determineTimeOfDay(),
            socialContext: determineSocialContext(objects: objects),
            tags: tags
        )
    }

    private func determineSocialContext(objects: [SceneObject]) -> String {
        let peopleCount = objects.filter { $0.category == .person }.count

        if peopleCount == 0 {
            return "alone"
        } else if peopleCount == 1 {
            return "one person"
        } else if peopleCount <= 3 {
            return "small group"
        } else {
            return "crowd"
        }
    }

    private func determineTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 5 && hour < 12 {
            return "morning"
        } else if hour >= 12 && hour < 17 {
            return "afternoon"
        } else if hour >= 17 && hour < 21 {
            return "evening"
        } else {
            return "night"
        }
    }

    // MARK: - Semantic Description

    private func generateSemanticDescription(
        objects: [SceneObject],
        relationships: [ObjectRelationship],
        context: SceneContext
    ) async -> String {
        // Use LLM to generate natural language description
        let objectsDesc = objects.prefix(5).map { "\($0.label) (\($0.category.rawValue))" }.joined(separator: ", ")

        let prompt = """
        Describe this scene in one concise sentence:
        - Environment: \(context.environment.rawValue)
        - Objects: \(objectsDesc)
        - Activities: \(context.activities.joined(separator: ", "))
        - Social context: \(context.socialContext)
        """

        do {
            let response = try await llmOrchestrator.chat(
                messages: [["role": "user", "content": prompt]],
                task: .fast
            )
            return response.content
        } catch {
            // Fallback to simple description
            return "Scene with \(objects.count) objects in a \(context.environment.rawValue) environment"
        }
    }

    // MARK: - Memory Integration

    private func storeSceneInMemory(_ scene: SceneAnalysis) async throws {
        // Store scene in RAG memory
        let memoryText = """
        Scene at \(scene.timestamp): \(scene.semanticDescription)
        Objects: \(scene.objects.map { $0.label }.joined(separator: ", "))
        Environment: \(scene.classification.environment.rawValue)
        """

        let context = MemoryContext(
            location: scene.location.map {
                LocationInfo(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            timestamp: scene.timestamp,
            activity: scene.context.activities.first,
            tags: scene.context.tags
        )

        _ = try await ragMemory.storeMemory(
            text: memoryText,
            type: .observation,
            context: context
        )
    }

    private func createSceneSnapshot(_ scene: SceneAnalysis) {
        let snapshot = SceneSnapshot(
            timestamp: scene.timestamp,
            objectSignature: scene.objects.map { "\($0.label)_\($0.boundingBox)" }.joined(),
            objectCount: scene.objects.count
        )

        sceneMemory.append(snapshot)
        if sceneMemory.count > maxMemorySnapshots {
            sceneMemory.removeFirst(sceneMemory.count - maxMemorySnapshots)
        }
    }

    // MARK: - Utilities

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return hypot(p1.x - p2.x, p1.y - p2.y)
    }

    private func mapToSceneType(identifier: String) -> SceneType {
        let lower = identifier.lowercased()

        if lower.contains("indoor") { return .indoor }
        if lower.contains("outdoor") { return .outdoor }
        if lower.contains("office") { return .office }
        if lower.contains("home") { return .home }
        if lower.contains("street") || lower.contains("road") { return .street }
        if lower.contains("nature") || lower.contains("park") { return .nature }
        if lower.contains("shop") || lower.contains("store") { return .retail }

        return .unknown
    }

    private func determineEnvironment(identifier: String) -> Environment {
        let lower = identifier.lowercased()

        if lower.contains("indoor") || lower.contains("inside") {
            return .indoor
        } else if lower.contains("outdoor") || lower.contains("outside") {
            return .outdoor
        }

        return .unknown
    }
}

// MARK: - Supporting Types

public struct SceneAnalysis: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let image: UIImage
    public let objects: [SceneObject]
    public let classification: SceneClassification
    public let relationships: [ObjectRelationship]
    public let context: SceneContext
    public let saliencyMap: SaliencyMap?
    public let depthMap: DepthMap?
    public let temporalChanges: TemporalChanges?
    public let semanticDescription: String
    public let location: CLLocation?
}

public struct SceneObject: Identifiable {
    public let id: UUID
    public let label: String
    public let category: ObjectCategory
    public let confidence: Float
    public let boundingBox: CGRect
    public let attributes: [String: String]
}

public struct SceneClassification {
    public let primaryCategory: SceneType
    public let confidence: Float
    public let environment: Environment
    public let lighting: Lighting
    public let weather: Weather

    static let unknown = SceneClassification(
        primaryCategory: .unknown,
        confidence: 0,
        environment: .unknown,
        lighting: .unknown,
        weather: .unknown
    )
}

public struct ObjectRelationship {
    public let object1: UUID
    public let object2: UUID
    public let type: RelationshipType
    public let interaction: String?
    public let confidence: Float
}

public struct TemporalChanges {
    public let objectsAppeared: [SceneObject]
    public let objectsDisappeared: [SceneObject]
    public let objectsMoved: [(SceneObject, CGPoint)]
    public let significantChange: Bool
}

public struct SceneContext {
    public let environment: Environment
    public let activities: [String]
    public let timeOfDay: String
    public let socialContext: String
    public let tags: [String]
}

public struct SaliencyMap {
    public let salientObjects: [SalientRegion]
    public let highestAttentionRegion: CGRect?
}

public struct SalientRegion {
    public let boundingBox: CGRect
    public let confidence: Float
}

public struct DepthMap {
    public let depthData: [Float]
    public let width: Int
    public let height: Int
}

private struct SceneSnapshot {
    let timestamp: Date
    let objectSignature: String
    let objectCount: Int
}

// MARK: - Enums

public enum SceneType: String {
    case indoor, outdoor, office, home, street, nature, retail, restaurant, unknown
}

public enum Environment: String {
    case indoor, outdoor, mixed, unknown
}

public enum Lighting: String {
    case bright, dim, natural, artificial, mixed, unknown
}

public enum Weather: String {
    case clear, cloudy, rainy, snowy, unknown
}

public enum ObjectCategory {
    case person, face, animal, vehicle, furniture, electronics
    case food, plant, barcode, text, general
}

public enum RelationshipType {
    case near, far, above, below, leftOf, rightOf
    case overlapping, containing, touching, unrelated
}

public enum SceneError: LocalizedError {
    case invalidImage
    case analysiseFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image provided"
        case .analysiseFailed: return "Scene analysis failed"
        }
    }
}

// MARK: - Extensions

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
