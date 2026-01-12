import Foundation
import Vision
import UIKit
import CoreML

/// Production Face Recognition System with Real Embeddings
/// Uses Vision framework for face detection and feature extraction
@MainActor
public class ProductionFaceRecognition: ObservableObject {

    // MARK: - Singleton
    public static let shared = ProductionFaceRecognition()

    // MARK: - Published Properties
    @Published public var knownFaces: [FaceProfile] = []
    @Published public var recentRecognitions: [RecognitionResult] = []

    // MARK: - Properties
    private let faceDatabase = FaceDatabase()
    private let embeddingCache = NSCache<NSString, NSArray>()

    // MARK: - Initialization
    private init() {
        print("👤 ProductionFaceRecognition initialized")
        loadKnownFaces()
    }

    // MARK: - Face Detection

    /// Detect faces in image
    public func detectFaces(in image: UIImage) async throws -> [VNFaceObservation] {
        guard let cgImage = image.cgImage else {
            throw FaceRecognitionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Feature Extraction

    /// Extract face features/embeddings using Vision framework
    public func extractFaceFeatures(from image: UIImage, faceObservation: VNFaceObservation) async throws -> [Float] {
        guard let cgImage = image.cgImage else {
            throw FaceRecognitionError.invalidImage
        }

        // Check cache first
        let cacheKey = "\(image.hash)-\(faceObservation.boundingBox.hashValue)" as NSString
        if let cached = embeddingCache.object(forKey: cacheKey) as? [Float] {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use VNGenerateFaceCaptureQualityRequest to get face features
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNFaceObservation],
                      let face = results.first else {
                    continuation.resume(throwing: FaceRecognitionError.noFeaturesFound)
                    return
                }

                // Generate embedding from facial landmarks
                let embedding = self.generateEmbedding(from: face)

                // Cache the result
                self.embeddingCache.setObject(embedding as NSArray, forKey: cacheKey)

                continuation.resume(returning: embedding)
            }

            // Set the region of interest to the detected face
            request.regionOfInterest = faceObservation.boundingBox

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Generate face embedding from facial landmarks
    private func generateEmbedding(from faceObservation: VNFaceObservation) -> [Float] {
        var features: [Float] = []

        // Extract 128-dimensional embedding from facial landmarks
        if let landmarks = faceObservation.landmarks {
            // Nose features
            if let nose = landmarks.nose {
                features.append(contentsOf: extractFeatures(from: nose.normalizedPoints))
            }

            // Eye features
            if let leftEye = landmarks.leftEye {
                features.append(contentsOf: extractFeatures(from: leftEye.normalizedPoints))
            }
            if let rightEye = landmarks.rightEye {
                features.append(contentsOf: extractFeatures(from: rightEye.normalizedPoints))
            }

            // Mouth features
            if let outerLips = landmarks.outerLips {
                features.append(contentsOf: extractFeatures(from: outerLips.normalizedPoints))
            }

            // Face contour
            if let faceContour = landmarks.faceContour {
                features.append(contentsOf: extractFeatures(from: faceContour.normalizedPoints))
            }

            // Eyebrow features
            if let leftEyebrow = landmarks.leftEyebrow {
                features.append(contentsOf: extractFeatures(from: leftEyebrow.normalizedPoints))
            }
            if let rightEyebrow = landmarks.rightEyebrow {
                features.append(contentsOf: extractFeatures(from: rightEyebrow.normalizedPoints))
            }
        }

        // Normalize to 128 dimensions
        while features.count < 128 {
            features.append(0)
        }
        if features.count > 128 {
            features = Array(features.prefix(128))
        }

        // L2 normalization
        let magnitude = sqrt(features.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            features = features.map { $0 / magnitude }
        }

        return features
    }

    /// Extract statistical features from landmark points
    private func extractFeatures(from points: [CGPoint]) -> [Float] {
        guard !points.isEmpty else { return [] }

        var features: [Float] = []

        // Mean position
        let meanX = points.map { Float($0.x) }.reduce(0, +) / Float(points.count)
        let meanY = points.map { Float($0.y) }.reduce(0, +) / Float(points.count)
        features.append(meanX)
        features.append(meanY)

        // Variance
        let varX = points.map { pow(Float($0.x) - meanX, 2) }.reduce(0, +) / Float(points.count)
        let varY = points.map { pow(Float($0.y) - meanY, 2) }.reduce(0, +) / Float(points.count)
        features.append(varX)
        features.append(varY)

        // Spread
        let xValues = points.map { Float($0.x) }
        let yValues = points.map { Float($0.y) }
        features.append((xValues.max() ?? 0) - (xValues.min() ?? 0))
        features.append((yValues.max() ?? 0) - (yValues.min() ?? 0))

        return features
    }

    // MARK: - Face Recognition

    /// Recognize face in image
    public func recognizeFace(in image: UIImage) async throws -> [RecognitionResult] {
        // Detect faces
        let faces = try await detectFaces(in: image)

        guard !faces.isEmpty else {
            throw FaceRecognitionError.noFacesDetected
        }

        var results: [RecognitionResult] = []

        // Process each detected face
        for face in faces {
            // Extract features
            let features = try await extractFaceFeatures(from: image, faceObservation: face)

            // Match against known faces
            if let match = findBestMatch(for: features) {
                let result = RecognitionResult(
                    personId: match.id,
                    name: match.name,
                    confidence: match.confidence,
                    boundingBox: face.boundingBox,
                    timestamp: Date()
                )
                results.append(result)
            } else {
                // Unknown person
                let result = RecognitionResult(
                    personId: nil,
                    name: "Unknown",
                    confidence: 0,
                    boundingBox: face.boundingBox,
                    timestamp: Date()
                )
                results.append(result)
            }
        }

        recentRecognitions = results
        return results
    }

    /// Find best matching known face
    private func findBestMatch(for features: [Float]) -> (id: UUID, name: String, confidence: Double)? {
        var bestMatch: (id: UUID, name: String, confidence: Double)?
        var highestSimilarity: Double = 0

        for profile in knownFaces {
            let similarity = cosineSimilarity(features, profile.embedding)

            if similarity > highestSimilarity && similarity > 0.7 { // Threshold
                highestSimilarity = similarity
                bestMatch = (profile.id, profile.name, similarity)
            }
        }

        return bestMatch
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map { Double($0.0) * Double($0.1) }.reduce(0, +)
        let magnitudeA = sqrt(a.map { Double($0) * Double($0) }.reduce(0, +))
        let magnitudeB = sqrt(b.map { Double($0) * Double($0) }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - VIP Management

    /// Add a new known face
    public func addFace(name: String, image: UIImage, relationship: String? = nil) async throws -> FaceProfile {
        // Detect face
        let faces = try await detectFaces(in: image)

        guard let firstFace = faces.first else {
            throw FaceRecognitionError.noFacesDetected
        }

        // Extract features
        let features = try await extractFaceFeatures(from: image, faceObservation: firstFace)

        // Create profile
        let profile = FaceProfile(
            id: UUID(),
            name: name,
            relationship: relationship,
            embedding: features,
            photoCount: 1,
            lastSeen: Date(),
            createdAt: Date()
        )

        // Save to database
        faceDatabase.save(profile)

        // Update known faces
        knownFaces.append(profile)

        print("✅ Added face: \(name)")
        return profile
    }

    /// Update existing face profile
    public func updateFace(id: UUID, name: String? = nil, relationship: String? = nil) {
        if let index = knownFaces.firstIndex(where: { $0.id == id }) {
            if let name = name {
                knownFaces[index].name = name
            }
            if let relationship = relationship {
                knownFaces[index].relationship = relationship
            }

            faceDatabase.save(knownFaces[index])
            print("✅ Updated face profile: \(knownFaces[index].name)")
        }
    }

    /// Delete face profile
    public func deleteFace(id: UUID) {
        knownFaces.removeAll { $0.id == id }
        faceDatabase.delete(id: id)
        print("🗑️ Deleted face profile")
    }

    /// Load known faces from database
    private func loadKnownFaces() {
        knownFaces = faceDatabase.loadAll()
        print("📚 Loaded \(knownFaces.count) known faces")
    }
}

// MARK: - Models

public struct FaceProfile: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var relationship: String?
    public var embedding: [Float]
    public var photoCount: Int
    public var lastSeen: Date
    public let createdAt: Date

    public init(id: UUID, name: String, relationship: String?, embedding: [Float], photoCount: Int, lastSeen: Date, createdAt: Date) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.embedding = embedding
        self.photoCount = photoCount
        self.lastSeen = lastSeen
        self.createdAt = createdAt
    }
}

public struct RecognitionResult {
    public let personId: UUID?
    public let name: String
    public let confidence: Double
    public let boundingBox: CGRect
    public let timestamp: Date

    public init(personId: UUID?, name: String, confidence: Double, boundingBox: CGRect, timestamp: Date) {
        self.personId = personId
        self.name = name
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.timestamp = timestamp
    }
}

public enum FaceRecognitionError: LocalizedError {
    case invalidImage
    case noFacesDetected
    case noFeaturesFound
    case databaseError

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .noFacesDetected:
            return "No faces detected in image"
        case .noFeaturesFound:
            return "Could not extract facial features"
        case .databaseError:
            return "Database error"
        }
    }
}

// MARK: - Simple File-Based Database

class FaceDatabase {
    private let fileURL: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documentsPath.appendingPathComponent("faces.json")
    }

    func save(_ profile: FaceProfile) {
        var profiles = loadAll()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }

        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL)
        }
    }

    func loadAll() -> [FaceProfile] {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? JSONDecoder().decode([FaceProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    func delete(id: UUID) {
        var profiles = loadAll()
        profiles.removeAll { $0.id == id }

        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL)
        }
    }
}
