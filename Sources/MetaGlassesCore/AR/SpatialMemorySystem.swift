import Foundation
import ARKit
import CoreLocation
import Combine
import simd
import CloudKit

// MARK: - Spatial Memory System
/// Advanced spatial memory system with 3D location tagging, clustering, and indoor positioning
@MainActor
public class SpatialMemorySystem: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published public var memories: [SpatialMemory] = []
    @Published public var memoryClusters: [MemoryCluster] = []
    @Published public var currentLocation: SpatialLocation?
    @Published public var nearbyMemories: [SpatialMemory] = []
    @Published public var indoorLocation: IndoorLocation?

    // MARK: - Private Properties
    private var locationManager: CLLocationManager
    private var arKitIntegration: ARKitIntegration?
    private var memoryIndex: [String: SpatialMemory] = [:]
    private var spatialTree: SpatialKDTree
    private var cancellables = Set<AnyCancellable>()

    // Indoor positioning
    private var indoorMap: IndoorMap?
    private var lastKnownARTransform: simd_float4x4?

    // CloudKit for shared memories
    private let cloudContainer = CKContainer.default()
    private var cloudDatabase: CKDatabase?

    // MARK: - Data Models

    public struct SpatialMemory: Identifiable, Codable {
        public let id: UUID
        public let title: String
        public let content: String
        public let location: SpatialLocation
        public let arAnchor: ARKitIntegration.CodableTransform?
        public let timestamp: Date
        public var tags: [String]
        public var mediaURLs: [String]
        public var visitCount: Int
        public var lastVisited: Date?

        public init(
            id: UUID = UUID(),
            title: String,
            content: String,
            location: SpatialLocation,
            arAnchor: simd_float4x4? = nil,
            tags: [String] = [],
            mediaURLs: [String] = []
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.location = location
            self.arAnchor = arAnchor.map { ARKitIntegration.CodableTransform(transform: $0) }
            self.timestamp = Date()
            self.tags = tags
            self.mediaURLs = mediaURLs
            self.visitCount = 0
            self.lastVisited = nil
        }
    }

    public struct SpatialLocation: Codable {
        public let coordinate: CLLocationCoordinate2D
        public let altitude: Double
        public let horizontalAccuracy: Double
        public let verticalAccuracy: Double
        public let arPosition: SIMD3<Float>?
        public let floor: Int?
        public let venue: String?

        public init(
            coordinate: CLLocationCoordinate2D,
            altitude: Double,
            horizontalAccuracy: Double = 10.0,
            verticalAccuracy: Double = 5.0,
            arPosition: SIMD3<Float>? = nil,
            floor: Int? = nil,
            venue: String? = nil
        ) {
            self.coordinate = coordinate
            self.altitude = altitude
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.arPosition = arPosition
            self.floor = floor
            self.venue = venue
        }

        public func distance(to other: SpatialLocation) -> Double {
            let location1 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let location2 = CLLocation(latitude: other.coordinate.latitude, longitude: other.coordinate.longitude)
            return location1.distance(from: location2)
        }
    }

    public struct MemoryCluster: Identifiable {
        public let id: UUID
        public let centerLocation: SpatialLocation
        public let radius: Double
        public var memories: [SpatialMemory]
        public let name: String?

        public var memoryCount: Int { memories.count }

        public init(centerLocation: SpatialLocation, radius: Double, memories: [SpatialMemory], name: String? = nil) {
            self.id = UUID()
            self.centerLocation = centerLocation
            self.radius = radius
            self.memories = memories
            self.name = name
        }
    }

    public struct IndoorLocation: Codable {
        public let venue: String
        public let building: String
        public let floor: Int
        public let room: String?
        public let arPosition: SIMD3<Float>
        public let confidence: Double
        public let timestamp: Date

        public init(venue: String, building: String, floor: Int, room: String?, arPosition: SIMD3<Float>, confidence: Double) {
            self.venue = venue
            self.building = building
            self.floor = floor
            self.room = room
            self.arPosition = arPosition
            self.confidence = confidence
            self.timestamp = Date()
        }
    }

    // MARK: - Initialization

    public override init() {
        self.locationManager = CLLocationManager()
        self.spatialTree = SpatialKDTree()
        super.init()
        setupLocationManager()
        setupCloudKit()
    }

    public convenience init(arKitIntegration: ARKitIntegration) {
        self.init()
        self.arKitIntegration = arKitIntegration
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0 // 1 meter
        locationManager.requestWhenInUseAuthorization()
    }

    private func setupCloudKit() {
        cloudDatabase = cloudContainer.privateCloudDatabase
    }

    // MARK: - Location Tracking

    public func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        print("📍 Started spatial memory tracking")
    }

    public func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        print("⏹️ Stopped spatial memory tracking")
    }

    // MARK: - Memory Management

    public func createMemory(
        title: String,
        content: String,
        tags: [String] = [],
        mediaURLs: [String] = []
    ) -> SpatialMemory? {
        guard let location = currentLocation else {
            print("⚠️ Cannot create memory: no location available")
            return nil
        }

        let arAnchor = arKitIntegration?.getCurrentCameraTransform()

        let memory = SpatialMemory(
            title: title,
            content: content,
            location: location,
            arAnchor: arAnchor,
            tags: tags,
            mediaURLs: mediaURLs
        )

        memories.append(memory)
        memoryIndex[memory.id.uuidString] = memory
        spatialTree.insert(memory)

        updateClusters()
        updateNearbyMemories()

        print("✅ Created spatial memory: \(title) at \(location.coordinate)")
        return memory
    }

    public func updateMemory(id: UUID, title: String? = nil, content: String? = nil, tags: [String]? = nil) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }

        var memory = memories[index]
        if let title = title { memory = SpatialMemory(id: memory.id, title: title, content: memory.content, location: memory.location, arAnchor: memory.arAnchor?.simdTransform, tags: memory.tags, mediaURLs: memory.mediaURLs) }
        if let content = content { memory = SpatialMemory(id: memory.id, title: memory.title, content: content, location: memory.location, arAnchor: memory.arAnchor?.simdTransform, tags: memory.tags, mediaURLs: memory.mediaURLs) }
        if let tags = tags { memory = SpatialMemory(id: memory.id, title: memory.title, content: memory.content, location: memory.location, arAnchor: memory.arAnchor?.simdTransform, tags: tags, mediaURLs: memory.mediaURLs) }

        memories[index] = memory
        memoryIndex[memory.id.uuidString] = memory
        updateClusters()
    }

    public func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        memoryIndex.removeValue(forKey: id.uuidString)
        spatialTree.remove(id: id)
        updateClusters()
        updateNearbyMemories()
    }

    // MARK: - Spatial Queries

    public func getMemoriesNearLocation(_ location: SpatialLocation, radius: Double = 100.0) -> [SpatialMemory] {
        return memories.filter { memory in
            memory.location.distance(to: location) <= radius
        }.sorted { memory1, memory2 in
            memory1.location.distance(to: location) < memory2.location.distance(to: location)
        }
    }

    public func getMemoriesInRegion(center: CLLocationCoordinate2D, radiusInMeters: Double) -> [SpatialMemory] {
        let centerLocation = SpatialLocation(
            coordinate: center,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 5
        )
        return getMemoriesNearLocation(centerLocation, radius: radiusInMeters)
    }

    public func searchMemories(query: String) -> [SpatialMemory] {
        let lowercasedQuery = query.lowercased()
        return memories.filter { memory in
            memory.title.lowercased().contains(lowercasedQuery) ||
            memory.content.lowercased().contains(lowercasedQuery) ||
            memory.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }

    // MARK: - Clustering

    private func updateClusters() {
        guard memories.count > 0 else {
            memoryClusters = []
            return
        }

        // DBSCAN clustering algorithm
        let clusterRadius = 50.0 // 50 meters
        let minClusterSize = 3

        var clustered = Set<UUID>()
        var clusters: [MemoryCluster] = []

        for memory in memories {
            guard !clustered.contains(memory.id) else { continue }

            let nearbyMemories = getMemoriesNearLocation(memory.location, radius: clusterRadius)
            guard nearbyMemories.count >= minClusterSize else { continue }

            // Calculate cluster center
            let avgLat = nearbyMemories.map { $0.location.coordinate.latitude }.reduce(0, +) / Double(nearbyMemories.count)
            let avgLon = nearbyMemories.map { $0.location.coordinate.longitude }.reduce(0, +) / Double(nearbyMemories.count)
            let avgAlt = nearbyMemories.map { $0.location.altitude }.reduce(0, +) / Double(nearbyMemories.count)

            let clusterCenter = SpatialLocation(
                coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                altitude: avgAlt
            )

            let cluster = MemoryCluster(
                centerLocation: clusterCenter,
                radius: clusterRadius,
                memories: nearbyMemories,
                name: generateClusterName(for: nearbyMemories)
            )

            clusters.append(cluster)
            nearbyMemories.forEach { clustered.insert($0.id) }
        }

        memoryClusters = clusters
    }

    private func generateClusterName(for memories: [SpatialMemory]) -> String {
        // Find most common tag
        var tagCounts: [String: Int] = [:]
        memories.forEach { memory in
            memory.tags.forEach { tag in
                tagCounts[tag, default: 0] += 1
            }
        }

        if let mostCommonTag = tagCounts.max(by: { $0.value < $1.value })?.key {
            return "\(mostCommonTag) (\(memories.count) memories)"
        }

        return "Memory Cluster (\(memories.count) memories)"
    }

    // MARK: - Nearby Memories

    private func updateNearbyMemories() {
        guard let location = currentLocation else {
            nearbyMemories = []
            return
        }

        nearbyMemories = getMemoriesNearLocation(location, radius: 50.0)
            .prefix(10)
            .map { memory in
                var updatedMemory = memory
                updatedMemory.visitCount += 1
                updatedMemory.lastVisited = Date()
                return updatedMemory
            }
    }

    // MARK: - Indoor Positioning

    public func updateIndoorLocation(venue: String, building: String, floor: Int, room: String? = nil) {
        guard let arPosition = arKitIntegration?.getCurrentCameraPosition() else {
            print("⚠️ Cannot determine indoor location without AR position")
            return
        }

        indoorLocation = IndoorLocation(
            venue: venue,
            building: building,
            floor: floor,
            room: room,
            arPosition: arPosition,
            confidence: 0.95
        )

        print("🏢 Indoor location: \(building), Floor \(floor)")
    }

    public func detectIndoorLocationChange() {
        guard let currentARPosition = arKitIntegration?.getCurrentCameraPosition(),
              let lastPosition = lastKnownARTransform?.position else {
            lastKnownARTransform = arKitIntegration?.getCurrentCameraTransform()
            return
        }

        let distance = simd_distance(currentARPosition, lastPosition)

        // Detect floor changes (vertical movement > 3 meters)
        if abs(currentARPosition.y - lastPosition.y) > 3.0 {
            if let indoor = indoorLocation {
                let newFloor = indoor.floor + (currentARPosition.y > lastPosition.y ? 1 : -1)
                updateIndoorLocation(venue: indoor.venue, building: indoor.building, floor: newFloor, room: indoor.room)
            }
        }

        // Detect room changes (horizontal movement > 10 meters)
        if distance > 10.0 {
            print("🚶 Significant movement detected: \(distance)m")
        }

        lastKnownARTransform = arKitIntegration?.getCurrentCameraTransform()
    }

    // MARK: - CloudKit Sync

    public func syncMemoriesToCloud() async throws {
        guard let database = cloudDatabase else {
            throw SpatialMemoryError.cloudKitNotAvailable
        }

        for memory in memories {
            let record = CKRecord(recordType: "SpatialMemory")
            record["id"] = memory.id.uuidString
            record["title"] = memory.title
            record["content"] = memory.content
            record["latitude"] = memory.location.coordinate.latitude
            record["longitude"] = memory.location.coordinate.longitude
            record["altitude"] = memory.location.altitude
            record["tags"] = memory.tags
            record["timestamp"] = memory.timestamp

            try await database.save(record)
        }

        print("☁️ Synced \(memories.count) memories to CloudKit")
    }

    public func fetchMemoriesFromCloud() async throws {
        guard let database = cloudDatabase else {
            throw SpatialMemoryError.cloudKitNotAvailable
        }

        let query = CKQuery(recordType: "SpatialMemory", predicate: NSPredicate(value: true))
        let results = try await database.records(matching: query)

        for result in results.matchResults {
            let record = try result.1.get()

            guard let idString = record["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = record["title"] as? String,
                  let content = record["content"] as? String,
                  let latitude = record["latitude"] as? Double,
                  let longitude = record["longitude"] as? Double,
                  let altitude = record["altitude"] as? Double else {
                continue
            }

            let location = SpatialLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: altitude
            )

            let tags = (record["tags"] as? [String]) ?? []

            let memory = SpatialMemory(
                id: id,
                title: title,
                content: content,
                location: location,
                tags: tags
            )

            if !memories.contains(where: { $0.id == memory.id }) {
                memories.append(memory)
                memoryIndex[memory.id.uuidString] = memory
                spatialTree.insert(memory)
            }
        }

        updateClusters()
        print("☁️ Fetched \(memories.count) memories from CloudKit")
    }
}

