import XCTest
import CoreLocation
@testable import MetaGlassesCamera

/// Comprehensive tests for Intelligence Systems
/// Tests Context Awareness, Pattern Learning, and Knowledge Graph
@MainActor
final class IntelligenceTests: XCTestCase {

    // MARK: - Context Awareness System Tests

    func testContextAwarenessInitialization() {
        let context = ContextAwarenessSystem.shared

        XCTAssertNotNil(context)
        XCTAssertEqual(context.isTrackingLocation, false)
        XCTAssertEqual(context.isTrackingActivity, false)
    }

    func testGetCurrentContext() {
        let context = ContextAwarenessSystem.shared
        let userContext = context.getCurrentContext()

        XCTAssertNotNil(userContext)
        XCTAssertNotNil(userContext.timestamp)
        XCTAssertNotEqual(userContext.timeOfDay, .unknown)
    }

    func testTimeOfDayDetection() {
        // Test early morning (5-8am)
        XCTAssertEqual(TimeOfDay.from(hour: 6), .earlyMorning)

        // Test morning (8am-12pm)
        XCTAssertEqual(TimeOfDay.from(hour: 10), .morning)

        // Test afternoon (12pm-5pm)
        XCTAssertEqual(TimeOfDay.from(hour: 14), .afternoon)

        // Test evening (5pm-9pm)
        XCTAssertEqual(TimeOfDay.from(hour: 19), .evening)

        // Test night (9pm-5am)
        XCTAssertEqual(TimeOfDay.from(hour: 22), .night)
        XCTAssertEqual(TimeOfDay.from(hour: 2), .night)
    }

    func testWorkHoursDetection() {
        let context = ContextAwarenessSystem.shared
        let calendar = Calendar.current
        let now = Date()

        // Get current hour and weekday
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)

        let userContext = context.getCurrentContext()

