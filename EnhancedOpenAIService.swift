import Foundation
import SwiftUI
import Combine
import CryptoKit
import UIKit

// MARK: - Enhanced OpenAI Service with Streaming & Advanced Features
@MainActor
class EnhancedOpenAIService: ObservableObject {
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var streamingText = ""
    @Published var streamingTokens: [String] = []
    @Published var conversationHistory: [ChatMessage] = []
    @Published var currentStreamingMessage: ChatMessage?
    @Published var error: ServiceError?
    @Published var requestMetrics = RequestMetrics()
    @Published var connectionQuality: ConnectionQuality = .excellent
    @Published var functionCalls: [FunctionCall] = []

    // MARK: - Private Properties
    private let apiKey: String
    private var cancellables = Set<AnyCancellable>()
    private var streamTask: URLSessionDataTask?
    private let session: URLSession
    private let cache = ResponseCache()
    private let rateLimiter = RateLimiter()
    private let requestQueue = RequestQueue()
    private let metricsCollector = MetricsCollector()
    private let retryManager = RetryManager()

    // Advanced features
    private let contextWindow = 128000 // GPT-4 Turbo context window
    private var systemPrompts: [SystemPrompt] = []
    private var activeTools: [AITool] = []
    private var memoryBank = MemoryBank()

    // MARK: - Configuration
    struct Configuration {
        var model: Model = .gpt4Turbo
        var temperature: Double = 0.7
        var maxTokens: Int = 4096
        var topP: Double = 1.0
        var frequencyPenalty: Double = 0.0
        var presencePenalty: Double = 0.0
        var streamEnabled: Bool = true
        var autoRetry: Bool = true
        var cacheEnabled: Bool = true
        var offlineMode: Bool = false
        var contextCompression: Bool = true
        var functionCallingEnabled: Bool = true
    }

    var configuration = Configuration()

    // MARK: - Models & Types
    enum Model: String, CaseIterable {
        case gpt4 = "gpt-4"
        case gpt4Turbo = "gpt-4-turbo-preview"
        case gpt4Vision = "gpt-4-vision-preview"
        case gpt35Turbo = "gpt-3.5-turbo"
        case gpt35Turbo16k = "gpt-3.5-turbo-16k"
        case gpt4o = "gpt-4o"
        case gpt4oMini = "gpt-4o-mini"

        var contextWindow: Int {
            switch self {
            case .gpt4Turbo, .gpt4Vision, .gpt4o: return 128000
            case .gpt35Turbo16k: return 16384
            case .gpt4, .gpt35Turbo, .gpt4oMini: return 8192
            }
        }

        var supportsVision: Bool {
            switch self {
            case .gpt4Vision, .gpt4o, .gpt4oMini: return true
            default: return false
            }
        }

        var supportsFunctions: Bool {
            return true // All models support function calling now
        }
    }

    struct ChatMessage: Identifiable, Codable {
        let id = UUID()
        let role: Role
        var content: String
        let timestamp: Date
        var tokens: Int?
        var images: [UIImage]?
        var functionCall: FunctionCall?
        var metadata: MessageMetadata?

        enum Role: String, Codable {
            case system, user, assistant, function
        }
    }

