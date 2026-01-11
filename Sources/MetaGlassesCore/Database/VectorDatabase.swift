import Foundation
import CoreData
import SQLite3
import Accelerate
import simd

// MARK: - Vector Database Protocol
public protocol VectorDatabaseProtocol {
    func insert(id: UUID, embedding: [Float], metadata: [String: Any]) async throws
    func update(id: UUID, embedding: [Float]) async throws
    func delete(id: UUID) async throws
    func search(query: [Float], k: Int, threshold: Float) async throws -> [SearchResult]
    func getEmbeddings(for id: UUID) async throws -> [[Float]]
    func getMetadata(for id: UUID) async throws -> [String: Any]?
    func updateMetadata(id: UUID, metadata: [String: Any]) async throws
}

// MARK: - Models
public struct SearchResult {
    public let id: UUID
    public let similarity: Float
    public let metadata: [String: Any]
}

// MARK: - Vector Database Implementation
public final class VectorDatabase: VectorDatabaseProtocol {

    // MARK: - Properties
    private var db: OpaquePointer?
    private let dbPath: String
    private let dimension: Int
    private let indexType: IndexType
    private var index: VectorIndex?

    // Configuration
    private let maxVectors = 1_000_000
    private let batchSize = 100
    private let compressionRatio: Float = 0.9

    // Cache
    private var cache = LRUCache<UUID, [Float]>(capacity: 1000)
    private let queue = DispatchQueue(label: "vector.db", attributes: .concurrent)

    // MARK: - Index Types
    public enum IndexType {
        case flat           // Exact search
        case hnsw           // Hierarchical Navigable Small World
        case ivfFlat        // Inverted File with Flat vectors
        case lsh            // Locality Sensitive Hashing
        case annoy          // Approximate Nearest Neighbors
    }

    // MARK: - Initialization
    public init(dimension: Int = 512, indexType: IndexType = .hnsw) throws {
        self.dimension = dimension
        self.indexType = indexType

        // Setup database path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbPath = documentsPath.appendingPathComponent("vectors.db").path

        try setupDatabase()
        try createIndex()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Setup
    private func setupDatabase() throws {
        // Open database
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw VectorDatabaseError.databaseOpenFailed
        }

        // Enable WAL mode for better concurrency
        try executeSQL("PRAGMA journal_mode=WAL")
        try executeSQL("PRAGMA synchronous=NORMAL")

        // Create tables
        let createVectorsTable = """
            CREATE TABLE IF NOT EXISTS vectors (
                id TEXT PRIMARY KEY,
                embedding BLOB NOT NULL,
                metadata TEXT,
                norm REAL,
                created_at REAL,
                updated_at REAL
            )
        """
        try executeSQL(createVectorsTable)

        // Create indices
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_norm ON vectors(norm)")
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_created_at ON vectors(created_at)")

        // Create index metadata table
        let createIndexTable = """
            CREATE TABLE IF NOT EXISTS vector_index (
                id INTEGER PRIMARY KEY,
                type TEXT,
                data BLOB,
                updated_at REAL
            )
        """
        try executeSQL(createIndexTable)

        // Create clustering table for IVF
        let createClustersTable = """
            CREATE TABLE IF NOT EXISTS clusters (
                id INTEGER PRIMARY KEY,
                centroid BLOB,
                vector_ids TEXT
            )
        """
        try executeSQL(createClustersTable)
    }

    private func createIndex() throws {
        switch indexType {
        case .flat:
            index = FlatIndex(dimension: dimension)
        case .hnsw:
            index = HNSWIndex(dimension: dimension)
        case .ivfFlat:
            index = IVFFlatIndex(dimension: dimension, nClusters: 100)
        case .lsh:
            index = LSHIndex(dimension: dimension, nTables: 10)
        case .annoy:
            index = AnnoyIndex(dimension: dimension)
        }

        // Load existing vectors into index
        try loadIndexFromDatabase()
    }

