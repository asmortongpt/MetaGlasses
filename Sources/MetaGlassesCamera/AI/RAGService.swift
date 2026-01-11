import Foundation
import UIKit

/// Retrieval Augmented Generation system with vector embeddings and knowledge base
@MainActor
class RAGService: ObservableObject {
    // MARK: - Published Properties
    @Published var knowledgeBaseSize: Int = 0
    @Published var isIndexing = false
    @Published var lastQuery: String = ""

    // MARK: - Services
    private let openAI: OpenAIService
    private var vectorStore: VectorStore

    // MARK: - Initialization
    init(openAIService: OpenAIService? = nil) {
        self.openAI = openAIService ?? OpenAIService()
        self.vectorStore = VectorStore()

        Task {
            await loadKnowledgeBase()
        }

        print("✅ RAG Service initialized")
    }

    // MARK: - Add Knowledge
    func addDocument(text: String, metadata: [String: String] = [:]) async throws {
        isIndexing = true
        defer { isIndexing = false }

        // Split text into chunks (for long documents)
        let chunks = splitIntoChunks(text, maxLength: 1000)

        for (index, chunk) in chunks.enumerated() {
            // Generate embedding
            let embedding = try await openAI.createEmbedding(text: chunk)

            // Create document
            var docMetadata = metadata
            docMetadata["chunk"] = "\(index)"
            docMetadata["totalChunks"] = "\(chunks.count)"

            let document = VectorDocument(
                content: chunk,
                embedding: embedding,
                metadata: docMetadata
            )

            // Store in vector database
            vectorStore.add(document)
        }

        knowledgeBaseSize = vectorStore.count
        await saveKnowledgeBase()

        print("✅ Added \(chunks.count) document chunks to knowledge base")
    }

    func addImage(image: UIImage, caption: String = "", metadata: [String: String] = [:]) async throws {
        isIndexing = true
        defer { isIndexing = false }

        // Use OpenAI Vision to describe the image
        let imageDescription = try await openAI.analyzeImage(
            image,
            prompt: "Provide a detailed description of this image for knowledge base indexing. Include: objects, people, text, setting, colors, and any notable details."
        )

        // Combine caption and AI description
        let fullText = caption.isEmpty ? imageDescription : "\(caption)\n\n\(imageDescription)"

        // Generate embedding
        let embedding = try await openAI.createEmbedding(text: fullText)

        // Store image data
        var imageMetadata = metadata
        imageMetadata["type"] = "image"
        imageMetadata["hasCaption"] = "\(!caption.isEmpty)"

        let document = VectorDocument(
            content: fullText,
            embedding: embedding,
            metadata: imageMetadata,
            imageData: image.jpegData(compressionQuality: 0.7)
        )

        vectorStore.add(document)
        knowledgeBaseSize = vectorStore.count
        await saveKnowledgeBase()

        print("✅ Image added to knowledge base")
    }

    // MARK: - Search & Retrieve
    func search(query: String, topK: Int = 5) async throws -> [VectorDocument] {
        lastQuery = query

        // Generate query embedding
        let queryEmbedding = try await openAI.createEmbedding(text: query)

        // Search vector store
        let results = vectorStore.search(embedding: queryEmbedding, topK: topK)

        print("🔍 Found \(results.count) relevant documents for: \(query)")
        return results
    }

    // MARK: - RAG-Enhanced Query
    func enhancedQuery(question: String, maxContext: Int = 3) async throws -> String {
        // Search knowledge base for relevant context
        let relevantDocs = try await search(query: question, topK: maxContext)

        // Build context from retrieved documents
        var context = "Relevant information from knowledge base:\n\n"
        for (index, doc) in relevantDocs.enumerated() {
            context += "\(index + 1). \(doc.content)\n\n"
        }

        // Prepare messages with context
        let messages: [[String: String]] = [
            [
                "role": "system",
                "content": """
                You are an AI assistant with access to a personal knowledge base.
                Answer questions using the provided context when relevant.
                If the context doesn't contain the answer, use your general knowledge but mention that.
                """
            ],
            [
                "role": "user",
                "content": """
                Context:
                \(context)

                Question: \(question)

                Please answer the question using the context if relevant.
                """
            ]
        ]

        // Get AI response
        let response = try await openAI.chatCompletion(messages: messages, model: .gpt4Turbo)

        print("✅ RAG-enhanced response generated")
        return response
    }

