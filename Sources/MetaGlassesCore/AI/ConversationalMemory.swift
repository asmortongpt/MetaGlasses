import Foundation
import Combine

/// Conversational Memory System
/// Multi-turn conversation tracking with context maintenance and knowledge graph integration
@MainActor
public class ConversationalMemory: ObservableObject {

    // MARK: - Singleton
    public static let shared = ConversationalMemory()

    // MARK: - Published Properties
    @Published public var activeConversations: [Conversation] = []
    @Published public var conversationCount = 0
    @Published public var currentConversation: Conversation?

    // MARK: - Private Properties
    private var conversations: [UUID: Conversation] = [:]
    private var topicGraph: TopicKnowledgeGraph
    private let ragMemory = ProductionRAGMemory.shared
    private let llmOrchestrator = LLMOrchestrator()
    private let maxConversationHistory = 100
    private let summarizationThreshold = 20 // messages before summarizing

    // MARK: - Initialization
    private init() {
        self.topicGraph = TopicKnowledgeGraph()
        print("💬 ConversationalMemory initialized")
        loadConversations()
    }

    // MARK: - Conversation Management

    /// Start a new conversation
    public func startConversation(topic: String? = nil) -> Conversation {
        let conversation = Conversation(
            id: UUID(),
            startTime: Date(),
            topic: topic ?? "General",
            messages: [],
            context: ConversationContext(),
            summary: nil
        )

        conversations[conversation.id] = conversation
        currentConversation = conversation
        activeConversations.append(conversation)
        conversationCount = conversations.count

        print("🆕 Started new conversation: \(conversation.topic)")
        return conversation
    }

    /// Add message to active conversation
    public func addMessage(
        _ content: String,
        role: MessageRole,
        metadata: MessageMetadata? = nil
    ) async throws {
        guard var conversation = currentConversation else {
            throw ConversationError.noActiveConversation
        }

        // Create message
        let message = ConversationMessage(
            id: UUID(),
            timestamp: Date(),
            role: role,
            content: content,
            metadata: metadata ?? MessageMetadata()
        )

        // Add to conversation
        conversation.messages.append(message)
        conversation.lastUpdated = Date()

        // Update context
        await updateConversationContext(&conversation, newMessage: message)

        // Check if summarization is needed
        if conversation.messages.count >= summarizationThreshold {
            try await summarizeConversation(&conversation)
        }

        // Update storage
        conversations[conversation.id] = conversation
        currentConversation = conversation
        updateActiveConversations()

        // Store in RAG memory
        try await storeMessageInMemory(message, conversation: conversation)

        // Extract and link topics
        await extractAndLinkTopics(message: message, conversation: conversation)

        saveConversations()
    }

    /// Get conversation history with context
    public func getConversationHistory(
        conversationId: UUID,
        includeContext: Bool = true
    ) -> [ConversationMessage] {
        guard let conversation = conversations[conversationId] else {
            return []
        }

        return conversation.messages
    }

    /// Retrieve relevant context for a query
    public func retrieveRelevantContext(
        query: String,
        conversationId: UUID? = nil,
        limit: Int = 5
    ) async throws -> ConversationContext {
        var relevantMessages: [ConversationMessage] = []
        var relatedTopics: [String] = []

        // Search current conversation first
        if let convId = conversationId ?? currentConversation?.id,
           let conversation = conversations[convId] {
            // Semantic search within conversation
            let searchResults = try await searchConversation(
                query: query,
                conversation: conversation,
                limit: limit
            )
            relevantMessages.append(contentsOf: searchResults)

            // Get related topics from graph
            relatedTopics = topicGraph.findRelatedTopics(query: query, limit: 5)
        }

        // Search all conversations via RAG
        let ragResults = try await ragMemory.retrieveRelevant(
            query: query,
            limit: limit,
            threshold: 0.6
        ) { memory in
            memory.type == .conversation
        }

        // Build context
        return ConversationContext(
            relevantMessages: relevantMessages,
            relatedTopics: relatedTopics,
            ragMemories: ragResults.map { $0.memory.text },
            sentiment: analyzeSentiment(messages: relevantMessages)
        )
    }

