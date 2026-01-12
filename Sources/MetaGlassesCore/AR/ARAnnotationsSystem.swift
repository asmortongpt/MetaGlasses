import Foundation
import ARKit
import RealityKit
import Combine
import SwiftUI
import CloudKit
import simd

// MARK: - AR Annotations System
/// Comprehensive AR annotations system with virtual sticky notes, persistence, and cloud sync
@MainActor
public class ARAnnotationsSystem: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published public var annotations: [ARAnnotation] = []
    @Published public var selectedAnnotation: ARAnnotation?
    @Published public var nearbyAnnotations: [ARAnnotation] = []
    @Published public var annotationCount: Int = 0
    @Published public var isSyncing: Bool = false

    // MARK: - Private Properties
    private var arSession: ARSession
    private var annotationAnchors: [UUID: ARAnchor] = [:]
    private var annotationEntities: [UUID: AnnotationEntity] = [:]
    private var cancellables = Set<AnyCancellable>()

    // CloudKit
    private let cloudContainer = CKContainer.default()
    private var cloudDatabase: CKDatabase?

    // Persistence
    private let userDefaults = UserDefaults.standard
    private let annotationsKey = "com.metaglasses.ar.annotations"

    // Search index
    private var searchIndex: [String: [UUID]] = [:]

    // MARK: - Data Models

    public struct ARAnnotation: Identifiable, Codable {
        public let id: UUID
        public var title: String
        public var content: String
        public var type: AnnotationType
        public let transform: ARKitIntegration.CodableTransform
        public let worldPosition: SIMD3<Float>
        public let createdAt: Date
        public var updatedAt: Date
        public var createdBy: String
        public var tags: [String]
        public var color: AnnotationColor
        public var isShared: Bool
        public var attachments: [AttachmentInfo]

        public init(
            id: UUID = UUID(),
            title: String,
            content: String,
            type: AnnotationType,
            transform: simd_float4x4,
            worldPosition: SIMD3<Float>,
            createdBy: String,
            tags: [String] = [],
            color: AnnotationColor = .yellow
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.type = type
            self.transform = ARKitIntegration.CodableTransform(transform: transform)
            self.worldPosition = worldPosition
            self.createdAt = Date()
            self.updatedAt = Date()
            self.createdBy = createdBy
            self.tags = tags
            self.color = color
            self.isShared = false
            self.attachments = []
        }

        public enum AnnotationType: String, Codable {
            case note = "Note"
            case reminder = "Reminder"
            case measurement = "Measurement"
            case photo = "Photo"
            case voice = "Voice"
            case drawing = "Drawing"
            case waypoint = "Waypoint"
        }

        public enum AnnotationColor: String, Codable {
            case yellow = "Yellow"
            case blue = "Blue"
            case green = "Green"
            case red = "Red"
            case purple = "Purple"
            case orange = "Orange"

            public var uiColor: UIColor {
                switch self {
                case .yellow: return .systemYellow
                case .blue: return .systemBlue
                case .green: return .systemGreen
                case .red: return .systemRed
                case .purple: return .systemPurple
                case .orange: return .systemOrange
                }
            }
        }

        public struct AttachmentInfo: Codable {
            public let id: UUID
            public let type: AttachmentType
            public let url: String
            public let thumbnailURL: String?

            public enum AttachmentType: String, Codable {
                case image
                case video
                case audio
                case document
            }
        }
    }

    private class AnnotationEntity {
        let anchor: ARAnchor
        var entity: Entity?
        var textEntity: ModelEntity?
        var billboardEntity: ModelEntity?

        init(anchor: ARAnchor) {
            self.anchor = anchor
        }
    }

    // MARK: - Initialization

    public init(arSession: ARSession) {
        self.arSession = arSession
        super.init()
        setupCloudKit()
        loadAnnotationsFromDisk()
    }

    private func setupCloudKit() {
        cloudDatabase = cloudContainer.privateCloudDatabase
    }

    // MARK: - Annotation Management

    public func createAnnotation(
        title: String,
        content: String,
        type: ARAnnotation.AnnotationType,
        at position: SIMD3<Float>,
        tags: [String] = [],
        color: ARAnnotation.AnnotationColor = .yellow
    ) -> ARAnnotation? {

        // Create transform at position
        var transform = matrix_identity_float4x4
        transform.columns.3 = simd_float4(position.x, position.y, position.z, 1.0)

        // Orient towards camera
        if let cameraTransform = arSession.currentFrame?.camera.transform {
            let toCamera = normalize(cameraTransform.position - position)
            let right = normalize(cross(simd_float3(0, 1, 0), toCamera))
            let up = cross(toCamera, right)

            transform.columns.0 = simd_float4(right, 0)
            transform.columns.1 = simd_float4(up, 0)
            transform.columns.2 = simd_float4(toCamera, 0)
        }

        let annotation = ARAnnotation(
            title: title,
            content: content,
            type: type,
            transform: transform,
            worldPosition: position,
            createdBy: "User",
            tags: tags,
            color: color
        )

        annotations.append(annotation)
        annotationCount = annotations.count

        // Create AR anchor
        let anchor = ARAnchor(name: "annotation_\(annotation.id.uuidString)", transform: transform)
        arSession.add(anchor: anchor)
        annotationAnchors[annotation.id] = anchor

        // Update search index
        updateSearchIndex(for: annotation)

        // Save to disk
        saveAnnotationsToDisk()

        print("📝 Created annotation: \(title) at \(position)")
        return annotation
    }

    public func updateAnnotation(
        id: UUID,
        title: String? = nil,
        content: String? = nil,
        tags: [String]? = nil,
        color: ARAnnotation.AnnotationColor? = nil
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = annotations[index]

        if let title = title {
            annotation.title = title
        }
        if let content = content {
            annotation.content = content
        }
        if let tags = tags {
            annotation.tags = tags
        }
        if let color = color {
            annotation.color = color
        }

        annotation.updatedAt = Date()
        annotations[index] = annotation

        // Update search index
        updateSearchIndex(for: annotation)

        // Save to disk
        saveAnnotationsToDisk()

        print("✏️ Updated annotation: \(annotation.title)")
    }

    public func deleteAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        annotationCount = annotations.count

        // Remove AR anchor
        if let anchor = annotationAnchors[id] {
            arSession.remove(anchor: anchor)
            annotationAnchors.removeValue(forKey: id)
        }

        // Remove from search index
        removeFromSearchIndex(id: id)

        // Save to disk
        saveAnnotationsToDisk()

        print("🗑️ Deleted annotation: \(id)")
    }

    // MARK: - Spatial Queries

    public func getAnnotationsNearPosition(_ position: SIMD3<Float>, radius: Float = 2.0) -> [ARAnnotation] {
        return annotations.filter { annotation in
            simd_distance(annotation.worldPosition, position) <= radius
        }.sorted { a1, a2 in
            simd_distance(a1.worldPosition, position) < simd_distance(a2.worldPosition, position)
        }
    }

    public func updateNearbyAnnotations(cameraPosition: SIMD3<Float>) {
        nearbyAnnotations = getAnnotationsNearPosition(cameraPosition, radius: 5.0)
    }

    public func getAnnotationsByType(_ type: ARAnnotation.AnnotationType) -> [ARAnnotation] {
        return annotations.filter { $0.type == type }
    }

    public func getAnnotationsByTag(_ tag: String) -> [ARAnnotation] {
        return annotations.filter { $0.tags.contains(tag) }
    }

    // MARK: - Search

    public func searchAnnotations(query: String) -> [ARAnnotation] {
        let lowercasedQuery = query.lowercased()

        // First check search index
        if let indexedIds = searchIndex[lowercasedQuery] {
            return annotations.filter { indexedIds.contains($0.id) }
        }

        // Fallback to full text search
        return annotations.filter { annotation in
            annotation.title.lowercased().contains(lowercasedQuery) ||
            annotation.content.lowercased().contains(lowercasedQuery) ||
            annotation.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }

    private func updateSearchIndex(for annotation: ARAnnotation) {
        let searchableText = "\(annotation.title) \(annotation.content) \(annotation.tags.joined(separator: " "))"
        let words = searchableText.lowercased().components(separatedBy: .whitespacesAndNewlines)

        for word in words where !word.isEmpty {
            if searchIndex[word] == nil {
                searchIndex[word] = []
            }
            if !searchIndex[word]!.contains(annotation.id) {
                searchIndex[word]!.append(annotation.id)
            }
        }
    }

    private func removeFromSearchIndex(id: UUID) {
        for key in searchIndex.keys {
            searchIndex[key]?.removeAll { $0 == id }
        }
    }

    // MARK: - Persistence

    private func saveAnnotationsToDisk() {
        do {
            let data = try JSONEncoder().encode(annotations)
            userDefaults.set(data, forKey: annotationsKey)
            print("💾 Saved \(annotations.count) annotations to disk")
        } catch {
            print("❌ Failed to save annotations: \(error)")
        }
    }

    private func loadAnnotationsFromDisk() {
        guard let data = userDefaults.data(forKey: annotationsKey) else {
            print("ℹ️ No saved annotations found")
            return
        }

        do {
            annotations = try JSONDecoder().decode([ARAnnotation].self, from: data)
            annotationCount = annotations.count

            // Rebuild search index
            for annotation in annotations {
                updateSearchIndex(for: annotation)
            }

            print("📂 Loaded \(annotations.count) annotations from disk")
        } catch {
            print("❌ Failed to load annotations: \(error)")
        }
    }

    // MARK: - CloudKit Sync

    public func shareAnnotation(id: UUID) async throws {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            throw AnnotationError.annotationNotFound
        }

        var annotation = annotations[index]
        annotation.isShared = true
        annotations[index] = annotation

        try await syncAnnotationToCloud(annotation)

        print("☁️ Shared annotation: \(annotation.title)")
    }

    public func syncAllToCloud() async throws {
        isSyncing = true
        defer { isSyncing = false }

        guard let database = cloudDatabase else {
            throw AnnotationError.cloudKitNotAvailable
        }

        for annotation in annotations where annotation.isShared {
            try await syncAnnotationToCloud(annotation)
        }

        print("☁️ Synced \(annotations.count) annotations to CloudKit")
    }

    private func syncAnnotationToCloud(_ annotation: ARAnnotation) async throws {
        guard let database = cloudDatabase else {
            throw AnnotationError.cloudKitNotAvailable
        }

        let record = CKRecord(recordType: "ARAnnotation")
        record["id"] = annotation.id.uuidString
        record["title"] = annotation.title
        record["content"] = annotation.content
        record["type"] = annotation.type.rawValue
        record["positionX"] = annotation.worldPosition.x
        record["positionY"] = annotation.worldPosition.y
        record["positionZ"] = annotation.worldPosition.z
        record["createdBy"] = annotation.createdBy
        record["tags"] = annotation.tags
        record["color"] = annotation.color.rawValue
        record["createdAt"] = annotation.createdAt
        record["updatedAt"] = annotation.updatedAt

        try await database.save(record)
    }

    public func fetchSharedAnnotations() async throws {
        isSyncing = true
        defer { isSyncing = false }

        guard let database = cloudDatabase else {
            throw AnnotationError.cloudKitNotAvailable
        }

        let query = CKQuery(recordType: "ARAnnotation", predicate: NSPredicate(value: true))
        let results = try await database.records(matching: query)

        var fetchedAnnotations: [ARAnnotation] = []

        for result in results.matchResults {
            let record = try result.1.get()

            guard let idString = record["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = record["title"] as? String,
                  let content = record["content"] as? String,
                  let typeString = record["type"] as? String,
                  let type = ARAnnotation.AnnotationType(rawValue: typeString),
                  let posX = record["positionX"] as? Float,
                  let posY = record["positionY"] as? Float,
                  let posZ = record["positionZ"] as? Float else {
                continue
            }

            let position = SIMD3<Float>(posX, posY, posZ)
            let createdBy = (record["createdBy"] as? String) ?? "Unknown"
            let tags = (record["tags"] as? [String]) ?? []
            let colorString = (record["color"] as? String) ?? "yellow"
            let color = ARAnnotation.AnnotationColor(rawValue: colorString) ?? .yellow

            var transform = matrix_identity_float4x4
            transform.columns.3 = simd_float4(posX, posY, posZ, 1.0)

            var annotation = ARAnnotation(
                id: id,
                title: title,
                content: content,
                type: type,
                transform: transform,
                worldPosition: position,
                createdBy: createdBy,
                tags: tags,
                color: color
            )

            annotation.isShared = true

            if let createdAt = record["createdAt"] as? Date {
                annotation = ARAnnotation(
                    id: annotation.id,
                    title: annotation.title,
                    content: annotation.content,
                    type: annotation.type,
                    transform: annotation.transform.simdTransform,
                    worldPosition: annotation.worldPosition,
                    createdBy: annotation.createdBy,
                    tags: annotation.tags,
                    color: annotation.color
                )
            }

            fetchedAnnotations.append(annotation)
        }

        // Merge with existing annotations (avoid duplicates)
        for fetchedAnnotation in fetchedAnnotations {
            if !annotations.contains(where: { $0.id == fetchedAnnotation.id }) {
                annotations.append(fetchedAnnotation)
                updateSearchIndex(for: fetchedAnnotation)
            }
        }

        annotationCount = annotations.count
        saveAnnotationsToDisk()

        print("☁️ Fetched \(fetchedAnnotations.count) shared annotations from CloudKit")
    }

    // MARK: - Bulk Operations

    public func deleteAllAnnotations() {
        for annotation in annotations {
            if let anchor = annotationAnchors[annotation.id] {
                arSession.remove(anchor: anchor)
            }
        }

        annotations.removeAll()
        annotationAnchors.removeAll()
        annotationEntities.removeAll()
        searchIndex.removeAll()
        annotationCount = 0

        saveAnnotationsToDisk()

        print("🗑️ Deleted all annotations")
    }

    public func exportAnnotations() -> Data? {
        do {
            let data = try JSONEncoder().encode(annotations)
            print("📤 Exported \(annotations.count) annotations")
            return data
        } catch {
            print("❌ Failed to export annotations: \(error)")
            return nil
        }
    }

    public func importAnnotations(from data: Data) throws {
        let importedAnnotations = try JSONDecoder().decode([ARAnnotation].self, from: data)

        for annotation in importedAnnotations {
            if !annotations.contains(where: { $0.id == annotation.id }) {
                annotations.append(annotation)
                updateSearchIndex(for: annotation)
            }
        }

        annotationCount = annotations.count
        saveAnnotationsToDisk()

        print("📥 Imported \(importedAnnotations.count) annotations")
    }

    // MARK: - Statistics

    public func getAnnotationStatistics() -> AnnotationStatistics {
        let typeGroups = Dictionary(grouping: annotations, by: { $0.type })
        let colorGroups = Dictionary(grouping: annotations, by: { $0.color })

        return AnnotationStatistics(
            totalCount: annotations.count,
            sharedCount: annotations.filter { $0.isShared }.count,
            typeBreakdown: typeGroups.mapValues { $0.count },
            colorBreakdown: colorGroups.mapValues { $0.count },
            oldestAnnotation: annotations.min { $0.createdAt < $1.createdAt }?.createdAt,
            newestAnnotation: annotations.max { $0.createdAt < $1.createdAt }?.createdAt
        )
    }

    public struct AnnotationStatistics {
        public let totalCount: Int
        public let sharedCount: Int
        public let typeBreakdown: [ARAnnotation.AnnotationType: Int]
        public let colorBreakdown: [ARAnnotation.AnnotationColor: Int]
        public let oldestAnnotation: Date?
        public let newestAnnotation: Date?
    }
}

// MARK: - Errors

public enum AnnotationError: Error {
    case annotationNotFound
    case cloudKitNotAvailable
    case invalidData
}

// MARK: - SIMD Extensions

extension simd_float4x4 {
    var position: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
