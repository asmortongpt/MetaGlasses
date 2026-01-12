import XCTest
import UIKit
@testable import MetaGlassesCamera

/// Performance Benchmark Tests
/// Measures speed and efficiency of critical operations
@MainActor
final class BenchmarkTests: XCTestCase {

    // MARK: - Pattern Detection Benchmarks

    func testPatternDetectionSpeed() async {
        let learning = UserPatternLearningSystem.shared

        // Prepare test data: 1000 actions over 30 days
        let calendar = Calendar.current
        let baseDate = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago

        for i in 0..<1000 {
            let offset = Double(i) * 3600 // 1 hour apart
            let timestamp = baseDate.addingTimeInterval(offset)

            let action = UserAction(
                id: UUID(),
                type: i % 3 == 0 ? .capturePhoto : (i % 3 == 1 ? .analyzePhoto : .addMemory),
                timestamp: timestamp,
                metadata: ["index": "\(i)"]
            )

            learning.recordAction(action)
        }

        // Measure pattern analysis time
        measure {
            Task {
                await learning.analyzePatterns()
            }
        }

        // Cleanup
        learning.clearLearning()
    }

    func testTemporalPatternDetectionBenchmark() {
        let learning = UserPatternLearningSystem.shared

        // Create 500 temporal actions
        for i in 0..<500 {
            let hour = i % 24
            var components = DateComponents()
            components.hour = hour
            components.minute = 0

            let timestamp = Calendar.current.date(from: components) ?? Date()

            let action = UserAction(
                id: UUID(),
                type: .capturePhoto,
                timestamp: timestamp
            )

            learning.recordAction(action)
        }

        measure {
            // Measure internal pattern detection
            _ = learning.learnedPatterns
        }

        learning.clearLearning()
    }

    // MARK: - Knowledge Graph Query Benchmarks

    func testKnowledgeGraphQueryPerformance() {
        let graph = KnowledgeGraphSystem.shared

        // Create 1000 entities
        var entities: [Entity] = []
        for i in 0..<1000 {
            let entity = Entity(
                id: UUID(),
                type: EntityType.allCases[i % 5],
                name: "Entity \(i)",
                properties: ["index": "\(i)"],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: i
            )
            entities.append(entity)
            graph.addEntity(entity)
        }

        // Create 2000 relationships
        for i in 0..<2000 {
            let sourceId = entities[i % entities.count].id
            let targetId = entities[(i + 1) % entities.count].id

            let relationship = Relationship(
                id: UUID(),
                type: RelationshipType.allCases[i % 7],
                sourceId: sourceId,
                targetId: targetId,
                strength: Double.random(in: 0.5...1.0),
                properties: [:],
                createdAt: Date()
            )

            graph.addRelationship(relationship)
        }

        // Measure query performance
        measure {
            for entity in entities.prefix(100) {
                _ = graph.getRelationships(for: entity.id)
                _ = graph.getRelatedEntities(for: entity.id)
            }
        }

        graph.clearGraph()
    }

