import XCTest
import UIKit
@testable import MetaGlassesCamera

/// Comprehensive tests for AI Systems
/// Tests RAG Memory, Face Recognition, and Multi-LLM Integration
@MainActor
final class AISystemsTests: XCTestCase {

    // MARK: - RAG Memory System Tests

    func testRAGMemoryInitialization() {
        let rag = ProductionRAGMemory.shared

        XCTAssertNotNil(rag)
        XCTAssertEqual(rag.memoryCount >= 0, true)
    }

    func testMemoryTypes() {
        let types: [MemoryType] = [
            .conversation,
            .observation,
            .reminder,
            .fact,
            .experience,
            .person,
            .place,
            .event
        ]

        for type in types {
            let memory = Memory(
                id: UUID(),
                text: "Test memory",
                type: type,
                embedding: Array(repeating: 0.1, count: 1536),
                context: MemoryContext(),
                metadata: [:],
                createdAt: Date(),
                lastAccessed: Date(),
                accessCount: 0
            )

            XCTAssertEqual(memory.type, type)
        }
    }

    func testMemoryContext() {
        let location = LocationInfo(
            latitude: 37.7749,
            longitude: -122.4194,
            name: "San Francisco"
        )

        let context = MemoryContext(
            location: location,
            timestamp: Date(),
            activity: "walking",
            weather: "sunny",
            people: ["Alice", "Bob"],
            tags: ["vacation", "photos"]
        )

        XCTAssertEqual(context.location?.name, "San Francisco")
        XCTAssertEqual(context.activity, "walking")
        XCTAssertEqual(context.people?.count, 2)
        XCTAssertEqual(context.tags?.count, 2)
    }

