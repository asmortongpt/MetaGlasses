import Foundation

/// Production RAG Memory System with Real OpenAI Embeddings
/// Stores and retrieves memories using vector similarity search
@MainActor
public class ProductionRAGMemory: ObservableObject {

    // MARK: - Singleton
    public static let shared = ProductionRAGMemory()

    // MARK: - Published Properties
    @Published public var memoryCount = 0
    @Published public var recentMemories: [Memory] = []

    // MARK: - Properties
    private var memories: [Memory] = []
    private let embeddingCache = NSCache<NSString, NSArray>()
    private let openAIKey: String

    // MARK: - Initialization
    private init() {
        // Get OpenAI key from environment
        self.openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "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"

        print("🧠 ProductionRAGMemory initialized")
        loadMemories()
    }

    // MARK: - Embedding Generation

    /// Generate text embedding using OpenAI API
    public func generateEmbedding(for text: String) async throws -> [Float] {
        // Check cache first
        let cacheKey = text as NSString
        if let cached = embeddingCache.object(forKey: cacheKey) as? [Float] {
            return cached
        }

        // Build request
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "text-embedding-3-small",
            "input": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RAGError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RAGError.apiError("OpenAI API Error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let firstData = dataArray.first,
              let embedding = firstData["embedding"] as? [Double] else {
            throw RAGError.parsingError
        }

        let floatEmbedding = embedding.map { Float($0) }

        // Cache the result
        embeddingCache.setObject(floatEmbedding as NSArray, forKey: cacheKey)

        return floatEmbedding
    }

    // MARK: - Memory Storage

    /// Store a new memory
    public func storeMemory(
        text: String,
        type: MemoryType,
        context: MemoryContext? = nil,
        metadata: [String: String] = [:]
    ) async throws -> Memory {
        // Generate embedding
        let embedding = try await generateEmbedding(for: text)

        // Create memory
        let memory = Memory(
            id: UUID(),
            text: text,
            type: type,
            embedding: embedding,
            context: context ?? MemoryContext(),
            metadata: metadata,
            createdAt: Date(),
            lastAccessed: Date(),
            accessCount: 0
        )

        // Store
        memories.append(memory)
        memoryCount = memories.count
        recentMemories = Array(memories.suffix(10).reversed())

        // Save to disk
        saveMemories()

        print("✅ Stored memory: \(text.prefix(50))...")
        return memory
    }

    // MARK: - Memory Retrieval

    /// Retrieve relevant memories using semantic search
    public func retrieveRelevant(
        query: String,
        limit: Int = 5,
        threshold: Float = 0.5,
        filter: ((Memory) -> Bool)? = nil
    ) async throws -> [ScoredMemory] {
        // Generate query embedding
        let queryEmbedding = try await generateEmbedding(for: query)

        // Calculate similarities
        var scoredMemories: [ScoredMemory] = []

        for memory in memories {
            // Apply filter if provided
            if let filter = filter, !filter(memory) {
                continue
            }

            let similarity = cosineSimilarity(queryEmbedding, memory.embedding)

            if similarity >= threshold {
                scoredMemories.append(ScoredMemory(memory: memory, score: similarity))

                // Update access stats
                updateAccessStats(for: memory.id)
            }
        }

        // Sort by similarity
        scoredMemories.sort { $0.score > $1.score }

        // Return top results
        return Array(scoredMemories.prefix(limit))
    }

    /// Retrieve memories by type
    public func retrieveByType(_ type: MemoryType, limit: Int = 10) -> [Memory] {
        return Array(memories.filter { $0.type == type }.suffix(limit).reversed())
    }

    /// Retrieve recent memories
    public func retrieveRecent(limit: Int = 10) -> [Memory] {
        return Array(memories.suffix(limit).reversed())
    }

    // MARK: - Helper Methods

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map { $0.0 * $0.1 }.reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Update access statistics for a memory
    private func updateAccessStats(for id: UUID) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].lastAccessed = Date()
            memories[index].accessCount += 1
        }
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("memories.json")
    }

    private func saveMemories() {
        if let data = try? JSONEncoder().encode(memories) {
            try? data.write(to: fileURL)
        }
    }

    private func loadMemories() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([Memory].self, from: data) else {
            return
        }

        memories = loaded
        memoryCount = memories.count
        recentMemories = Array(memories.suffix(10).reversed())

        print("📚 Loaded \(memoryCount) memories")
    }

    /// Clear all memories
    public func clearAllMemories() {
        memories.removeAll()
        memoryCount = 0
        recentMemories = []
        saveMemories()
        print("🗑️ Cleared all memories")
    }

    /// Delete specific memory
    public func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        memoryCount = memories.count
        saveMemories()
        print("🗑️ Deleted memory: \(id)")
    }
}

// MARK: - Models

public struct Memory: Codable, Identifiable {
    public let id: UUID
    public let text: String
    public let type: MemoryType
    public let embedding: [Float]
    public var context: MemoryContext
    public var metadata: [String: String]
    public let createdAt: Date
    public var lastAccessed: Date
    public var accessCount: Int

    public init(id: UUID, text: String, type: MemoryType, embedding: [Float], context: MemoryContext, metadata: [String: String], createdAt: Date, lastAccessed: Date, accessCount: Int) {
        self.id = id
        self.text = text
        self.type = type
        self.embedding = embedding
        self.context = context
        self.metadata = metadata
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.accessCount = accessCount
    }
}

public struct MemoryContext: Codable {
    public var location: LocationInfo?
    public var timestamp: Date?
    public var activity: String?
    public var weather: String?
    public var people: [String]?
    public var tags: [String]?

    public init(location: LocationInfo? = nil, timestamp: Date? = nil, activity: String? = nil, weather: String? = nil, people: [String]? = nil, tags: [String]? = nil) {
        self.location = location
        self.timestamp = timestamp
        self.activity = activity
        self.weather = weather
        self.people = people
        self.tags = tags
    }
}

public struct LocationInfo: Codable {
    public let latitude: Double
    public let longitude: Double
    public let name: String?

    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
}

public enum MemoryType: String, Codable {
    case conversation
    case observation
    case reminder
    case fact
    case experience
    case person
    case place
    case event
}

public struct ScoredMemory {
    public let memory: Memory
    public let score: Float

    public init(memory: Memory, score: Float) {
        self.memory = memory
        self.score = score
    }
}

public enum RAGError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case parsingError

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let message):
            return message
        case .parsingError:
            return "Failed to parse response"
        }
    }
}