    struct MessageMetadata: Codable {
        var model: String?
        var temperature: Double?
        var processingTime: TimeInterval?
        var cached: Bool = false
        var retryCount: Int = 0
    }

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
        var result: String?
    }

    struct ServiceError: LocalizedError {
        let code: ErrorCode
        let message: String
        let underlyingError: Error?

        enum ErrorCode {
            case networkError
            case apiError
            case rateLimitExceeded
            case invalidResponse
            case authenticationFailed
            case contextOverflow
            case functionCallFailed
        }

        var errorDescription: String? {
            return message
        }
    }

    // MARK: - Initialization
    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""

        // Configure URLSession with optimizations
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: configuration)

        setupSystemPrompts()
        setupTools()
        startMetricsCollection()
    }

    private func setupSystemPrompts() {
        systemPrompts = [
            SystemPrompt(
                id: "meta-glasses",
                content: """
                You are an advanced AI assistant integrated into Meta Ray-Ban smart glasses. You have:
                - Real-time camera and vision capabilities with object detection and scene understanding
                - Facial recognition and emotion detection
                - Voice commands with natural language understanding
                - Location and contextual awareness
                - Access to user's calendar, contacts, and preferences
                - Ability to control smart glasses features (camera, recording, etc.)

                Be concise, helpful, and proactive. Anticipate user needs based on context.
                Use real-time information when available. Provide actionable insights.
                """,
                priority: .high
            ),
            SystemPrompt(
                id: "personality",
                content: """
                Personality traits:
                - Professional yet friendly
                - Proactive and anticipatory
                - Detail-oriented
                - Privacy-conscious
                - Culturally aware
                """,
                priority: .medium
            )
        ]
    }

    private func setupTools() {
        activeTools = [
            AITool(
                name: "capture_photo",
                description: "Take a photo using the Meta glasses camera",
                parameters: ["quality": "high", "hdr": "auto", "flash": "auto"]
            ),
            AITool(
                name: "start_recording",
                description: "Start video recording",
                parameters: ["quality": "4K", "stabilization": "true"]
            ),
            AITool(
                name: "analyze_scene",
                description: "Analyze the current scene visible through glasses",
                parameters: ["detail_level": "comprehensive"]
            ),
            AITool(
                name: "identify_person",
                description: "Identify a person in view using facial recognition",
                parameters: ["confidence_threshold": "0.8"]
            ),
            AITool(
                name: "translate_text",
                description: "Translate text visible in the camera view",
                parameters: ["source": "auto", "target": "en"]
            ),
            AITool(
                name: "set_reminder",
                description: "Set a contextual reminder",
                parameters: ["time": "string", "message": "string", "location": "optional"]
            )
        ]
    }

    // MARK: - Streaming Chat
    func streamChat(message: String, images: [UIImage]? = nil) async {
        guard !apiKey.isEmpty else {
            self.error = ServiceError(
                code: .authenticationFailed,
                message: "API key not configured",
                underlyingError: nil
            )
            return
        }

        isProcessing = true
        streamingText = ""
        streamingTokens = []

        // Check cache first
        if configuration.cacheEnabled,
           let cachedResponse = cache.get(for: message, images: images) {
            await handleCachedResponse(cachedResponse)
            return
        }

        // Check rate limits
        guard rateLimiter.canMakeRequest() else {
            self.error = ServiceError(
                code: .rateLimitExceeded,
                message: "Rate limit exceeded. Please wait.",
                underlyingError: nil
            )
            isProcessing = false
            return
        }

        // Add user message to history
        let userMessage = ChatMessage(
            role: .user,
            content: message,
            timestamp: Date(),
            images: images
        )
        conversationHistory.append(userMessage)

        // Compress context if needed
        if configuration.contextCompression {
            await compressContextIfNeeded()
        }

        do {
            let request = try await buildStreamingRequest(message: message, images: images)
            await performStreamingRequest(request)
        } catch {
            self.error = ServiceError(
                code: .networkError,
                message: "Failed to build request",
                underlyingError: error
            )
            isProcessing = false
        }
    }

    private func buildStreamingRequest(message: String, images: [UIImage]?) async throws -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: Any]] = []

        // Add system prompts
        for prompt in systemPrompts.sorted(by: { $0.priority.rawValue > $1.priority.rawValue }) {
            messages.append([
                "role": "system",
                "content": prompt.content
            ])
        }

        // Add conversation history (with smart truncation)
        let relevantHistory = getRelevantHistory()
        for msg in relevantHistory {
            var messageDict: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content
            ]

            // Add images if present
            if let images = msg.images, msg.role == .user {
                messageDict["content"] = buildMultimodalContent(text: msg.content, images: images)
            }

            messages.append(messageDict)
        }

        // Add current message
        if let images = images, configuration.model.supportsVision {
            messages.append([
                "role": "user",
                "content": buildMultimodalContent(text: message, images: images)
            ])
        } else {
            messages.append([
                "role": "user",
                "content": message
            ])
        }

        var body: [String: Any] = [
            "model": configuration.model.rawValue,
            "messages": messages,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "top_p": configuration.topP,
            "frequency_penalty": configuration.frequencyPenalty,
            "presence_penalty": configuration.presencePenalty,
            "stream": configuration.streamEnabled
        ]

        // Add function calling if enabled
        if configuration.functionCallingEnabled && configuration.model.supportsFunctions {
            body["tools"] = activeTools.map { $0.toJSON() }
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildMultimodalContent(text: String, images: [UIImage]) -> [[String: Any]] {
        var content: [[String: Any]] = [["type": "text", "text": text]]

        for image in images {
            if let imageData = image.jpegData(compressionQuality: 0.7) {
                let base64Image = imageData.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                ])
            }
        }

        return content
    }

    private func performStreamingRequest(_ request: URLRequest) async {
        let startTime = Date()

        streamTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            Task { @MainActor in
                if let error = error {
                    await self.handleStreamError(error)
                    return
                }

                guard let data = data else { return }
                await self.processStreamData(data, startTime: startTime)
            }
        }

        streamTask?.resume()
    }

    private func processStreamData(_ data: Data, startTime: Date) async {
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []

        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" {
                    await finalizeStream(startTime: startTime)
                    continue
                }

                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any] {

                    // Handle function calls
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        await handleToolCalls(toolCalls)
                    }

                    // Handle content
                    if let content = delta["content"] as? String {
                        await appendStreamContent(content)
                    }
                }
            }
        }
    }

    private func appendStreamContent(_ content: String) async {
        streamingText += content
        streamingTokens.append(content)

        // Update or create streaming message
        if currentStreamingMessage == nil {
            currentStreamingMessage = ChatMessage(
                role: .assistant,
                content: streamingText,
                timestamp: Date()
            )
        } else {
            currentStreamingMessage?.content = streamingText
        }

        // Trigger haptic feedback for better UX
        if streamingTokens.count % 10 == 0 {
            HapticManager.shared.impact(.light)
        }
    }

    private func finalizeStream(startTime: Date) async {
        isProcessing = false

        if var message = currentStreamingMessage {
            message.metadata = MessageMetadata(
                model: configuration.model.rawValue,
                temperature: configuration.temperature,
                processingTime: Date().timeIntervalSince(startTime),
                cached: false
            )
            message.tokens = estimateTokenCount(message.content)

            conversationHistory.append(message)

            // Cache the response
            if configuration.cacheEnabled {
                cache.store(message)
            }

            // Update metrics
            metricsCollector.recordRequest(
                model: configuration.model,
                tokens: message.tokens ?? 0,
                latency: message.metadata?.processingTime ?? 0
            )
        }

        currentStreamingMessage = nil
    }

    // MARK: - Multi-Image Analysis
    func analyzeMultipleImages(_ images: [UIImage], prompt: String? = nil) async -> String {
        guard configuration.model.supportsVision else {
            return "Current model doesn't support vision. Please switch to GPT-4 Vision."
        }

        let analysisPrompt = prompt ?? """
        Analyze these \(images.count) images comprehensively:
        1. Describe what you see in each image
        2. Identify any relationships or patterns between the images
        3. Detect objects, people, text, and scenes
        4. Provide insights and recommendations
        5. Note any potential issues or interesting observations
        """

        isProcessing = true
        defer { isProcessing = false }

        do {
            let request = try await buildStreamingRequest(message: analysisPrompt, images: images)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ServiceError(
                    code: .apiError,
                    message: "Vision API error",
                    underlyingError: nil
                )
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }

            throw ServiceError(
                code: .invalidResponse,
                message: "Failed to parse vision response",
                underlyingError: nil
            )

        } catch {
            self.error = error as? ServiceError ?? ServiceError(
                code: .networkError,
                message: error.localizedDescription,
                underlyingError: error
            )
            return "Analysis failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Function Calling
    private func handleToolCalls(_ toolCalls: [[String: Any]]) async {
        for toolCall in toolCalls {
            guard let function = toolCall["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let arguments = function["arguments"] as? String else { continue }

            let functionCall = FunctionCall(name: name, arguments: arguments)
            functionCalls.append(functionCall)

            // Execute function based on name
            switch name {
            case "capture_photo":
                await executePhotoCapture(arguments: arguments)
            case "analyze_scene":
                await executeSceneAnalysis(arguments: arguments)
            case "identify_person":
                await executePersonIdentification(arguments: arguments)
            case "translate_text":
                await executeTextTranslation(arguments: arguments)
            default:
                print("Unknown function: \(name)")
            }
        }
    }

    private func executePhotoCapture(arguments: String) async {
        // Trigger Meta glasses camera
        NotificationCenter.default.post(
            name: .triggerGlassesCamera,
            object: nil,
            userInfo: ["arguments": arguments]
        )
    }

    private func executeSceneAnalysis(arguments: String) async {
        // Trigger scene analysis
        NotificationCenter.default.post(
            name: .analyzeCurrentScene,
            object: nil,
            userInfo: ["arguments": arguments]
        )
    }

    private func executePersonIdentification(arguments: String) async {
        // Trigger facial recognition
        NotificationCenter.default.post(
            name: .identifyPerson,
            object: nil,
            userInfo: ["arguments": arguments]
        )
    }

    private func executeTextTranslation(arguments: String) async {
        // Trigger text translation
        NotificationCenter.default.post(
            name: .translateText,
            object: nil,
            userInfo: ["arguments": arguments]
        )
    }

    // MARK: - Context Management
    private func compressContextIfNeeded() async {
        let totalTokens = conversationHistory.reduce(0) { $0 + ($1.tokens ?? estimateTokenCount($1.content)) }

        if totalTokens > configuration.model.contextWindow * 0.8 {
            // Summarize older messages
            let oldMessages = Array(conversationHistory.prefix(conversationHistory.count / 2))
            let summary = await summarizeMessages(oldMessages)

            // Replace old messages with summary
            conversationHistory = [
                ChatMessage(
                    role: .system,
                    content: "Previous conversation summary: \(summary)",
                    timestamp: Date()
                )
            ] + Array(conversationHistory.suffix(conversationHistory.count / 2))
        }
    }

    private func summarizeMessages(_ messages: [ChatMessage]) async -> String {
        let content = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")

        let summaryPrompt = """
        Summarize this conversation concisely, preserving key information and context:
        \(content)
        """

        // Use a smaller model for summarization
        let oldModel = configuration.model
        configuration.model = .gpt35Turbo
        defer { configuration.model = oldModel }

        return await quickChat(summaryPrompt)
    }

    private func quickChat(_ message: String) async -> String {
        // Non-streaming quick response
        do {
            let request = try await buildStreamingRequest(message: message, images: nil)
            let (data, _) = try await session.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        } catch {
            return "Summary failed"
        }

        return ""
    }

    private func getRelevantHistory() -> [ChatMessage] {
        // Smart history selection based on relevance and recency
        let maxMessages = 20

        if conversationHistory.count <= maxMessages {
            return conversationHistory
        }

        // Keep system messages, recent messages, and important context
        var relevant: [ChatMessage] = []

        // Always include system messages
        relevant += conversationHistory.filter { $0.role == .system }

        // Include recent messages
        let recentMessages = Array(conversationHistory.suffix(maxMessages - relevant.count))
        relevant += recentMessages

        return relevant
    }

    // MARK: - Error Handling
    private func handleStreamError(_ error: Error) async {
        isProcessing = false

        if configuration.autoRetry && retryManager.shouldRetry(error: error) {
            let delay = retryManager.nextRetryDelay()

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if let lastUserMessage = conversationHistory.last(where: { $0.role == .user }) {
                await streamChat(message: lastUserMessage.content, images: lastUserMessage.images)
            }
        } else {
            self.error = ServiceError(
                code: .networkError,
                message: "Stream failed: \(error.localizedDescription)",
                underlyingError: error
            )
        }
    }

    private func handleCachedResponse(_ response: ChatMessage) async {
        // Simulate streaming for cached responses
        let tokens = response.content.split(separator: " ")
        streamingText = ""

        for token in tokens {
            streamingText += "\(token) "
            streamingTokens.append(String(token))

            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        }

        var cachedMessage = response
        cachedMessage.metadata?.cached = true
        conversationHistory.append(cachedMessage)

        isProcessing = false
    }

    // MARK: - Metrics
    private func startMetricsCollection() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateConnectionQuality()
            }
            .store(in: &cancellables)
    }

    private func updateConnectionQuality() {
        let avgLatency = metricsCollector.averageLatency

        if avgLatency < 0.5 {
            connectionQuality = .excellent
        } else if avgLatency < 1.0 {
            connectionQuality = .good
        } else if avgLatency < 2.0 {
            connectionQuality = .fair
        } else {
            connectionQuality = .poor
        }
    }

    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }

    // MARK: - Public Methods
    func clearHistory() {
        conversationHistory = []
        memoryBank.clear()
        cache.clear()
        print("🗑️ Conversation cleared")
    }

    func exportConversation() -> String {
        return conversationHistory.map { msg in
            "\(msg.role.rawValue.uppercased()): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    func cancelStream() {
        streamTask?.cancel()
        isProcessing = false
        currentStreamingMessage = nil
    }
}