// MARK: - CLLocationManagerDelegate

extension SpatialMemorySystem: CLLocationManagerDelegate {

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let arPosition = arKitIntegration?.getCurrentCameraPosition()

        currentLocation = SpatialLocation(
            coordinate: location.coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            arPosition: arPosition,
            floor: location.floor?.level,
            venue: nil
        )

        updateNearbyMemories()
        detectIndoorLocationChange()
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
}

// MARK: - Spatial KD-Tree

private class SpatialKDTree {
    private var memories: [SpatialMemorySystem.SpatialMemory] = []

    func insert(_ memory: SpatialMemorySystem.SpatialMemory) {
        memories.append(memory)
    }

    func remove(id: UUID) {
        memories.removeAll { $0.id == id }
    }

    func nearest(to location: SpatialMemorySystem.SpatialLocation, k: Int) -> [SpatialMemorySystem.SpatialMemory] {
        return memories
            .sorted { memory1, memory2 in
                memory1.location.distance(to: location) < memory2.location.distance(to: location)
            }
            .prefix(k)
            .map { $0 }
    }
}

// MARK: - Errors

public enum SpatialMemoryError: Error {
    case cloudKitNotAvailable
    case locationNotAvailable
    case arKitNotInitialized
}

// MARK: - Codable Support for CLLocationCoordinate2D

extension CLLocationCoordinate2D: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

// MARK: - Indoor Map (Future Enhancement)

private struct IndoorMap {
    let venue: String
    let floors: [FloorPlan]
}

private struct FloorPlan {
    let level: Int
    let rooms: [Room]
    let boundaries: [simd_float2]
}

private struct Room {
    let name: String
    let boundary: [simd_float2]
    let arAnchors: [UUID]
}