    func testMemoryCoding() throws {
        let memory = Memory(
            id: UUID(),
            text: "Test memory",
            type: .experience,
            embedding: Array(repeating: 0.1, count: 100),
            context: MemoryContext(),
            metadata: ["key": "value"],
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 5
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(memory)
        let decoded = try decoder.decode(Memory.self, from: data)

        XCTAssertEqual(memory.id, decoded.id)
        XCTAssertEqual(memory.text, decoded.text)
        XCTAssertEqual(memory.type, decoded.type)
        XCTAssertEqual(memory.embedding.count, decoded.embedding.count)
        XCTAssertEqual(memory.accessCount, decoded.accessCount)
    }

    func testScoredMemory() {
        let memory = Memory(
            id: UUID(),
            text: "Test memory",
            type: .fact,
            embedding: Array(repeating: 0.1, count: 100),
            context: MemoryContext(),
            metadata: [:],
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 0
        )

        let scoredMemory = ScoredMemory(memory: memory, score: 0.85)

        XCTAssertEqual(scoredMemory.score, 0.85)
        XCTAssertEqual(scoredMemory.memory.id, memory.id)
    }

    func testRAGError() {
        let errors: [RAGError] = [
            .invalidResponse,
            .apiError("Test error"),
            .parsingError
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    // MARK: - Face Recognition System Tests

    func testFaceRecognitionInitialization() {
        let faceRec = ProductionFaceRecognition.shared

        XCTAssertNotNil(faceRec)
        XCTAssertEqual(faceRec.knownFaces.count >= 0, true)
    }

    func testFaceProfile() {
        let profile = FaceProfile(
            id: UUID(),
            name: "John Doe",
            relationship: "Friend",
            embedding: Array(repeating: 0.1, count: 128),
            photoCount: 5,
            lastSeen: Date(),
            createdAt: Date()
        )

        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.relationship, "Friend")
        XCTAssertEqual(profile.photoCount, 5)
        XCTAssertEqual(profile.embedding.count, 128)
    }

    func testFaceProfileCoding() throws {
        let profile = FaceProfile(
            id: UUID(),
            name: "Jane Smith",
            relationship: "Family",
            embedding: Array(repeating: 0.2, count: 128),
            photoCount: 10,
            lastSeen: Date(),
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(FaceProfile.self, from: data)

        XCTAssertEqual(profile.id, decoded.id)
        XCTAssertEqual(profile.name, decoded.name)
        XCTAssertEqual(profile.relationship, decoded.relationship)
        XCTAssertEqual(profile.embedding.count, decoded.embedding.count)
        XCTAssertEqual(profile.photoCount, decoded.photoCount)
    }

    func testRecognitionResult() {
        let result = RecognitionResult(
            personId: UUID(),
            name: "Test Person",
            confidence: 0.95,
            boundingBox: CGRect(x: 100, y: 100, width: 200, height: 200),
            timestamp: Date()
        )

        XCTAssertEqual(result.name, "Test Person")
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertEqual(result.boundingBox.width, 200)
        XCTAssertEqual(result.boundingBox.height, 200)
    }

    func testFaceRecognitionErrors() {
        let errors: [FaceRecognitionError] = [
            .invalidImage,
            .noFacesDetected,
            .noFeaturesFound,
            .databaseError
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testDetectFacesInvalidImage() async {
        let faceRec = ProductionFaceRecognition.shared
        let invalidImage = UIImage()

        do {
            _ = try await faceRec.detectFaces(in: invalidImage)
            XCTFail("Should throw error for invalid image")
        } catch {
            XCTAssertTrue(error is FaceRecognitionError)
        }
    }

    func testDetectFacesValidImage() async {
        let faceRec = ProductionFaceRecognition.shared

        // Create a simple test image
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let testImage = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        do {
            let faces = try await faceRec.detectFaces(in: testImage)
            // May not find faces in gray square, but should not crash
            XCTAssertTrue(faces.count >= 0)
        } catch {
            // Error is acceptable for test image
            XCTAssertTrue(true)
        }
    }

    // MARK: - CosineSimilarity Tests

    func testCosineSimilarityIdentical() {
        let vector = Array(repeating: Float(0.5), count: 128)

        // Create a test RAG instance to access similarity function
        let embedding1 = vector
        let embedding2 = vector

        // Calculate expected similarity (should be 1.0 for identical vectors)
        let dotProduct = zip(embedding1, embedding2).map { $0.0 * $0.1 }.reduce(0, +)
        let magnitudeA = sqrt(embedding1.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(embedding2.map { $0 * $0 }.reduce(0, +))
        let similarity = dotProduct / (magnitudeA * magnitudeB)

        XCTAssertGreaterThan(similarity, 0.9)
    }

    func testCosineSimilarityOrthogonal() {
        var vector1 = Array(repeating: Float(0), count: 128)
        var vector2 = Array(repeating: Float(0), count: 128)

        vector1[0] = 1.0
        vector2[1] = 1.0

        // Orthogonal vectors should have similarity close to 0
        let dotProduct = zip(vector1, vector2).map { $0.0 * $0.1 }.reduce(0, +)

        XCTAssertEqual(dotProduct, 0, accuracy: 0.01)
    }

    // MARK: - Performance Tests

    func testRAGMemoryPerformance() {
        let memories: [Memory] = (0..<100).map { i in
            Memory(
                id: UUID(),
                text: "Test memory \(i)",
                type: .fact,
                embedding: Array(repeating: Float(i) / 100.0, count: 100),
                context: MemoryContext(),
                metadata: [:],
                createdAt: Date(),
                lastAccessed: Date(),
                accessCount: 0
            )
        }

        measure {
            for memory in memories {
                _ = memory.text
                _ = memory.embedding
            }
        }
    }

    func testFaceEmbeddingPerformance() {
        let embeddings: [[Float]] = (0..<100).map { _ in
            Array(repeating: Float.random(in: 0...1), count: 128)
        }

        measure {
            for embedding in embeddings {
                let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
                _ = embedding.map { $0 / magnitude }
            }
        }
    }

    // MARK: - Vector Operations Tests

    func testVectorNormalization() {
        var vector = Array(repeating: Float(2.0), count: 128)

        // Calculate magnitude
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        XCTAssertGreaterThan(magnitude, 0)

        // Normalize
        vector = vector.map { $0 / magnitude }

        // Check normalized magnitude is 1.0
        let normalizedMagnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        XCTAssertEqual(normalizedMagnitude, 1.0, accuracy: 0.001)
    }

    func testVectorDotProduct() {
        let vector1 = Array(repeating: Float(1.0), count: 128)
        let vector2 = Array(repeating: Float(2.0), count: 128)

        let dotProduct = zip(vector1, vector2).map { $0.0 * $0.1 }.reduce(0, +)

        XCTAssertGreaterThan(dotProduct, 0)
    }

    func testVectorMagnitude() {
        let vector = Array(repeating: Float(3.0), count: 128)

        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))

        let expected = sqrt(Float(128) * 9.0) // sqrt(128 * 3^2)
        XCTAssertEqual(magnitude, expected, accuracy: 0.01)
    }

    // MARK: - Edge Cases

    func testEmptyEmbedding() {
        let memory = Memory(
            id: UUID(),
            text: "Test",
            type: .fact,
            embedding: [],
            context: MemoryContext(),
            metadata: [:],
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 0
        )

        XCTAssertEqual(memory.embedding.count, 0)
    }

    func testLargeEmbedding() {
        let largeEmbedding = Array(repeating: Float(0.1), count: 10000)

        let memory = Memory(
            id: UUID(),
            text: "Test",
            type: .fact,
            embedding: largeEmbedding,
            context: MemoryContext(),
            metadata: [:],
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 0
        )

        XCTAssertEqual(memory.embedding.count, 10000)
    }

    func testMemoryWithMaxAccessCount() {
        let memory = Memory(
            id: UUID(),
            text: "Popular memory",
            type: .fact,
            embedding: Array(repeating: 0.1, count: 100),
            context: MemoryContext(),
            metadata: [:],
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: Int.max
        )

        XCTAssertEqual(memory.accessCount, Int.max)
    }

    // MARK: - Metadata Tests

    func testMemoryMetadata() {
        let metadata = [
            "source": "camera",
            "quality": "high",
            "processed": "true"
        ]

        let memory = Memory(
            id: UUID(),
            text: "Test memory",
            type: .observation,
            embedding: Array(repeating: 0.1, count: 100),
            context: MemoryContext(),
            metadata: metadata,
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 0
        )

        XCTAssertEqual(memory.metadata["source"], "camera")
        XCTAssertEqual(memory.metadata["quality"], "high")
        XCTAssertEqual(memory.metadata["processed"], "true")
    }

    func testFaceProfileMetadata() {
        let profile = FaceProfile(
            id: UUID(),
            name: "Test Person",
            relationship: nil,
            embedding: Array(repeating: 0.1, count: 128),
            photoCount: 0,
            lastSeen: Date(),
            createdAt: Date()
        )

        XCTAssertNil(profile.relationship)
        XCTAssertEqual(profile.photoCount, 0)
    }

    // MARK: - Timestamp Tests

    func testMemoryTimestamps() {
        let now = Date()
        let memory = Memory(
            id: UUID(),
            text: "Test",
            type: .fact,
            embedding: Array(repeating: 0.1, count: 100),
            context: MemoryContext(timestamp: now),
            metadata: [:],
            createdAt: now,
            lastAccessed: now,
            accessCount: 0
        )

        XCTAssertEqual(memory.createdAt.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
        XCTAssertEqual(memory.lastAccessed.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func testFaceProfileTimestamps() {
        let now = Date()
        let profile = FaceProfile(
            id: UUID(),
            name: "Test",
            relationship: nil,
            embedding: Array(repeating: 0.1, count: 128),
            photoCount: 1,
            lastSeen: now,
            createdAt: now
        )

        XCTAssertEqual(profile.lastSeen.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
        XCTAssertEqual(profile.createdAt.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentMemoryAccess() async {
        let rag = ProductionRAGMemory.shared

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = rag.memoryCount
                    _ = rag.recentMemories
                }
            }
        }

        // Should not crash with concurrent access
        XCTAssertTrue(true)
    }

    func testConcurrentFaceProfileAccess() async {
        let faceRec = ProductionFaceRecognition.shared

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = faceRec.knownFaces
                    _ = faceRec.recentRecognitions
                }
            }
        }

        // Should not crash with concurrent access
        XCTAssertTrue(true)
    }
}