    // MARK: - Memory & Conversation
    func rememberConversation(messages: [ConversationMessage]) async throws {
        // Extract important information from conversation
        let conversationText = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")

        // Summarize conversation for storage
        let summaryPrompt: [[String: String]] = [
            [
                "role": "system",
                "content": "Summarize the key information from this conversation that should be remembered."
            ],
            [
                "role": "user",
                "content": conversationText
            ]
        ]

        let summary = try await openAI.chatCompletion(messages: summaryPrompt, maxTokens: 500)

        // Store summary with timestamp metadata
        try await addDocument(
            text: summary,
            metadata: [
                "type": "conversation",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "messageCount": "\(messages.count)"
            ]
        )

        print("✅ Conversation remembered")
    }

    // MARK: - Personal Knowledge
    func addPersonalFact(fact: String, category: String = "general") async throws {
        try await addDocument(
            text: fact,
            metadata: [
                "type": "personal_fact",
                "category": category,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        )

        print("✅ Personal fact stored: \(fact.prefix(50))...")
    }

    func recallPersonalFacts(about topic: String) async throws -> [String] {
        let results = try await search(query: topic, topK: 10)

        let facts = results
            .filter { $0.metadata["type"] == "personal_fact" }
            .map { $0.content }

        return facts
    }

    // MARK: - Utilities
    private func splitIntoChunks(_ text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        let sentences = text.components(separatedBy: ". ")

        for sentence in sentences {
            if currentChunk.count + sentence.count > maxLength {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
                currentChunk = sentence
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : ". ") + sentence
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [text] : chunks
    }

    // MARK: - Persistence
    private func saveKnowledgeBase() async {
        do {
            let data = try JSONEncoder().encode(vectorStore.documents)
            let url = getKnowledgeBaseURL()
            try data.write(to: url)
            print("💾 Knowledge base saved (\(vectorStore.count) documents)")
        } catch {
            print("❌ Failed to save knowledge base: \(error)")
        }
    }

    private func loadKnowledgeBase() async {
        do {
            let url = getKnowledgeBaseURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("ℹ️ No existing knowledge base found")
                return
            }

            let data = try Data(contentsOf: url)
            let documents = try JSONDecoder().decode([VectorDocument].self, from: data)
            vectorStore.documents = documents
            knowledgeBaseSize = vectorStore.count
            print("✅ Loaded \(documents.count) documents from knowledge base")
        } catch {
            print("❌ Failed to load knowledge base: \(error)")
        }
    }

    private func getKnowledgeBaseURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("metaglasses_knowledge_base.json")
    }

    // MARK: - Knowledge Base Management
    func clearKnowledgeBase() async {
        vectorStore.clear()
        knowledgeBaseSize = 0
        await saveKnowledgeBase()
        print("🗑️ Knowledge base cleared")
    }

    func exportKnowledgeBase() async throws -> Data {
        return try JSONEncoder().encode(vectorStore.documents)
    }

    func importKnowledgeBase(data: Data) async throws {
        let documents = try JSONDecoder().decode([VectorDocument].self, from: data)
        vectorStore.documents = documents
        knowledgeBaseSize = vectorStore.count
        await saveKnowledgeBase()
        print("📥 Imported \(documents.count) documents")
    }
}

// MARK: - Vector Store
class VectorStore {
    var documents: [VectorDocument] = []

    var count: Int {
        return documents.count
    }

    func add(_ document: VectorDocument) {
        documents.append(document)
    }

    func search(embedding: [Double], topK: Int) -> [VectorDocument] {
        // Calculate cosine similarity for all documents
        let scoredDocs = documents.map { doc in
            (doc, cosineSimilarity(embedding, doc.embedding))
        }

        // Sort by similarity (descending) and take top K
        let topDocs = scoredDocs
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }

        return Array(topDocs)
    }

    func clear() {
        documents.removeAll()
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }
}

// MARK: - Vector Document
struct VectorDocument: Codable, Identifiable {
    let id: UUID
    let content: String
    let embedding: [Double]
    let metadata: [String: String]
    let imageData: Data?
    let timestamp: Date

    init(
        content: String,
        embedding: [Double],
        metadata: [String: String] = [:],
        imageData: Data? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.embedding = embedding
        self.metadata = metadata
        self.imageData = imageData
        self.timestamp = Date()
    }

    var hasImage: Bool {
        return imageData != nil
    }

    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Re-export ConversationMessage if needed
// (Already defined in VoiceAssistantService, so this is just for reference)