// MARK: - Supporting Types
struct SystemPrompt {
    let id: String
    let content: String
    let priority: Priority

    enum Priority: Int {
        case low = 0
        case medium = 1
        case high = 2
    }
}

struct AITool {
    let name: String
    let description: String
    let parameters: [String: Any]

    func toJSON() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": parameters
                ]
            ]
        ]
    }
}

class ResponseCache {
    private var cache: [String: ChatMessage] = [:]
    private let maxSize = 100

    func get(for query: String, images: [UIImage]?) -> ChatMessage? {
        let key = cacheKey(query: query, images: images)
        return cache[key]
    }

    func store(_ message: ChatMessage) {
        if cache.count >= maxSize {
            cache.removeValue(forKey: cache.keys.first ?? "")
        }

        let key = "\(message.content.prefix(50))"
        cache[key] = message
    }

    func clear() {
        cache.removeAll()
    }

    private func cacheKey(query: String, images: [UIImage]?) -> String {
        var key = query
        if let images = images {
            key += "_\(images.count)images"
        }
        return key
    }
}

class RateLimiter {
    private var requestTimes: [Date] = []
    private let maxRequests = 60
    private let timeWindow: TimeInterval = 60

    func canMakeRequest() -> Bool {
        let now = Date()
        requestTimes = requestTimes.filter { now.timeIntervalSince($0) < timeWindow }

        if requestTimes.count < maxRequests {
            requestTimes.append(now)
            return true
        }

        return false
    }
}