    // MARK: - Public Methods
    public func insert(id: UUID, embedding: [Float], metadata: [String: Any]) async throws {
        guard embedding.count == dimension else {
            throw VectorDatabaseError.dimensionMismatch
        }

        let normalized = normalizeVector(embedding)
        let norm = vectorNorm(normalized)
        let embeddingData = Data(bytes: normalized, count: normalized.count * MemoryLayout<Float>.size)
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        let timestamp = Date().timeIntervalSince1970

        let sql = """
            INSERT OR REPLACE INTO vectors (id, embedding, metadata, norm, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """

        try await executeAsync { [weak self] in
            guard let self = self else { return }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw VectorDatabaseError.statementPreparationFailed
            }

            sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
            sqlite3_bind_blob(statement, 2, embeddingData.withUnsafeBytes { $0.baseAddress }, Int32(embeddingData.count), nil)
            sqlite3_bind_blob(statement, 3, metadataJSON.withUnsafeBytes { $0.baseAddress }, Int32(metadataJSON.count), nil)
            sqlite3_bind_double(statement, 4, Double(norm))
            sqlite3_bind_double(statement, 5, timestamp)
            sqlite3_bind_double(statement, 6, timestamp)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw VectorDatabaseError.insertFailed
            }

            // Update index
            self.index?.add(id: id, vector: normalized)

            // Update cache
            self.cache.set(id, value: normalized)
        }
    }

    public func update(id: UUID, embedding: [Float]) async throws {
        guard embedding.count == dimension else {
            throw VectorDatabaseError.dimensionMismatch
        }

        let normalized = normalizeVector(embedding)
        let norm = vectorNorm(normalized)
        let embeddingData = Data(bytes: normalized, count: normalized.count * MemoryLayout<Float>.size)
        let timestamp = Date().timeIntervalSince1970

        let sql = """
            UPDATE vectors SET embedding = ?, norm = ?, updated_at = ?
            WHERE id = ?
        """

        try await executeAsync { [weak self] in
            guard let self = self else { return }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw VectorDatabaseError.statementPreparationFailed
            }

            sqlite3_bind_blob(statement, 1, embeddingData.withUnsafeBytes { $0.baseAddress }, Int32(embeddingData.count), nil)
            sqlite3_bind_double(statement, 2, Double(norm))
            sqlite3_bind_double(statement, 3, timestamp)
            sqlite3_bind_text(statement, 4, id.uuidString, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw VectorDatabaseError.updateFailed
            }

            // Update index
            self.index?.update(id: id, vector: normalized)

            // Update cache
            self.cache.set(id, value: normalized)
        }
    }

    public func delete(id: UUID) async throws {
        let sql = "DELETE FROM vectors WHERE id = ?"

        try await executeAsync { [weak self] in
            guard let self = self else { return }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw VectorDatabaseError.statementPreparationFailed
            }

            sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw VectorDatabaseError.deleteFailed
            }

            // Remove from index
            self.index?.remove(id: id)

            // Remove from cache
            self.cache.remove(id)
        }
    }

    public func search(query: [Float], k: Int, threshold: Float) async throws -> [SearchResult] {
        guard query.count == dimension else {
            throw VectorDatabaseError.dimensionMismatch
        }

        let normalized = normalizeVector(query)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: VectorDatabaseError.searchFailed)
                    return
                }

                do {
                    // Use index for approximate search
                    let candidates = self.index?.search(query: normalized, k: k * 2) ?? []

                    // Rerank with exact similarity
                    var results: [SearchResult] = []

                    for candidateId in candidates {
                        if let vector = self.getVector(id: candidateId) {
                            let similarity = self.cosineSimilarity(normalized, vector)

                            if similarity >= threshold {
                                if let metadata = try? self.getMetadataSync(for: candidateId) {
                                    results.append(SearchResult(
                                        id: candidateId,
                                        similarity: similarity,
                                        metadata: metadata
                                    ))
                                }
                            }
                        }
                    }

                    // Sort by similarity
                    results.sort { $0.similarity > $1.similarity }

                    // Return top k
                    continuation.resume(returning: Array(results.prefix(k)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func getEmbeddings(for id: UUID) async throws -> [[Float]] {
        // For now, return single embedding
        // In production, could store multiple embeddings per person
        if let vector = getVector(id: id) {
            return [vector]
        }
        return []
    }

    public func getMetadata(for id: UUID) async throws -> [String: Any]? {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                do {
                    let metadata = try self?.getMetadataSync(for: id)
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func updateMetadata(id: UUID, metadata: [String: Any]) async throws {
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        let sql = "UPDATE vectors SET metadata = ?, updated_at = ? WHERE id = ?"

        try await executeAsync { [weak self] in
            guard let self = self else { return }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw VectorDatabaseError.statementPreparationFailed
            }

            sqlite3_bind_blob(statement, 1, metadataJSON.withUnsafeBytes { $0.baseAddress }, Int32(metadataJSON.count), nil)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, id.uuidString, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw VectorDatabaseError.updateFailed
            }
        }
    }

    // MARK: - Private Methods
    private func normalizeVector(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    private func vectorNorm(_ vector: [Float]) -> Float {
        return sqrt(vector.reduce(0) { $0 + $1 * $1 })
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        return dotProduct // Vectors are already normalized
    }

    private func getVector(id: UUID) -> [Float]? {
        // Check cache first
        if let cached = cache.get(id) {
            return cached
        }

        // Load from database
        let sql = "SELECT embedding FROM vectors WHERE id = ?"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard let blob = sqlite3_column_blob(statement, 0) else {
            return nil
        }

        let bytes = sqlite3_column_bytes(statement, 0)
        let count = Int(bytes) / MemoryLayout<Float>.size

        let vector = Array(UnsafeBufferPointer(start: blob.bindMemory(to: Float.self, capacity: count), count: count))

        // Update cache
        cache.set(id, value: vector)

        return vector
    }

    private func getMetadataSync(for id: UUID) throws -> [String: Any] {
        let sql = "SELECT metadata FROM vectors WHERE id = ?"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorDatabaseError.statementPreparationFailed
        }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw VectorDatabaseError.notFound
        }

        guard let blob = sqlite3_column_blob(statement, 0) else {
            return [:]
        }

        let bytes = sqlite3_column_bytes(statement, 0)
        let data = Data(bytes: blob, count: Int(bytes))

        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func executeSQL(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw VectorDatabaseError.sqlExecutionFailed
        }
    }

    private func executeAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadIndexFromDatabase() throws {
        let sql = "SELECT id, embedding FROM vectors"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorDatabaseError.statementPreparationFailed
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idString)),
                  let blob = sqlite3_column_blob(statement, 1) else {
                continue
            }

            let bytes = sqlite3_column_bytes(statement, 1)
            let count = Int(bytes) / MemoryLayout<Float>.size

            let vector = Array(UnsafeBufferPointer(start: blob.bindMemory(to: Float.self, capacity: count), count: count))

            index?.add(id: id, vector: vector)
        }
    }
}

