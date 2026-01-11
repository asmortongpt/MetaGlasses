import Foundation
import Combine
import CoreML
import NaturalLanguage

// MARK: - Multi-LLM Orchestrator Protocol
public protocol MultiLLMOrchestratorProtocol {
    func process(_ input: LLMInput) async throws -> LLMResponse
    func processWithConsensus(_ input: LLMInput) async throws -> ConsensusResponse
    func streamResponse(_ input: LLMInput) -> AsyncThrowingStream<String, Error>
}

// MARK: - LLM Provider Protocol
public protocol LLMProvider {
    var name: String { get }
    var capabilities: Set<LLMCapability> { get }
    var priority: Int { get }
    var costPerToken: Double { get }

    func complete(_ prompt: String, options: LLMOptions) async throws -> String
    func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error>
    func embeddings(_ text: String) async throws -> [Float]
}

// MARK: - Models
public enum LLMCapability: String, CaseIterable {
    case vision
    case codeGeneration
    case reasoning
    case translation
    case summarization
    case sentimentAnalysis
    case creativeWriting
    case factualAnswering
    case mathematicalReasoning
    case contextualMemory
}

public struct LLMInput {
    public let prompt: String
    public let context: [String]?
    public let images: [Data]?
    public let requiredCapabilities: Set<LLMCapability>
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?

    public init(prompt: String,
                context: [String]? = nil,
                images: [Data]? = nil,
                requiredCapabilities: Set<LLMCapability> = [],
                temperature: Double = 0.7,
                maxTokens: Int = 2000,
                systemPrompt: String? = nil) {
        self.prompt = prompt
        self.context = context
        self.images = images
        self.requiredCapabilities = requiredCapabilities
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }
}

public struct LLMOptions {
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double
    let systemPrompt: String?
    let stopSequences: [String]?
}

public struct LLMResponse {
    public let text: String
    public let provider: String
    public let confidence: Double
    public let tokensUsed: Int
    public let latency: TimeInterval
    public let metadata: [String: Any]
}

public struct ConsensusResponse {
    public let consensus: String
    public let individualResponses: [LLMResponse]
    public let confidence: Double
    public let reasoning: String
}

// MARK: - Multi-LLM Orchestrator Implementation
@MainActor
public final class MultiLLMOrchestrator: MultiLLMOrchestratorProtocol {

    // MARK: - Properties
    private var providers: [LLMProvider] = []
    private let cache = LLMResponseCache()
    private let rateLimiter = RateLimiter()
    private let loadBalancer = LoadBalancer()
    private let qualityMonitor = QualityMonitor()
    private let cancellables = Set<AnyCancellable>()

    // Configuration
    private let maxRetries = 3
    private let timeoutInterval: TimeInterval = 30
    private let consensusThreshold = 0.7

    // MARK: - Initialization
    public init() {
        setupProviders()
        setupMonitoring()
    }

    private func setupProviders() {
        // Register all LLM providers
        providers = [
            OpenAIProvider(),
            ClaudeProvider(),
            GeminiProvider(),
            GroqProvider(),
            MistralProvider(),
            CohereProvider(),
            LocalLLMProvider() // For edge processing
        ]
    }

    private func setupMonitoring() {
        qualityMonitor.startMonitoring()
    }

    // MARK: - Public Methods
    public func process(_ input: LLMInput) async throws -> LLMResponse {
        // Check cache first
        if let cached = await cache.get(for: input) {
            return cached
        }

        // Select optimal provider based on requirements
        let provider = try selectOptimalProvider(for: input)

        // Process with retry logic
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let response = try await processWithProvider(provider, input: input)

                // Cache successful response
                await cache.store(response, for: input)

                // Update quality metrics
                await qualityMonitor.recordSuccess(provider: provider.name, latency: response.latency)

                return response
            } catch {
                lastError = error
                await qualityMonitor.recordFailure(provider: provider.name, error: error)

                if attempt < maxRetries {
                    // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                }
            }
        }