    /// End current conversation
    public func endConversation() async throws {
        guard var conversation = currentConversation else {
            return
        }

        conversation.endTime = Date()

        // Final summarization
        if conversation.summary == nil {
            try await summarizeConversation(&conversation)
        }

        conversations[conversation.id] = conversation
        currentConversation = nil
        updateActiveConversations()

        print("✅ Ended conversation: \(conversation.topic)")
        saveConversations()
    }

    // MARK: - Context Management

    private func updateConversationContext(
        _ conversation: inout Conversation,
        newMessage: ConversationMessage
    ) async {
        // Update turn count
        if newMessage.role == .user {
            conversation.context.turnCount += 1
        }

        // Extract entities
        let entities = await extractEntities(from: newMessage.content)
        conversation.context.mentionedEntities.append(contentsOf: entities)

        // Update topics
        if let topic = await extractMainTopic(from: newMessage.content) {
            if !conversation.context.topics.contains(topic) {
                conversation.context.topics.append(topic)
            }
        }

        // Update intent
        conversation.context.userIntent = await detectIntent(message: newMessage)
    }

    private func extractEntities(from text: String) async -> [String] {
        // Use LLM for entity extraction
        let prompt = """
        Extract named entities (people, places, things) from this text.
        Return ONLY a comma-separated list, no explanation.
        Text: \(text)
        """

        do {
            let response = try await llmOrchestrator.chat(
                messages: [["role": "user", "content": prompt]],
                task: .fast
            )

            return response.content
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private func extractMainTopic(from text: String) async -> String? {
        // Simple topic extraction - could use NLP
        let words = text.lowercased().split(separator: " ")
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for"])

        let keywords = words
            .filter { $0.count > 3 && !stopWords.contains(String($0)) }
            .map { String($0) }

        return keywords.first
    }

    private func detectIntent(message: ConversationMessage) async -> String {
        guard message.role == .user else {
            return "respond"
        }

        let text = message.content.lowercased()

        if text.contains("?") {
            return "question"
        } else if text.hasPrefix("tell me") || text.hasPrefix("show me") {
            return "request_info"
        } else if text.contains("help") {
            return "request_help"
        } else if text.contains("thanks") || text.contains("thank you") {
            return "gratitude"
        }

        return "statement"
    }

    // MARK: - Conversation Search

    private func searchConversation(
        query: String,
        conversation: Conversation,
        limit: Int
    ) async throws -> [ConversationMessage] {
        // Generate query embedding
        let queryEmbedding = try await ragMemory.generateEmbedding(for: query)

        // Calculate similarities for all messages
        var scoredMessages: [(ConversationMessage, Float)] = []

        for message in conversation.messages {
            let messageEmbedding = try await ragMemory.generateEmbedding(for: message.content)
            let similarity = cosineSimilarity(queryEmbedding, messageEmbedding)

            if similarity > 0.5 {
                scoredMessages.append((message, similarity))
            }
        }

        // Sort by similarity
        scoredMessages.sort { $0.1 > $1.1 }

        // Return top results
        return Array(scoredMessages.prefix(limit).map { $0.0 })
    }

    // MARK: - Summarization

    private func summarizeConversation(_ conversation: inout Conversation) async throws {
        print("📝 Summarizing conversation...")

        // Build message history
        let messages = conversation.messages.map { msg in
            "\(msg.role.rawValue): \(msg.content)"
        }.joined(separator: "\n")

        // Generate summary
        let prompt = """
        Summarize this conversation in 2-3 sentences, capturing the main topics and key points:

        \(messages)
        """

        let response = try await llmOrchestrator.chat(
            messages: [["role": "user", "content": prompt]],
            task: .fast
        )

        conversation.summary = response.content

        // Keep only recent messages, archive older ones
        if conversation.messages.count > summarizationThreshold {
            let recentCount = summarizationThreshold / 2
            let recentMessages = Array(conversation.messages.suffix(recentCount))
            conversation.messages = recentMessages
        }

        print("✅ Summary: \(response.content)")
    }

    // MARK: - Topic Graph Integration

    private func extractAndLinkTopics(
        message: ConversationMessage,
        conversation: Conversation
    ) async {
        // Extract topics from message
        let prompt = """
        Extract 1-3 main topics/keywords from this message.
        Return ONLY a comma-separated list:
        \(message.content)
        """

        do {
            let response = try await llmOrchestrator.chat(
                messages: [["role": "user", "content": prompt]],
                task: .fast
            )

            let topics = response.content
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Add to knowledge graph
            for topic in topics {
                topicGraph.addTopic(topic, conversationId: conversation.id)
            }

            // Link related topics
            if topics.count >= 2 {
                for i in 0..<topics.count {
                    for j in (i+1)..<topics.count {
                        topicGraph.linkTopics(topics[i], topics[j])
                    }
                }
            }
        } catch {
            print("⚠️ Topic extraction failed: \(error)")
        }
    }

    // MARK: - Sentiment Analysis

    private func analyzeSentiment(messages: [ConversationMessage]) -> Sentiment {
        // Simple sentiment analysis
        let recentMessages = messages.suffix(5)
        var positiveWords = 0
        var negativeWords = 0

        let positiveSet = Set(["good", "great", "excellent", "happy", "love", "thanks", "perfect"])
        let negativeSet = Set(["bad", "terrible", "hate", "angry", "sad", "problem", "issue"])

        for message in recentMessages {
            let words = Set(message.content.lowercased().split(separator: " ").map { String($0) })
            positiveWords += words.intersection(positiveSet).count
            negativeWords += words.intersection(negativeSet).count
        }

        if positiveWords > negativeWords {
            return .positive
        } else if negativeWords > positiveWords {
            return .negative
        } else {
            return .neutral
        }
    }

    // MARK: - Memory Integration

    private func storeMessageInMemory(
        _ message: ConversationMessage,
        conversation: Conversation
    ) async throws {
        let memoryText = """
        Conversation (\(conversation.topic)): \(message.role.rawValue) said "\(message.content)"
        """

        let context = MemoryContext(
            timestamp: message.timestamp,
            activity: "conversation",
            tags: [conversation.topic] + conversation.context.topics
        )

        _ = try await ragMemory.storeMemory(
            text: memoryText,
            type: .conversation,
            context: context
        )
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("conversations.json")
    }

    private func saveConversations() {
        let conversationList = Array(conversations.values)
        if let data = try? JSONEncoder().encode(conversationList) {
            try? data.write(to: fileURL)
        }
    }

    private func loadConversations() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return
        }

        for conv in loaded {
            conversations[conv.id] = conv
        }

        conversationCount = conversations.count
        activeConversations = loaded.filter { $0.endTime == nil }

        print("📚 Loaded \(conversationCount) conversations")
    }