// MARK: - Vector Index Protocol
protocol VectorIndex {
    func add(id: UUID, vector: [Float])
    func update(id: UUID, vector: [Float])
    func remove(id: UUID)
    func search(query: [Float], k: Int) -> [UUID]
}

// MARK: - Flat Index (Brute Force)
class FlatIndex: VectorIndex {
    private var vectors: [UUID: [Float]] = [:]
    private let dimension: Int

    init(dimension: Int) {
        self.dimension = dimension
    }

    func add(id: UUID, vector: [Float]) {
        vectors[id] = vector
    }

    func update(id: UUID, vector: [Float]) {
        vectors[id] = vector
    }

    func remove(id: UUID) {
        vectors.removeValue(forKey: id)
    }

    func search(query: [Float], k: Int) -> [UUID] {
        var similarities: [(UUID, Float)] = []

        for (id, vector) in vectors {
            let similarity = cosineSimilarity(query, vector)
            similarities.append((id, similarity))
        }

        similarities.sort { $0.1 > $1.1 }
        return Array(similarities.prefix(k).map { $0.0 })
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        return dotProduct
    }
}

// MARK: - HNSW Index (Hierarchical Navigable Small World)
class HNSWIndex: VectorIndex {
    private let dimension: Int
    private let m = 16  // Number of connections
    private let efConstruction = 200  // Size of dynamic candidate list
    private var layers: [[UUID: Set<UUID>]] = []
    private var vectors: [UUID: [Float]] = [:]