class RequestQueue {
    private var queue: [() async -> Void] = []
    private var isProcessing = false

    func enqueue(_ task: @escaping () async -> Void) {
        queue.append(task)
        processNext()
    }

    private func processNext() {
        guard !isProcessing, !queue.isEmpty else { return }

        isProcessing = true
        let task = queue.removeFirst()

        Task {
            await task()
            isProcessing = false
            processNext()
        }
    }
}

class MetricsCollector {
    private var requests: [RequestMetric] = []

    struct RequestMetric {
        let model: EnhancedOpenAIService.Model
        let tokens: Int
        let latency: TimeInterval
        let timestamp: Date
    }

    func recordRequest(model: EnhancedOpenAIService.Model, tokens: Int, latency: TimeInterval) {
        requests.append(RequestMetric(
            model: model,
            tokens: tokens,
            latency: latency,
            timestamp: Date()
        ))

        // Keep only last 1000 requests
        if requests.count > 1000 {
            requests = Array(requests.suffix(1000))
        }
    }

    var averageLatency: TimeInterval {
        guard !requests.isEmpty else { return 0 }
        let total = requests.reduce(0) { $0 + $1.latency }
        return total / Double(requests.count)
    }

    var totalTokensUsed: Int {
        return requests.reduce(0) { $0 + $1.tokens }
    }
}