    private func updateActiveConversations() {
        activeConversations = Array(conversations.values.filter { $0.endTime == nil })
    }

    // MARK: - Utilities

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map { $0.0 * $0.1 }.reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Public Queries

    /// Get conversation statistics
    public func getStatistics() -> ConversationStatistics {
        let totalMessages = conversations.values.reduce(0) { $0 + $1.messages.count }
        let avgLength = totalMessages / max(conversations.count, 1)

        return ConversationStatistics(
            totalConversations: conversations.count,
            activeConversations: activeConversations.count,
            totalMessages: totalMessages,
            averageConversationLength: avgLength,
            topTopics: topicGraph.getTopTopics(limit: 10)
        )
    }

    /// Search across all conversations
    public func searchAllConversations(query: String, limit: Int = 10) async throws -> [SearchResult] {
        var results: [SearchResult] = []

        for conversation in conversations.values {
            let matches = try await searchConversation(
                query: query,
                conversation: conversation,
                limit: limit
            )

            for message in matches {
                results.append(SearchResult(
                    conversationId: conversation.id,
                    conversationTopic: conversation.topic,
                    message: message
                ))
            }
        }

        results.sort { $0.message.timestamp > $1.message.timestamp }
        return Array(results.prefix(limit))
    }
}

// MARK: - Topic Knowledge Graph