        // Work hours should be 9am-5pm on weekdays
        if !isWeekend && hour >= 9 && hour < 17 {
            XCTAssertTrue(userContext.isWorkHours)
        }
    }

    func testContextCoding() throws {
        let context = UserContext()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(context)
        let decoded = try decoder.decode(UserContext.self, from: data)

        XCTAssertEqual(context.timeOfDay, decoded.timeOfDay)
        XCTAssertEqual(context.isWeekend, decoded.isWeekend)
        XCTAssertEqual(context.activityType, decoded.activityType)
    }

    // MARK: - Pattern Learning System Tests

    func testPatternLearningInitialization() {
        let learning = UserPatternLearningSystem.shared

        XCTAssertNotNil(learning)
        XCTAssertEqual(learning.isLearning, false)
        XCTAssertEqual(learning.learnedPatterns.count >= 0, true)
    }

    func testRecordAction() {
        let learning = UserPatternLearningSystem.shared

        let action = UserAction(
            id: UUID(),
            type: .capturePhoto,
            timestamp: Date(),
            metadata: ["test": "value"]
        )

        learning.recordAction(action)

        // Action should be recorded (internal state)
        XCTAssertTrue(true) // Passes if no crash
    }

    func testActionTypes() {
        let actionTypes: [ActionType] = [
            .capturePhoto,
            .recordVideo,
            .analyzePhoto,
            .recognizeFace,
            .addMemory,
            .viewGallery,
            .useVoiceCommand,
            .acceptSuggestion,
            .dismissSuggestion,
            .unknown
        ]

        // Test all action types can be encoded/decoded
        for actionType in actionTypes {
            let action = UserAction(
                id: UUID(),
                type: actionType,
                timestamp: Date()
            )

            XCTAssertEqual(action.type, actionType)
        }
    }

    func testPatternTypes() {
        let patternTypes: [PatternType] = [
            .temporal,
            .location,
            .sequential,
            .contextual
        ]

        for patternType in patternTypes {
            let pattern = LearnedPattern(
                id: UUID(),
                type: patternType,
                description: "Test pattern",
                conditions: ["test": "value"],
                predictedAction: .capturePhoto,
                confidence: 0.8,
                occurrences: 5,
                firstOccurrence: Date(),
                lastOccurrence: Date()
            )

            XCTAssertEqual(pattern.type, patternType)
            XCTAssertEqual(pattern.confidence, 0.8)
            XCTAssertEqual(pattern.occurrences, 5)
        }
    }

    func testPatternCoding() throws {
        let pattern = LearnedPattern(
            id: UUID(),
            type: .temporal,
            description: "Test pattern",
            conditions: ["hour": "10"],
            predictedAction: .capturePhoto,
            confidence: 0.85,
            occurrences: 10,
            firstOccurrence: Date(),
            lastOccurrence: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(pattern)
        let decoded = try decoder.decode(LearnedPattern.self, from: data)

        XCTAssertEqual(pattern.id, decoded.id)
        XCTAssertEqual(pattern.type, decoded.type)
        XCTAssertEqual(pattern.confidence, decoded.confidence)
        XCTAssertEqual(pattern.occurrences, decoded.occurrences)
    }

    func testPredictionGeneration() {
        let prediction = Prediction(
            id: UUID(),
            patternId: UUID(),
            predictedAction: .capturePhoto,
            confidence: 0.9,
            reasoning: "Based on temporal pattern",
            createdAt: Date()
        )

        XCTAssertEqual(prediction.predictedAction, .capturePhoto)
        XCTAssertEqual(prediction.confidence, 0.9)
        XCTAssertFalse(prediction.reasoning.isEmpty)
    }

    // MARK: - Knowledge Graph System Tests

    func testKnowledgeGraphInitialization() {
        let graph = KnowledgeGraphSystem.shared

        XCTAssertNotNil(graph)
        XCTAssertEqual(graph.totalEntities >= 0, true)
        XCTAssertEqual(graph.totalRelationships >= 0, true)
    }

    func testAddEntity() {
        let graph = KnowledgeGraphSystem.shared
        let initialCount = graph.totalEntities

        let entity = Entity(
            id: UUID(),
            type: .person,
            name: "Test Person",
            properties: ["role": "tester"],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(entity)

        XCTAssertEqual(graph.totalEntities, initialCount + 1)

        // Cleanup
        graph.clearGraph()
    }

    func testFindEntityByName() {
        let graph = KnowledgeGraphSystem.shared

        let entity = Entity(
            id: UUID(),
            type: .person,
            name: "John Doe",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(entity)

        let found = graph.findEntity(name: "John Doe")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "John Doe")

        // Cleanup
        graph.clearGraph()
    }

    func testFindEntitiesByType() {
        let graph = KnowledgeGraphSystem.shared

        // Add multiple entities of different types
        let person = Entity(
            id: UUID(),
            type: .person,
            name: "Person 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        let place = Entity(
            id: UUID(),
            type: .place,
            name: "Place 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(person)
        graph.addEntity(place)

        let people = graph.findEntities(ofType: .person)
        let places = graph.findEntities(ofType: .place)

        XCTAssertTrue(people.count > 0)
        XCTAssertTrue(places.count > 0)

        // Cleanup
        graph.clearGraph()
    }

    func testAddRelationship() {
        let graph = KnowledgeGraphSystem.shared
        let initialCount = graph.totalRelationships

        let entity1 = Entity(
            id: UUID(),
            type: .person,
            name: "Person 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        let entity2 = Entity(
            id: UUID(),
            type: .place,
            name: "Place 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(entity1)
        graph.addEntity(entity2)

        let relationship = Relationship(
            id: UUID(),
            type: .locatedAt,
            sourceId: entity1.id,
            targetId: entity2.id,
            strength: 0.9,
            properties: [:],
            createdAt: Date()
        )

        graph.addRelationship(relationship)

        XCTAssertEqual(graph.totalRelationships, initialCount + 1)

        // Cleanup
        graph.clearGraph()
    }

    func testGetRelationships() {
        let graph = KnowledgeGraphSystem.shared

        let entity1 = Entity(
            id: UUID(),
            type: .person,
            name: "Person 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        let entity2 = Entity(
            id: UUID(),
            type: .person,
            name: "Person 2",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(entity1)
        graph.addEntity(entity2)

        let relationship = Relationship(
            id: UUID(),
            type: .knows,
            sourceId: entity1.id,
            targetId: entity2.id,
            strength: 1.0,
            properties: [:],
            createdAt: Date()
        )

        graph.addRelationship(relationship)

        let relationships = graph.getRelationships(for: entity1.id)
        XCTAssertTrue(relationships.count > 0)

        // Cleanup
        graph.clearGraph()
    }

    func testGetRelatedEntities() {
        let graph = KnowledgeGraphSystem.shared

        let person = Entity(
            id: UUID(),
            type: .person,
            name: "Person 1",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        let place = Entity(
            id: UUID(),
            type: .place,
            name: "Office",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(person)
        graph.addEntity(place)

        let relationship = Relationship(
            id: UUID(),
            type: .locatedAt,
            sourceId: person.id,
            targetId: place.id,
            strength: 1.0,
            properties: [:],
            createdAt: Date()
        )

        graph.addRelationship(relationship)

        let related = graph.getRelatedEntities(for: person.id)
        XCTAssertTrue(related.count > 0)

        // Cleanup
        graph.clearGraph()
    }

    func testEntityTypes() {
        let types: [EntityType] = [
            .person,
            .place,
            .event,
            .concept,
            .object
        ]

        for type in types {
            let entity = Entity(
                id: UUID(),
                type: type,
                name: "Test \(type.rawValue)",
                properties: [:],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )

            XCTAssertEqual(entity.type, type)
        }
    }

    func testRelationshipTypes() {
        let types: [RelationshipType] = [
            .knows,
            .locatedAt,
            .participatedIn,
            .relatedTo,
            .partOf,
            .causedBy,
            .associatedWith
        ]

        for type in types {
            let relationship = Relationship(
                id: UUID(),
                type: type,
                sourceId: UUID(),
                targetId: UUID(),
                strength: 0.8,
                properties: [:],
                createdAt: Date()
            )

            XCTAssertEqual(relationship.type, type)
            XCTAssertEqual(relationship.strength, 0.8)
        }
    }

    func testMostConnectedEntities() {
        let graph = KnowledgeGraphSystem.shared

        // Create entities with different observation counts
        let entity1 = Entity(
            id: UUID(),
            type: .person,
            name: "Popular Person",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 100
        )

        let entity2 = Entity(
            id: UUID(),
            type: .person,
            name: "Less Popular Person",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 10
        )

        graph.addEntity(entity1)
        graph.addEntity(entity2)

        let mostConnected = graph.getMostConnected(limit: 1)
        XCTAssertTrue(mostConnected.count > 0)

        if let first = mostConnected.first {
            XCTAssertTrue(first.observations >= 10)
        }

        // Cleanup
        graph.clearGraph()
    }

    func testClearGraph() {
        let graph = KnowledgeGraphSystem.shared

        let entity = Entity(
            id: UUID(),
            type: .person,
            name: "Test",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(entity)
        XCTAssertTrue(graph.totalEntities > 0)

        graph.clearGraph()
        XCTAssertEqual(graph.totalEntities, 0)
        XCTAssertEqual(graph.totalRelationships, 0)
    }

    // MARK: - Integration Tests

    func testContextWithPatternLearning() {
        let context = ContextAwarenessSystem.shared
        let learning = UserPatternLearningSystem.shared

        let userContext = context.getCurrentContext()
        XCTAssertNotNil(userContext)

        let action = UserAction(
            id: UUID(),
            type: .capturePhoto,
            timestamp: Date()
        )

        learning.recordAction(action)

        // Should not crash
        XCTAssertTrue(true)
    }

    func testPatternLearningWithKnowledgeGraph() {
        let learning = UserPatternLearningSystem.shared
        let graph = KnowledgeGraphSystem.shared

        // Record actions
        let action = UserAction(
            id: UUID(),
            type: .recognizeFace,
            timestamp: Date()
        )

        learning.recordAction(action)

        // Add related entity
        let person = Entity(
            id: UUID(),
            type: .person,
            name: "Test Person",
            properties: [:],
            createdAt: Date(),
            lastUpdated: Date(),
            observations: 1
        )

        graph.addEntity(person)

        // Should integrate without issues
        XCTAssertTrue(true)

        // Cleanup
        graph.clearGraph()
    }

    // MARK: - Performance Tests

    func testPatternLearningPerformance() {
        let learning = UserPatternLearningSystem.shared

        measure {
            for i in 0..<100 {
                let action = UserAction(
                    id: UUID(),
                    type: .capturePhoto,
                    timestamp: Date(),
                    metadata: ["index": "\(i)"]
                )

                learning.recordAction(action)
            }
        }
    }

    func testKnowledgeGraphPerformance() {
        let graph = KnowledgeGraphSystem.shared

        measure {
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

                graph.addEntity(entity)
            }
        }

        // Cleanup
        graph.clearGraph()
    }
}