    func testGraphPathFindingPerformance() {
        let graph = KnowledgeGraphSystem.shared

        // Create a chain of 100 entities
        var entities: [Entity] = []
        for i in 0..<100 {
            let entity = Entity(
                id: UUID(),
                type: .person,
                name: "Person \(i)",
                properties: [:],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            entities.append(entity)
            graph.addEntity(entity)
        }

        // Connect them in sequence
        for i in 0..<(entities.count - 1) {
            let relationship = Relationship(
                id: UUID(),
                type: .knows,
                sourceId: entities[i].id,
                targetId: entities[i + 1].id,
                strength: 1.0,
                properties: [:],
                createdAt: Date()
            )
            graph.addRelationship(relationship)
        }

        // Measure path finding
        measure {
            for i in stride(from: 0, to: entities.count - 10, by: 10) {
                _ = graph.findPath(from: entities[i].id, to: entities[i + 9].id)
            }
        }

        graph.clearGraph()
    }

    func testClusterDetectionPerformance() {
        let graph = KnowledgeGraphSystem.shared

        // Create multiple disconnected clusters
        for cluster in 0..<10 {
            var clusterEntities: [Entity] = []

            // 50 entities per cluster
            for i in 0..<50 {
                let entity = Entity(
                    id: UUID(),
                    type: .person,
                    name: "Cluster\(cluster)_Person\(i)",
                    properties: [:],
                    createdAt: Date(),
                    lastUpdated: Date(),
                    observations: 1
                )
                clusterEntities.append(entity)
                graph.addEntity(entity)
            }

            // Connect within cluster
            for i in 0..<(clusterEntities.count - 1) {
                let relationship = Relationship(
                    id: UUID(),
                    type: .knows,
                    sourceId: clusterEntities[i].id,
                    targetId: clusterEntities[i + 1].id,
                    strength: 1.0,
                    properties: [:],
                    createdAt: Date()
                )
                graph.addRelationship(relationship)
            }
        }

        // Measure cluster detection
        measure {
            _ = graph.getClusters()
        }

        graph.clearGraph()
    }

    // MARK: - Embedding Generation Benchmarks

    func testEmbeddingComputationSpeed() {
        let embeddings: [[Float]] = (0..<1000).map { _ in
            Array(repeating: Float.random(in: 0...1), count: 1536)
        }

        measure {
            for embedding in embeddings {
                // Normalize embedding (common operation)
                let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
                _ = embedding.map { $0 / magnitude }
            }
        }
    }

    func testCosineSimilarityBenchmark() {
        let embedding1 = Array(repeating: Float(0.5), count: 1536)
        let embeddings = (0..<1000).map { _ in
            Array(repeating: Float.random(in: 0...1), count: 1536)
        }

        measure {
            for embedding2 in embeddings {
                // Calculate cosine similarity
                let dotProduct = zip(embedding1, embedding2).map { $0.0 * $0.1 }.reduce(0, +)
                let mag1 = sqrt(embedding1.map { $0 * $0 }.reduce(0, +))
                let mag2 = sqrt(embedding2.map { $0 * $0 }.reduce(0, +))
                _ = dotProduct / (mag1 * mag2)
            }
        }
    }

    func testBatchSimilarityComputation() {
        let queryEmbedding = Array(repeating: Float(0.5), count: 1536)
        let embeddings = (0..<10000).map { _ in
            Array(repeating: Float.random(in: 0...1), count: 1536)
        }

        measure {
            var similarities: [Float] = []
            for embedding in embeddings {
                let dotProduct = zip(queryEmbedding, embedding).map { $0.0 * $0.1 }.reduce(0, +)
                let mag1 = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
                let mag2 = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
                let similarity = dotProduct / (mag1 * mag2)
                similarities.append(similarity)
            }

            // Sort by similarity
            _ = similarities.sorted(by: >)
        }
    }

    // MARK: - Memory Usage Benchmarks

    func testMemoryUsageOverTime() {
        let graph = KnowledgeGraphSystem.shared

        // Measure memory before
        let startMemory = getMemoryUsage()

        // Add 5000 entities
        for i in 0..<5000 {
            let entity = Entity(
                id: UUID(),
                type: .person,
                name: "Person \(i)",
                properties: ["bio": String(repeating: "x", count: 100)],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            graph.addEntity(entity)
        }

        // Measure memory after
        let endMemory = getMemoryUsage()

        let memoryIncreaseMB = (endMemory - startMemory) / 1024 / 1024

        print("Memory increase: \(memoryIncreaseMB) MB for 5000 entities")

        // Should be reasonable (< 50 MB)
        XCTAssertLessThan(memoryIncreaseMB, 50)

        graph.clearGraph()
    }

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    // MARK: - Performance Optimizer Benchmarks

    func testImageCachingPerformance() {
        let optimizer = PerformanceOptimizer.shared

        // Create test images
        let images = (0..<100).map { _ in createTestImage() }

        measure {
            // Cache images
            for (index, image) in images.enumerated() {
                optimizer.cacheImage(image, forKey: "image_\(index)")
            }

            // Retrieve cached images
            for index in 0..<100 {
                _ = optimizer.getCachedImage(forKey: "image_\(index)")
            }
        }
    }

    func testMemoryOptimizationSpeed() {
        let optimizer = PerformanceOptimizer.shared

        // Fill cache with images
        for i in 0..<50 {
            let image = createTestImage()
            optimizer.cacheImage(image, forKey: "test_\(i)")
        }

        measure {
            optimizer.optimizeMemory()
        }
    }

    // MARK: - Concurrent Operation Benchmarks

    func testConcurrentPatternAnalysis() async {
        let learning = UserPatternLearningSystem.shared

        // Add test actions
        for i in 0..<500 {
            let action = UserAction(
                id: UUID(),
                type: .capturePhoto,
                timestamp: Date().addingTimeInterval(Double(i * 60))
            )
            learning.recordAction(action)
        }

        measure {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<10 {
                        group.addTask {
                            await learning.analyzePatterns()
                        }
                    }
                }
            }
        }

        learning.clearLearning()
    }