        throw lastError ?? LLMError.processingFailed
    }

    public func processWithConsensus(_ input: LLMInput) async throws -> ConsensusResponse {
        // Get responses from multiple providers
        let selectedProviders = selectProvidersForConsensus(for: input)

        async let responses = withThrowingTaskGroup(of: LLMResponse?.self) { group in
            for provider in selectedProviders {
                group.addTask {
                    do {
                        return try await self.processWithProvider(provider, input: input)
                    } catch {
                        // Log error but don't fail the entire consensus
                        print("Provider \(provider.name) failed: \(error)")
                        return nil
                    }
                }
            }

            var results: [LLMResponse] = []
            for try await response in group {
                if let response = response {
                    results.append(response)
                }
            }
            return results
        }

        let validResponses = try await responses

        // Analyze and build consensus
        let consensus = try await buildConsensus(from: validResponses, input: input)

        return consensus
    }

    public func streamResponse(_ input: LLMInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let provider = try selectOptimalProvider(for: input)
                    let stream = provider.stream(input.prompt, options: LLMOptions(
                        temperature: input.temperature,
                        maxTokens: input.maxTokens,
                        topP: 0.9,
                        frequencyPenalty: 0.0,
                        presencePenalty: 0.0,
                        systemPrompt: input.systemPrompt,
                        stopSequences: nil
                    ))

                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods
    private func selectOptimalProvider(for input: LLMInput) throws -> LLMProvider {
        // Filter providers by capabilities
        let capableProviders = providers.filter { provider in
            input.requiredCapabilities.isSubset(of: provider.capabilities)
        }

        guard !capableProviders.isEmpty else {
            throw LLMError.noCapableProvider
        }

        // Use load balancer to select based on current load and performance
        let metrics = loadBalancer.getCurrentMetrics()

        // Score providers based on multiple factors
        let scoredProviders = capableProviders.map { provider -> (provider: LLMProvider, score: Double) in
            var score = 100.0

            // Factor in priority
            score += Double(provider.priority) * 10

            // Factor in cost
            score -= provider.costPerToken * 1000

            // Factor in current load
            if let load = metrics[provider.name] {
                score -= load * 20
            }

            // Factor in historical performance
            let performance = qualityMonitor.getPerformanceScore(for: provider.name)
            score += performance * 30

            return (provider, score)
        }

        // Select provider with highest score
        guard let best = scoredProviders.max(by: { $0.score < $1.score }) else {
            throw LLMError.selectionFailed
        }

        return best.provider
    }

    private func selectProvidersForConsensus(for input: LLMInput, count: Int = 3) -> [LLMProvider] {
        let capableProviders = providers.filter { provider in
            input.requiredCapabilities.isSubset(of: provider.capabilities)
        }

        // Sort by priority and take top N
        return Array(capableProviders.sorted { $0.priority > $1.priority }.prefix(count))
    }

    private func processWithProvider(_ provider: LLMProvider, input: LLMInput) async throws -> LLMResponse {
        let startTime = Date()

        // Apply rate limiting
        try await rateLimiter.acquire(for: provider.name)

        // Build prompt with context
        let fullPrompt = buildFullPrompt(from: input)

        // Get completion
        let text = try await provider.complete(fullPrompt, options: LLMOptions(
            temperature: input.temperature,
            maxTokens: input.maxTokens,
            topP: 0.9,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0,
            systemPrompt: input.systemPrompt,
            stopSequences: nil
        ))

        let latency = Date().timeIntervalSince(startTime)

        return LLMResponse(
            text: text,
            provider: provider.name,
            confidence: calculateConfidence(text: text, provider: provider),
            tokensUsed: estimateTokens(text: text),
            latency: latency,
            metadata: [
                "model": provider.name,
                "temperature": input.temperature,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }

    private func buildFullPrompt(from input: LLMInput) -> String {
        var prompt = ""

        // Add context if available
        if let context = input.context {
            prompt += "Context:\n"
            for ctx in context {
                prompt += "- \(ctx)\n"
            }
            prompt += "\n"
        }

        // Add main prompt
        prompt += input.prompt

        return prompt
    }

    private func buildConsensus(from responses: [LLMResponse], input: LLMInput) async throws -> ConsensusResponse {
        guard !responses.isEmpty else {
            throw LLMError.noResponses
        }

        // Use semantic similarity to find consensus
        let embeddings = try await generateEmbeddings(for: responses.map { $0.text })
        let similarity = calculateSemanticSimilarity(embeddings)

        // If high similarity, use weighted average
        if similarity > consensusThreshold {
            let weightedConsensus = generateWeightedConsensus(responses)

            return ConsensusResponse(
                consensus: weightedConsensus,
                individualResponses: responses,
                confidence: similarity,
                reasoning: "High agreement between models (similarity: \(String(format: "%.2f", similarity)))"
            )
        } else {
            // Use meta-reasoning to reconcile differences
            let metaReasoning = try await performMetaReasoning(responses, input: input)

            return ConsensusResponse(
                consensus: metaReasoning.conclusion,
                individualResponses: responses,
                confidence: metaReasoning.confidence,
                reasoning: metaReasoning.reasoning
            )
        }
    }

    private func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        // Use the first provider that supports embeddings
        guard let provider = providers.first(where: { $0.capabilities.contains(.contextualMemory) }) else {
            throw LLMError.noEmbeddingProvider
        }

        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await provider.embeddings(text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    private func calculateSemanticSimilarity(_ embeddings: [[Float]]) -> Double {
        guard embeddings.count >= 2 else { return 1.0 }

        var totalSimilarity = 0.0
        var comparisons = 0

        for i in 0..<embeddings.count {
            for j in (i+1)..<embeddings.count {
                let similarity = cosineSimilarity(embeddings[i], embeddings[j])
                totalSimilarity += similarity
                comparisons += 1
            }
        }

        return comparisons > 0 ? totalSimilarity / Double(comparisons) : 0.0
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        guard normA > 0 && normB > 0 else { return 0.0 }

        return Double(dotProduct / (sqrt(normA) * sqrt(normB)))
    }

    private func generateWeightedConsensus(_ responses: [LLMResponse]) -> String {
        // For now, return the response with highest confidence
        // In production, this would use more sophisticated merging
        return responses.max(by: { $0.confidence < $1.confidence })?.text ?? ""
    }

    private func performMetaReasoning(_ responses: [LLMResponse], input: LLMInput) async throws -> (conclusion: String, confidence: Double, reasoning: String) {
        // Use a high-capability model to analyze disagreements
        let metaPrompt = """
        Multiple AI models provided different answers to this question:
        "\(input.prompt)"

        Responses:
        \(responses.enumerated().map { "Model \($0.offset + 1): \($0.element.text)" }.joined(separator: "\n\n"))

        Please analyze these responses and provide:
        1. The most likely correct answer
        2. Your reasoning for this conclusion
        3. A confidence score (0-1)
        """

        let metaInput = LLMInput(
            prompt: metaPrompt,
            requiredCapabilities: [.reasoning, .factualAnswering],
            temperature: 0.3
        )

        let metaResponse = try await process(metaInput)

        // Parse the response (simplified for example)
        return (
            conclusion: metaResponse.text,
            confidence: 0.8,
            reasoning: "Meta-analysis of multiple model outputs"
        )
    }

    private func calculateConfidence(text: String, provider: LLMProvider) -> Double {
        // Simplified confidence calculation
        // In production, this would use more sophisticated metrics
        var confidence = 0.5

        // Check response length
        if text.count > 100 {
            confidence += 0.1
        }

        // Check for uncertainty markers
        let uncertaintyMarkers = ["might", "maybe", "possibly", "could be", "not sure"]
        for marker in uncertaintyMarkers {
            if text.lowercased().contains(marker) {
                confidence -= 0.1
            }
        }

        // Factor in provider's historical performance
        let performance = qualityMonitor.getPerformanceScore(for: provider.name)
        confidence += performance * 0.2

        return max(0.0, min(1.0, confidence))
    }

    private func estimateTokens(text: String) -> Int {
        // Rough estimation: 1 token ≈ 4 characters
        return text.count / 4
    }
}

// MARK: - Supporting Classes
private class LLMResponseCache {
    private var cache: [String: LLMResponse] = [:]
    private let queue = DispatchQueue(label: "llm.cache", attributes: .concurrent)
    private let maxCacheSize = 100
    private let ttl: TimeInterval = 300 // 5 minutes

    func get(for input: LLMInput) async -> LLMResponse? {
        let key = cacheKey(for: input)
        return queue.sync {
            if let cached = cache[key],
               let timestamp = cached.metadata["timestamp"] as? TimeInterval,
               Date().timeIntervalSince1970 - timestamp < ttl {
                return cached
            }
            return nil
        }
    }

    func store(_ response: LLMResponse, for input: LLMInput) async {
        let key = cacheKey(for: input)
        queue.async(flags: .barrier) {
            self.cache[key] = response

            // Evict old entries if cache is too large
            if self.cache.count > self.maxCacheSize {
                self.evictOldest()
            }
        }
    }

    private func cacheKey(for input: LLMInput) -> String {
        return "\(input.prompt)-\(input.temperature)-\(input.maxTokens)"
    }

    private func evictOldest() {
        // Simple LRU eviction
        if let oldest = cache.min(by: { a, b in
            let timeA = a.value.metadata["timestamp"] as? TimeInterval ?? 0
            let timeB = b.value.metadata["timestamp"] as? TimeInterval ?? 0
            return timeA < timeB
        }) {
            cache.removeValue(forKey: oldest.key)
        }
    }
}

private class RateLimiter {
    private var limits: [String: (requests: Int, resetTime: Date)] = [:]
    private let queue = DispatchQueue(label: "llm.ratelimit", attributes: .concurrent)

    func acquire(for provider: String) async throws {
        // Simplified rate limiting
        queue.sync {
            let now = Date()
            if let limit = limits[provider] {
                if now < limit.resetTime && limit.requests >= 10 {
                    // Wait until reset
                    Thread.sleep(forTimeInterval: limit.resetTime.timeIntervalSince(now))
                }
            }

            if limits[provider] == nil || Date() >= limits[provider]!.resetTime {
                limits[provider] = (1, Date().addingTimeInterval(60))
            } else {
                limits[provider]!.requests += 1
            }
        }
    }
}

private class LoadBalancer {
    private var metrics: [String: Double] = [:]

    func getCurrentMetrics() -> [String: Double] {
        return metrics
    }

    func updateLoad(for provider: String, load: Double) {
        metrics[provider] = load
    }
}

private class QualityMonitor {
    private var successRates: [String: (successes: Int, failures: Int)] = [:]
    private var latencies: [String: [TimeInterval]] = [:]

    func startMonitoring() {
        // Start background monitoring
    }

    func recordSuccess(provider: String, latency: TimeInterval) async {
        successRates[provider, default: (0, 0)].successes += 1
        latencies[provider, default: []].append(latency)

        // Keep only recent latencies
        if latencies[provider]!.count > 100 {
            latencies[provider]!.removeFirst()
        }
    }

    func recordFailure(provider: String, error: Error) async {
        successRates[provider, default: (0, 0)].failures += 1
    }

    func getPerformanceScore(for provider: String) -> Double {
        guard let rates = successRates[provider] else { return 0.5 }

        let total = rates.successes + rates.failures
        guard total > 0 else { return 0.5 }

        let successRate = Double(rates.successes) / Double(total)

        // Factor in latency
        if let providerLatencies = latencies[provider], !providerLatencies.isEmpty {
            let avgLatency = providerLatencies.reduce(0, +) / Double(providerLatencies.count)
            let latencyScore = max(0, 1.0 - (avgLatency / 10.0)) // Normalize to 0-1

            return (successRate + latencyScore) / 2.0
        }

        return successRate
    }
}

// MARK: - Errors
public enum LLMError: LocalizedError {
    case noCapableProvider
    case processingFailed
    case selectionFailed
    case noResponses
    case noEmbeddingProvider
    case timeout
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .noCapableProvider:
            return "No LLM provider available with required capabilities"
        case .processingFailed:
            return "Failed to process LLM request"
        case .selectionFailed:
            return "Failed to select optimal provider"
        case .noResponses:
            return "No responses received from providers"
        case .noEmbeddingProvider:
            return "No provider available for embeddings"
        case .timeout:
            return "Request timed out"
        case .rateLimited:
            return "Rate limit exceeded"
        }
    }
}