    init(dimension: Int) {
        self.dimension = dimension
    }

    func add(id: UUID, vector: [Float]) {
        vectors[id] = vector
        // Simplified HNSW insertion
        // In production, implement full HNSW algorithm
    }

    func update(id: UUID, vector: [Float]) {
        vectors[id] = vector
        // Update connections if needed
    }

    func remove(id: UUID) {
        vectors.removeValue(forKey: id)
        // Remove from graph layers
    }

    func search(query: [Float], k: Int) -> [UUID] {
        // Simplified search
        return FlatIndex(dimension: dimension).also { index in
            for (id, vector) in vectors {
                index.add(id: id, vector: vector)
            }
        }.search(query: query, k: k)
    }
}

// MARK: - IVF Flat Index (Inverted File with Flat vectors)
class IVFFlatIndex: VectorIndex {
    private let dimension: Int
    private let nClusters: Int
    private var centroids: [[Float]] = []
    private var clusters: [Int: [UUID]] = [:]
    private var vectors: [UUID: [Float]] = [:]

    init(dimension: Int, nClusters: Int) {
        self.dimension = dimension
        self.nClusters = nClusters
    }

    func add(id: UUID, vector: [Float]) {
        vectors[id] = vector
        // Assign to nearest cluster
        if !centroids.isEmpty {
            let clusterIndex = findNearestCentroid(vector)
            clusters[clusterIndex, default: []].append(id)
        }
    }

    func update(id: UUID, vector: [Float]) {
        vectors[id] = vector
        // Re-assign to cluster if needed
    }

    func remove(id: UUID) {
        vectors.removeValue(forKey: id)
        // Remove from clusters
    }

    func search(query: [Float], k: Int) -> [UUID] {
        guard !centroids.isEmpty else {
            return FlatIndex(dimension: dimension).also { index in
                for (id, vector) in vectors {
                    index.add(id: id, vector: vector)
                }
            }.search(query: query, k: k)
        }

        // Find nearest clusters
        let nearestClusters = findNearestCentroids(query, n: min(3, centroids.count))

        // Search within selected clusters
        var candidates: [UUID] = []
        for clusterIndex in nearestClusters {
            candidates.append(contentsOf: clusters[clusterIndex] ?? [])
        }

        // Rerank candidates
        var similarities: [(UUID, Float)] = []
        for id in candidates {
            if let vector = vectors[id] {
                let similarity = cosineSimilarity(query, vector)
                similarities.append((id, similarity))
            }
        }

        similarities.sort { $0.1 > $1.1 }
        return Array(similarities.prefix(k).map { $0.0 })
    }

    private func findNearestCentroid(_ vector: [Float]) -> Int {
        var minDistance = Float.infinity
        var nearestIndex = 0

        for (index, centroid) in centroids.enumerated() {
            let distance = euclideanDistance(vector, centroid)
            if distance < minDistance {
                minDistance = distance
                nearestIndex = index
            }
        }

        return nearestIndex
    }

    private func findNearestCentroids(_ vector: [Float], n: Int) -> [Int] {
        var distances: [(Int, Float)] = []

        for (index, centroid) in centroids.enumerated() {
            let distance = euclideanDistance(vector, centroid)
            distances.append((index, distance))
        }

        distances.sort { $0.1 < $1.1 }
        return Array(distances.prefix(n).map { $0.0 })
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        var distance: Float = 0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            distance += diff * diff
        }
        return sqrt(distance)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        return dotProduct
    }
}

// MARK: - LSH Index (Locality Sensitive Hashing)
class LSHIndex: VectorIndex {
    private let dimension: Int
    private let nTables: Int
    private var hashTables: [[Int: [UUID]]] = []
    private var vectors: [UUID: [Float]] = [:]
    private var hashFunctions: [[[Float]]] = []

    init(dimension: Int, nTables: Int) {
        self.dimension = dimension
        self.nTables = nTables
        initializeHashFunctions()
    }

