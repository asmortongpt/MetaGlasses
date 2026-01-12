import Foundation

/// Knowledge Graph System
/// Represents relationships between people, places, events, and concepts
@MainActor
public class KnowledgeGraphSystem: ObservableObject {

    // MARK: - Singleton
    public static let shared = KnowledgeGraphSystem()

    // MARK: - Published Properties
    @Published public var entities: [Entity] = []
    @Published public var relationships: [Relationship] = []
    @Published public var totalEntities = 0
    @Published public var totalRelationships = 0

    // MARK: - Properties
    private var entityIndex: [String: Entity] = [:]
    private var relationshipIndex: [String: [Relationship]] = [:]

    // MARK: - Initialization
    private init() {
        print("🕸️ KnowledgeGraphSystem initialized")
        loadGraph()
    }

    // MARK: - Entity Management

    /// Add or update an entity
    public func addEntity(_ entity: Entity) {
        if let existing = entityIndex[entity.id.uuidString] {
            // Update existing entity
            var updated = existing
            updated.lastUpdated = Date()
            updated.observations += 1

            // Merge properties
            updated.properties.merge(entity.properties) { _, new in new }

            entityIndex[entity.id.uuidString] = updated

            // Update in array
            if let index = entities.firstIndex(where: { $0.id == entity.id }) {
                entities[index] = updated
            }
        } else {
            // Add new entity
            entityIndex[entity.id.uuidString] = entity
            entities.append(entity)
            totalEntities += 1
        }

        saveGraph()
    }