    func testConcurrentGraphQueries() async {
        let graph = KnowledgeGraphSystem.shared

        // Create test data
        var entities: [Entity] = []
        for i in 0..<200 {
            let entity = Entity(
                id: UUID(),
                type: .person,
                name: "Person \(i)",
                properties: [:],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            entities.append(entity)
            graph.addEntity(entity)
        }

        measure {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for entity in entities.prefix(20) {
                        group.addTask {
                            _ = graph.getRelationships(for: entity.id)
                            _ = graph.getRelatedEntities(for: entity.id)
                        }
                    }
                }
            }
        }

        graph.clearGraph()
    }

    // MARK: - Scalability Tests

    func testScalabilityWith10kActions() async {
        let learning = UserPatternLearningSystem.shared

        measure {
            // Add 10,000 actions
            for i in 0..<10000 {
                let action = UserAction(
                    id: UUID(),
                    type: ActionType.allCases[i % ActionType.allCases.count],
                    timestamp: Date().addingTimeInterval(Double(i))
                )
                learning.recordAction(action)
            }

            // Analyze patterns
            Task {
                await learning.analyzePatterns()
            }
        }

        learning.clearLearning()
    }

    func testScalabilityWith10kEntities() {
        let graph = KnowledgeGraphSystem.shared

        measure {
            // Add 10,000 entities
            for i in 0..<10000 {
                let entity = Entity(
                    id: UUID(),
                    type: EntityType.allCases[i % 5],
                    name: "Entity \(i)",
                    properties: [:],
                    createdAt: Date(),
                    lastUpdated: Date(),
                    observations: 1
                )
                graph.addEntity(entity)
            }

            // Query most connected
            _ = graph.getMostConnected(limit: 10)
        }

        graph.clearGraph()
    }

    // MARK: - Helper Methods

    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Throughput Tests

    func testActionRecordingThroughput() {
        let learning = UserPatternLearningSystem.shared

        let startTime = Date()
        var actionsRecorded = 0

        // Record for 1 second
        while Date().timeIntervalSince(startTime) < 1.0 {
            let action = UserAction(
                id: UUID(),
                type: .capturePhoto,
                timestamp: Date()
            )
            learning.recordAction(action)
            actionsRecorded += 1
        }

        print("Actions recorded per second: \(actionsRecorded)")

        // Should handle at least 100 actions/second
        XCTAssertGreaterThan(actionsRecorded, 100)

        learning.clearLearning()
    }

    func testGraphInsertionThroughput() {
        let graph = KnowledgeGraphSystem.shared

        let startTime = Date()
        var entitiesAdded = 0

        // Insert for 1 second
        while Date().timeIntervalSince(startTime) < 1.0 {
            let entity = Entity(
                id: UUID(),
                type: .person,
                name: "Person \(entitiesAdded)",
                properties: [:],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            graph.addEntity(entity)
            entitiesAdded += 1
        }

        print("Entities added per second: \(entitiesAdded)")

        // Should handle at least 50 entities/second
        XCTAssertGreaterThan(entitiesAdded, 50)

        graph.clearGraph()
    }
}

// MARK: - Helper Extensions

extension EntityType: CaseIterable {
    public static var allCases: [EntityType] = [.person, .place, .event, .concept, .object]
}

extension RelationshipType: CaseIterable {
    public static var allCases: [RelationshipType] = [
        .knows, .locatedAt, .participatedIn, .relatedTo, .partOf, .causedBy, .associatedWith
    ]
}

extension ActionType: CaseIterable {
    public static var allCases: [ActionType] = [
        .capturePhoto, .recordVideo, .analyzePhoto, .recognizeFace,
        .addMemory, .viewGallery, .useVoiceCommand, .acceptSuggestion,
        .dismissSuggestion, .unknown
    ]
}