private class TopicKnowledgeGraph {
    private var topics: [String: TopicNode] = [:]
    private var edges: [TopicEdge] = []

    func addTopic(_ topic: String, conversationId: UUID) {
        let normalized = topic.lowercased()

        if topics[normalized] == nil {
            topics[normalized] = TopicNode(name: normalized, conversationIds: [])
        }

        topics[normalized]?.conversationIds.append(conversationId)
        topics[normalized]?.frequency += 1
    }

    func linkTopics(_ topic1: String, _ topic2: String) {
        let t1 = topic1.lowercased()
        let t2 = topic2.lowercased()

        if let existingIndex = edges.firstIndex(where: {
            ($0.topic1 == t1 && $0.topic2 == t2) || ($0.topic1 == t2 && $0.topic2 == t1)
        }) {
            edges[existingIndex].strength += 1
        } else {
            edges.append(TopicEdge(topic1: t1, topic2: t2, strength: 1))
        }
    }

    func findRelatedTopics(query: String, limit: Int) -> [String] {
        let normalized = query.lowercased()

        // Find direct connections
        let relatedEdges = edges.filter {
            $0.topic1.contains(normalized) || $0.topic2.contains(normalized)
        }.sorted { $0.strength > $1.strength }

        var related = relatedEdges.prefix(limit).flatMap { edge in
            [edge.topic1, edge.topic2]
        }.filter { $0 != normalized }

        return Array(Set(related)).prefix(limit).map { String($0) }
    }

    func getTopTopics(limit: Int) -> [String] {
        return topics.values
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0.name }
    }
}

private struct TopicNode {
    var name: String
    var conversationIds: [UUID]
    var frequency: Int = 1
}

private struct TopicEdge {
    let topic1: String
    let topic2: String
    var strength: Int
}

// MARK: - Supporting Types

public struct Conversation: Codable, Identifiable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public var lastUpdated: Date
    public var topic: String
    public var messages: [ConversationMessage]
    public var context: ConversationContext
    public var summary: String?

    public init(id: UUID, startTime: Date, topic: String, messages: [ConversationMessage], context: ConversationContext, summary: String?) {
        self.id = id
        self.startTime = startTime
        self.lastUpdated = startTime
        self.topic = topic
        self.messages = messages
        self.context = context
        self.summary = summary
    }
}

public struct ConversationMessage: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let role: MessageRole
    public let content: String
    public let metadata: MessageMetadata
}

public struct ConversationContext: Codable {
    public var turnCount: Int = 0
    public var topics: [String] = []
    public var mentionedEntities: [String] = []
    public var userIntent: String = "unknown"
    public var relevantMessages: [ConversationMessage] = []
    public var relatedTopics: [String] = []
    public var ragMemories: [String] = []
    public var sentiment: Sentiment = .neutral

    public init() {}

    public init(relevantMessages: [ConversationMessage], relatedTopics: [String], ragMemories: [String], sentiment: Sentiment) {
        self.relevantMessages = relevantMessages
        self.relatedTopics = relatedTopics
        self.ragMemories = ragMemories
        self.sentiment = sentiment
    }
}

public struct MessageMetadata: Codable {
    public var location: String?
    public var imageAttached: Bool = false
    public var audioLength: TimeInterval?
    public var tags: [String] = []

    public init() {}
}

public struct ConversationStatistics {
    public let totalConversations: Int
    public let activeConversations: Int
    public let totalMessages: Int
    public let averageConversationLength: Int
    public let topTopics: [String]
}

public struct SearchResult {
    public let conversationId: UUID
    public let conversationTopic: String
    public let message: ConversationMessage
}

// MARK: - Enums

public enum MessageRole: String, Codable {
    case user, assistant, system
}

public enum Sentiment: String, Codable {
    case positive, neutral, negative
}

public enum ConversationError: LocalizedError {
    case noActiveConversation
    case conversationNotFound

    public var errorDescription: String? {
        switch self {
        case .noActiveConversation: return "No active conversation"
        case .conversationNotFound: return "Conversation not found"
        }
    }
}