    /// Find entity by name
    public func findEntity(name: String) -> Entity? {
        return entities.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Find entities by type
    public func findEntities(ofType type: EntityType) -> [Entity] {
        return entities.filter { $0.type == type }
    }

    // MARK: - Relationship Management

    /// Add relationship between entities
    public func addRelationship(_ relationship: Relationship) {
        // Add to relationships array
        relationships.append(relationship)
        totalRelationships += 1

        // Index by source entity
        let sourceKey = relationship.sourceId.uuidString
        if relationshipIndex[sourceKey] != nil {
            relationshipIndex[sourceKey]?.append(relationship)
        } else {
            relationshipIndex[sourceKey] = [relationship]
        }

        // Update entity observation counts
        if let sourceIndex = entities.firstIndex(where: { $0.id == relationship.sourceId }) {
            entities[sourceIndex].observations += 1
        }
        if let targetIndex = entities.firstIndex(where: { $0.id == relationship.targetId }) {
            entities[targetIndex].observations += 1
        }

        saveGraph()
    }

    /// Find relationships for entity
    public func getRelationships(for entityId: UUID) -> [Relationship] {
        let sourceRels = relationshipIndex[entityId.uuidString] ?? []

        let targetRels = relationships.filter { $0.targetId == entityId }

        return sourceRels + targetRels
    }

    /// Find related entities
    public func getRelatedEntities(for entityId: UUID, type: RelationshipType? = nil) -> [Entity] {
        let rels = getRelationships(for: entityId)

        var relatedIds: [UUID] = []

        for rel in rels {
            if let type = type, rel.type != type {
                continue
            }

            if rel.sourceId == entityId {
                relatedIds.append(rel.targetId)
            } else {
                relatedIds.append(rel.sourceId)
            }
        }

        return entities.filter { relatedIds.contains($0.id) }
    }

    // MARK: - Graph Queries

    /// Find path between two entities
    public func findPath(from sourceId: UUID, to targetId: UUID, maxDepth: Int = 3) -> [Entity]? {
        var visited = Set<UUID>()
        var queue: [(UUID, [Entity])] = [(sourceId, [])]

        while !queue.isEmpty {
            let (currentId, path) = queue.removeFirst()

            if currentId == targetId {
                return path
            }

            if path.count >= maxDepth {
                continue
            }

            visited.insert(currentId)

            let related = getRelatedEntities(for: currentId)

            for entity in related {
                if !visited.contains(entity.id) {
                    queue.append((entity.id, path + [entity]))
                }
            }
        }

        return nil
    }

    /// Get entity clusters (connected components)
    public func getClusters() -> [[Entity]] {
        var visited = Set<UUID>()
        var clusters: [[Entity]] = []

        for entity in entities {
            if visited.contains(entity.id) {
                continue
            }

            var cluster: [Entity] = []
            var queue: [UUID] = [entity.id]

            while !queue.isEmpty {
                let currentId = queue.removeFirst()

                if visited.contains(currentId) {
                    continue
                }

                visited.insert(currentId)

                if let currentEntity = entities.first(where: { $0.id == currentId }) {
                    cluster.append(currentEntity)
                }

                let related = getRelatedEntities(for: currentId)
                queue.append(contentsOf: related.map { $0.id })
            }

            if !cluster.isEmpty {
                clusters.append(cluster)
            }
        }

        return clusters
    }

    /// Get most connected entities
    public func getMostConnected(limit: Int = 10) -> [Entity] {
        return entities
            .sorted { $0.observations > $1.observations }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Automatic Learning

    /// Learn from photo metadata
    public func learnFromPhoto(metadata: PhotoMetadata, analysis: String) {
        // Extract entities from analysis using simple keyword matching
        // In production, would use NLP/NER

        // Check for people mentions
        if analysis.lowercased().contains("person") || analysis.lowercased().contains("people") {
            let personEntity = Entity(
                id: UUID(),
                type: .person,
                name: "Unknown Person",
                properties: ["detected_in": "photo"],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            addEntity(personEntity)
        }

        // Check for location
        if let location = metadata.location, let placeName = location.placeName {
            let placeEntity = Entity(
                id: UUID(),
                type: .place,
                name: placeName,
                properties: [
                    "latitude": "\(location.coordinate.latitude)",
                    "longitude": "\(location.coordinate.longitude)"
                ],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            addEntity(placeEntity)
        }

        // Check for events
        if let creationDate = metadata.creationDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium

            let eventEntity = Entity(
                id: UUID(),
                type: .event,
                name: "Photo taken on \(dateFormatter.string(from: creationDate))",
                properties: ["timestamp": "\(creationDate.timeIntervalSince1970)"],
                createdAt: Date(),
                lastUpdated: Date(),
                observations: 1
            )
            addEntity(eventEntity)
        }
    }

    /// Learn from conversation
    public func learnFromConversation(text: String) {
        // Extract entities from conversation
        // Simple keyword-based extraction (in production, use NLP)

        let words = text.split(separator: " ")

        // Check for named entities (capitalized words)
        for word in words {
            if word.first?.isUppercase == true && word.count > 2 {
                let concept = Entity(
                    id: UUID(),
                    type: .concept,
                    name: String(word),
                    properties: ["source": "conversation"],
                    createdAt: Date(),
                    lastUpdated: Date(),
                    observations: 1
                )
                addEntity(concept)
            }
        }
    }

    /// Infer relationships from co-occurrence
    public func inferRelationships() {
        // Find entities that co-occur frequently in the same context

        var coOccurrences: [String: Int] = [:]

        // Group entities by creation time (within 1 hour = same context)
        let groupedByTime = Dictionary(grouping: entities) { entity in
            Calendar.current.dateComponents([.year, .month, .day, .hour], from: entity.createdAt)
        }

        for (_, group) in groupedByTime {
            if group.count < 2 { continue }

            // Create relationships between entities in same group
            for i in 0..<group.count {
                for j in (i+1)..<group.count {
                    let entity1 = group[i]
                    let entity2 = group[j]

                    // Only create relationship if confidence is high
                    let key = "\(entity1.id.uuidString)-\(entity2.id.uuidString)"

                    coOccurrences[key, default: 0] += 1

                    if coOccurrences[key] ?? 0 >= 3 {
                        let relationship = Relationship(
                            id: UUID(),
                            type: .associatedWith,
                            sourceId: entity1.id,
                            targetId: entity2.id,
                            strength: min(1.0, Double(coOccurrences[key] ?? 0) / 10.0),
                            properties: ["inferred": "true"],
                            createdAt: Date()
                        )

                        addRelationship(relationship)
                    }
                }
            }
        }

        print("🔗 Inferred \(coOccurrences.count) potential relationships")
    }

    // MARK: - Persistence

    private var entitiesFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("knowledge_graph_entities.json")
    }

    private var relationshipsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("knowledge_graph_relationships.json")
    }

    private func saveGraph() {
        // Save entities
        if let data = try? JSONEncoder().encode(entities) {
            try? data.write(to: entitiesFileURL)
        }

        // Save relationships
        if let data = try? JSONEncoder().encode(relationships) {
            try? data.write(to: relationshipsFileURL)
        }
    }

    private func loadGraph() {
        // Load entities
        if let data = try? Data(contentsOf: entitiesFileURL),
           let loadedEntities = try? JSONDecoder().decode([Entity].self, from: data) {
            entities = loadedEntities
            totalEntities = entities.count

            // Rebuild index
            for entity in entities {
                entityIndex[entity.id.uuidString] = entity
            }

            print("📚 Loaded \(totalEntities) entities")
        }

        // Load relationships
        if let data = try? Data(contentsOf: relationshipsFileURL),
           let loadedRelationships = try? JSONDecoder().decode([Relationship].self, from: data) {
            relationships = loadedRelationships
            totalRelationships = relationships.count

            // Rebuild index
            for rel in relationships {
                let key = rel.sourceId.uuidString
                if relationshipIndex[key] != nil {
                    relationshipIndex[key]?.append(rel)
                } else {
                    relationshipIndex[key] = [rel]
                }
            }

            print("🔗 Loaded \(totalRelationships) relationships")
        }
    }

    /// Clear all data
    public func clearGraph() {
        entities.removeAll()
        relationships.removeAll()
        entityIndex.removeAll()
        relationshipIndex.removeAll()
        totalEntities = 0
        totalRelationships = 0

        saveGraph()

        print("🗑️ Cleared knowledge graph")
    }
}

// MARK: - Models

public struct Entity: Codable, Identifiable {
    public let id: UUID
    public let type: EntityType
    public var name: String
    public var properties: [String: String]
    public let createdAt: Date
    public var lastUpdated: Date
    public var observations: Int

    public init(id: UUID, type: EntityType, name: String, properties: [String: String], createdAt: Date, lastUpdated: Date, observations: Int) {
        self.id = id
        self.type = type
        self.name = name
        self.properties = properties
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.observations = observations
    }
}

public enum EntityType: String, Codable {
    case person
    case place
    case event
    case concept
    case object
}

public struct Relationship: Codable, Identifiable {
    public let id: UUID
    public let type: RelationshipType
    public let sourceId: UUID
    public let targetId: UUID
    public var strength: Double // 0.0 to 1.0
    public var properties: [String: String]
    public let createdAt: Date

    public init(id: UUID, type: RelationshipType, sourceId: UUID, targetId: UUID, strength: Double, properties: [String: String], createdAt: Date) {
        self.id = id
        self.type = type
        self.sourceId = sourceId
        self.targetId = targetId
        self.strength = strength
        self.properties = properties
        self.createdAt = createdAt
    }
}

public enum RelationshipType: String, Codable {
    case knows           // Person knows Person
    case locatedAt       // Entity at Place
    case participatedIn  // Person participated in Event
    case relatedTo       // Generic relationship
    case partOf          // Entity is part of Entity
    case causedBy        // Event caused by Entity
    case associatedWith  // Generic association
}