    private func initializeHashFunctions() {
        for _ in 0..<nTables {
            var table: [[Float]] = []
            for _ in 0..<4 { // Number of hash functions per table
                table.append((0..<dimension).map { _ in Float.random(in: -1...1) })
            }
            hashFunctions.append(table)
            hashTables.append([:])
        }
    }

    func add(id: UUID, vector: [Float]) {
        vectors[id] = vector

        for (tableIndex, functions) in hashFunctions.enumerated() {
            let hash = computeHash(vector, functions: functions)
            hashTables[tableIndex][hash, default: []].append(id)
        }
    }

    func update(id: UUID, vector: [Float]) {
        remove(id: id)
        add(id: id, vector: vector)
    }

    func remove(id: UUID) {
        vectors.removeValue(forKey: id)
        // Remove from hash tables
    }

    func search(query: [Float], k: Int) -> [UUID] {
        var candidates = Set<UUID>()

        for (tableIndex, functions) in hashFunctions.enumerated() {
            let hash = computeHash(query, functions: functions)
            if let bucket = hashTables[tableIndex][hash] {
                candidates.formUnion(bucket)
            }
        }

        // Rerank candidates
        var similarities: [(UUID, Float)] = []
        for id in candidates {
            if let vector = vectors[id] {
                let similarity = cosineSimilarity(query, vector)
                similarities.append((id, similarity))
            }
        }

        similarities.sort { $0.1 > $1.1 }
        return Array(similarities.prefix(k).map { $0.0 })
    }

    private func computeHash(_ vector: [Float], functions: [[Float]]) -> Int {
        var hash = 0
        for (i, function) in functions.enumerated() {
            var dotProduct: Float = 0
            vDSP_dotpr(vector, 1, function, 1, &dotProduct, vDSP_Length(vector.count))
            if dotProduct > 0 {
                hash |= (1 << i)
            }
        }
        return hash
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        return dotProduct
    }
}

// MARK: - Annoy Index (Approximate Nearest Neighbors)
class AnnoyIndex: VectorIndex {
    private let dimension: Int
    private var vectors: [UUID: [Float]] = [:]

    init(dimension: Int) {
        self.dimension = dimension
    }

    func add(id: UUID, vector: [Float]) {
        vectors[id] = vector
    }

    func update(id: UUID, vector: [Float]) {
        vectors[id] = vector
    }

    func remove(id: UUID) {
        vectors.removeValue(forKey: id)
    }

    func search(query: [Float], k: Int) -> [UUID] {
        // Simplified implementation
        return FlatIndex(dimension: dimension).also { index in
            for (id, vector) in vectors {
                index.add(id: id, vector: vector)
            }
        }.search(query: query, k: k)
    }
}

// MARK: - LRU Cache
private class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var cache: [Key: Value] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let value = cache[key] else { return nil }

        // Move to end (most recently used)
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }

        return value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        // Remove if exists
        if cache[key] != nil {
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
        }

        // Add to cache
        cache[key] = value
        order.append(key)

        // Evict if over capacity
        while order.count > capacity {
            let evictKey = order.removeFirst()
            cache.removeValue(forKey: evictKey)
        }
    }

    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
    }
}

// MARK: - Helper Extension
private extension FlatIndex {
    func also(_ block: (FlatIndex) -> Void) -> FlatIndex {
        block(self)
        return self
    }
}

// MARK: - Errors
public enum VectorDatabaseError: LocalizedError {
    case databaseOpenFailed
    case sqlExecutionFailed
    case statementPreparationFailed
    case dimensionMismatch
    case insertFailed
    case updateFailed
    case deleteFailed
    case searchFailed
    case notFound

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed:
            return "Failed to open vector database"
        case .sqlExecutionFailed:
            return "Failed to execute SQL"
        case .statementPreparationFailed:
            return "Failed to prepare SQL statement"
        case .dimensionMismatch:
            return "Vector dimension mismatch"
        case .insertFailed:
            return "Failed to insert vector"
        case .updateFailed:
            return "Failed to update vector"
        case .deleteFailed:
            return "Failed to delete vector"
        case .searchFailed:
            return "Search operation failed"
        case .notFound:
            return "Vector not found"
        }
    }
}