class RetryManager {
    private var retryCount = 0
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0

    func shouldRetry(error: Error) -> Bool {
        guard retryCount < maxRetries else {
            retryCount = 0
            return false
        }

        // Check if error is retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                retryCount += 1
                return true
            default:
                return false
            }
        }

        return false
    }

    func nextRetryDelay() -> TimeInterval {
        // Exponential backoff with jitter
        let delay = baseDelay * pow(2.0, Double(retryCount - 1))
        let jitter = Double.random(in: 0...0.5)
        return delay + jitter
    }

    func reset() {
        retryCount = 0
    }
}

class MemoryBank {
    private var memories: [Memory] = []

    struct Memory {
        let id: UUID
        let content: String
        let context: String
        let timestamp: Date
        let importance: Double
    }

    func store(_ content: String, context: String, importance: Double = 0.5) {
        memories.append(Memory(
            id: UUID(),
            content: content,
            context: context,
            timestamp: Date(),
            importance: importance
        ))

        // Keep only most important memories if exceeding limit
        if memories.count > 100 {
            memories.sort { $0.importance > $1.importance }
            memories = Array(memories.prefix(100))
        }
    }

    func recall(context: String, limit: Int = 5) -> [Memory] {
        // Simple context matching - could be enhanced with embeddings
        return memories
            .filter { $0.context.lowercased().contains(context.lowercased()) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    func clear() {
        memories.removeAll()
    }
}

class HapticManager {
    static let shared = HapticManager()

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - Enums
enum ConnectionQuality {
    case excellent, good, fair, poor, offline

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .orange
        case .offline: return .red
        }
    }

    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .offline: return "Offline"
        }
    }
}

struct RequestMetrics {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var totalTokens: Int = 0
    var averageLatency: TimeInterval = 0
    var cacheHitRate: Double = 0
}

// MARK: - Notification Names
extension Notification.Name {
    static let triggerGlassesCamera = Notification.Name("triggerGlassesCamera")
    static let analyzeCurrentScene = Notification.Name("analyzeCurrentScene")
    static let identifyPerson = Notification.Name("identifyPerson")
    static let translateText = Notification.Name("translateText")
}