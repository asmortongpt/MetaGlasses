import Foundation
import Combine

/// Enhanced LLM Router
/// Intelligent model selection, load balancing, failover, and cost optimization
@MainActor
public class EnhancedLLMRouter: ObservableObject {

    // MARK: - Singleton
    public static let shared = EnhancedLLMRouter()

    // MARK: - Published Properties
    @Published public var activeProvider: LLMProvider = .openAI
    @Published public var providerHealth: [LLMProvider: ProviderHealthStatus] = [:]
    @Published public var routingMetrics: RoutingMetrics

    // MARK: - Private Properties
    private let baseOrchestrator = LLMOrchestrator()
    private var requestQueue: [QueuedRequest] = []
    private var providerLoadBalancer: LoadBalancer
    private var costTracker: CostTracker
    private var failoverManager: FailoverManager

    // Rate limiting
    private var requestCounts: [LLMProvider: Int] = [:]
    private var lastResetTime: Date = Date()
    private let rateLimitWindow: TimeInterval = 60 // 1 minute

    // Circuit breaker
    private var circuitBreakers: [LLMProvider: CircuitBreaker] = [:]

    // MARK: - Initialization
    private init() {
        self.providerLoadBalancer = LoadBalancer()
        self.costTracker = CostTracker()
        self.failoverManager = FailoverManager()
        self.routingMetrics = RoutingMetrics()

        // Initialize circuit breakers
        for provider in LLMProvider.allCases {
            circuitBreakers[provider] = CircuitBreaker(provider: provider)
            providerHealth[provider] = .healthy
        }

        print("🔀 EnhancedLLMRouter initialized")
        startHealthMonitoring()
    }

    // MARK: - Intelligent Routing

    /// Route request to optimal provider with intelligent selection
    public func route(
        messages: [[String: String]],
        task: TaskType = .fast,
        priority: RequestPriority = .normal,
        maxCost: Double? = nil,
        requirementHints: RoutingHints? = nil
    ) async throws -> LLMResponse {
        // Update rate limits
        resetRateLimitsIfNeeded()

        // Select optimal provider
        let provider = try selectOptimalProvider(
            task: task,
            priority: priority,
            maxCost: maxCost,
            hints: requirementHints
        )

        // Check circuit breaker
        guard let breaker = circuitBreakers[provider],
              breaker.canAttempt() else {
            throw RoutingError.providerUnavailable(provider)
        }

        // Execute request with retries and fallback
        do {
            let response = try await executeWithRetry(
                provider: provider,
                messages: messages,
                task: task,
                maxRetries: 2
            )

            // Record success
            breaker.recordSuccess()
            updateMetrics(provider: provider, success: true, cost: response.cost)

            return response

        } catch {
            // Record failure
            breaker.recordFailure()
            updateMetrics(provider: provider, success: false, cost: 0)

            // Try failover
            return try await handleFailover(
                provider: provider,
                messages: messages,
                task: task,
                originalError: error
            )
        }
    }

    // MARK: - Provider Selection

    private func selectOptimalProvider(
        task: TaskType,
        priority: RequestPriority,
        maxCost: Double?,
        hints: RoutingHints?
    ) throws -> LLMProvider {
        // Get available providers
        let availableProviders = getAvailableProviders()

        guard !availableProviders.isEmpty else {
            throw RoutingError.noProvidersAvailable
        }

        // Score each provider
        var providerScores: [(LLMProvider, Double)] = []

        for provider in availableProviders {
            var score: Double = 0

            // Task suitability (0-40 points)
            score += calculateTaskSuitability(provider: provider, task: task) * 40

            // Cost efficiency (0-25 points)
            if let maxCost = maxCost {
                score += calculateCostScore(provider: provider, maxCost: maxCost) * 25
            } else {
                score += 12.5 // Neutral
            }

            // Load balance (0-20 points)
            score += providerLoadBalancer.getLoadScore(provider: provider) * 20

            // Health status (0-15 points)
            score += getHealthScore(provider: provider) * 15

            providerScores.append((provider, score))
        }

        // Sort by score
        providerScores.sort { $0.1 > $1.1 }

        // Apply priority boost
        if priority == .high {
            // Prefer more capable providers for high priority
            if providerScores.contains(where: { $0.0 == .anthropic }) {
                return .anthropic
            }
        }

        // Return best provider
        guard let best = providerScores.first else {
            throw RoutingError.noProvidersAvailable
        }

        activeProvider = best.0
        return best.0
    }

    private func calculateTaskSuitability(provider: LLMProvider, task: TaskType) -> Double {
        // Task-specific provider strengths
        switch task {
        case .vision:
            switch provider {
            case .openAI: return 1.0
            case .gemini: return 0.9
            case .anthropic: return 0.5
            }

        case .longContext:
            switch provider {
            case .anthropic: return 1.0
            case .openAI: return 0.8
            case .gemini: return 0.6
            }

        case .creative:
            switch provider {
            case .openAI: return 1.0
            case .anthropic: return 0.9
            case .gemini: return 0.7
            }

        case .analytical:
            switch provider {
            case .anthropic: return 1.0
            case .openAI: return 0.9
            case .gemini: return 0.7
            }

        case .fast:
            switch provider {
            case .gemini: return 1.0
            case .openAI: return 0.8
            case .anthropic: return 0.6
            }

        case .coding:
            switch provider {
            case .openAI: return 1.0
            case .anthropic: return 0.8
            case .gemini: return 0.6
            }
        }
    }

    private func calculateCostScore(provider: LLMProvider, maxCost: Double) -> Double {
        let estimatedCost = costTracker.estimateCost(provider: provider, tokens: 1000)

        if estimatedCost > maxCost {
            return 0
        }

        // Higher score for lower cost
        return 1.0 - (estimatedCost / maxCost)
    }

    private func getHealthScore(provider: LLMProvider) -> Double {
        guard let status = providerHealth[provider] else {
            return 0.5
        }

        switch status {
        case .healthy: return 1.0
        case .degraded: return 0.5
        case .unhealthy: return 0.1
        }
    }

    private func getAvailableProviders() -> [LLMProvider] {
        return LLMProvider.allCases.filter { provider in
            // Check rate limits
            guard !isRateLimited(provider: provider) else {
                return false
            }

            // Check circuit breaker
            guard let breaker = circuitBreakers[provider],
                  breaker.state != .open else {
                return false
            }

            // Check health
            guard let health = providerHealth[provider],
                  health != .unhealthy else {
                return false
            }

            return true
        }
    }

    // MARK: - Execution with Retry

    private func executeWithRetry(
        provider: LLMProvider,
        messages: [[String: String]],
        task: TaskType,
        maxRetries: Int
    ) async throws -> LLMResponse {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Add to load balancer
                providerLoadBalancer.recordRequest(provider: provider)

                // Execute via base orchestrator
                let response = try await baseOrchestrator.chat(
                    messages: messages,
                    task: task
                )

                // Track cost
                costTracker.recordCost(provider: provider, cost: response.cost)

                return response

            } catch {
                lastError = error
                print("⚠️ Attempt \(attempt + 1) failed for \(provider): \(error)")

                // Wait before retry with exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? RoutingError.executionFailed
    }

    // MARK: - Failover Handling

    private func handleFailover(
        provider: LLMProvider,
        messages: [[String: String]],
        task: TaskType,
        originalError: Error
    ) async throws -> LLMResponse {
        print("🔄 Initiating failover from \(provider)...")

        // Get failover sequence
        let failoverProviders = failoverManager.getFailoverSequence(
            primaryProvider: provider,
            availableProviders: getAvailableProviders()
        )

        // Try each failover provider
        for fallbackProvider in failoverProviders {
            do {
                print("🔄 Trying fallback: \(fallbackProvider)")

                let response = try await executeWithRetry(
                    provider: fallbackProvider,
                    messages: messages,
                    task: task,
                    maxRetries: 1
                )

                print("✅ Failover successful: \(fallbackProvider)")
                routingMetrics.failoversSuccessful += 1

                return response

            } catch {
                print("❌ Failover to \(fallbackProvider) failed")
                continue
            }
        }

        // All failovers exhausted
        routingMetrics.failoversFailed += 1
        throw RoutingError.allFailoversFailed(originalError: originalError)
    }

    // MARK: - Rate Limiting

    private func isRateLimited(provider: LLMProvider) -> Bool {
        let limit = getRateLimit(provider: provider)
        let current = requestCounts[provider] ?? 0
        return current >= limit
    }

    private func getRateLimit(provider: LLMProvider) -> Int {
        // Requests per minute
        switch provider {
        case .openAI: return 60
        case .anthropic: return 50
        case .gemini: return 100
        }
    }

    private func resetRateLimitsIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastResetTime) >= rateLimitWindow {
            requestCounts = [:]
            lastResetTime = now
        }
    }

    // MARK: - Health Monitoring

    private func startHealthMonitoring() {
        Task {
            while true {
                await checkProviderHealth()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }

    private func checkProviderHealth() async {
        for provider in LLMProvider.allCases {
            let health = await performHealthCheck(provider: provider)
            providerHealth[provider] = health
        }
    }

    private func performHealthCheck(provider: LLMProvider) async -> ProviderHealthStatus {
        // Simple health check with test request
        do {
            let testMessages = [["role": "user", "content": "test"]]
            _ = try await baseOrchestrator.chat(messages: testMessages, task: .fast)
            return .healthy
        } catch {
            // Check circuit breaker
            if let breaker = circuitBreakers[provider] {
                if breaker.failureCount > 5 {
                    return .unhealthy
                } else if breaker.failureCount > 2 {
                    return .degraded
                }
            }
            return .healthy
        }
    }

    // MARK: - Metrics

    private func updateMetrics(provider: LLMProvider, success: Bool, cost: Double) {
        routingMetrics.totalRequests += 1

        if success {
            routingMetrics.successfulRequests += 1
        } else {
            routingMetrics.failedRequests += 1
        }

        routingMetrics.totalCost += cost
        routingMetrics.providerUsage[provider, default: 0] += 1
    }

    // MARK: - Public Metrics

    public func getMetrics() -> RoutingMetrics {
        return routingMetrics
    }

    public func getCostSummary() -> CostSummary {
        return costTracker.getSummary()
    }

    public func getProviderStats() -> [LLMProvider: ProviderStats] {
        var stats: [LLMProvider: ProviderStats] = [:]

        for provider in LLMProvider.allCases {
            stats[provider] = ProviderStats(
                requestCount: routingMetrics.providerUsage[provider] ?? 0,
                health: providerHealth[provider] ?? .healthy,
                loadScore: providerLoadBalancer.getLoadScore(provider: provider),
                circuitBreakerState: circuitBreakers[provider]?.state ?? .closed
            )
        }

        return stats
    }
}

// MARK: - Supporting Components

private class LoadBalancer {
    private var requestCounts: [LLMProvider: Int] = [:]

    func recordRequest(provider: LLMProvider) {
        requestCounts[provider, default: 0] += 1
    }

    func getLoadScore(provider: LLMProvider) -> Double {
        let currentLoad = requestCounts[provider] ?? 0
        let maxLoad = requestCounts.values.max() ?? 1

        // Higher score for lower load
        return 1.0 - (Double(currentLoad) / Double(max(maxLoad, 1)))
    }
}

private class CostTracker {
    private var providerCosts: [LLMProvider: Double] = [:]
    private var totalCost: Double = 0

    func recordCost(provider: LLMProvider, cost: Double) {
        providerCosts[provider, default: 0] += cost
        totalCost += cost
    }

    func estimateCost(provider: LLMProvider, tokens: Int) -> Double {
        let tokensDouble = Double(tokens)

        switch provider {
        case .openAI: return tokensDouble * 0.00001
        case .anthropic: return tokensDouble * 0.000015
        case .gemini: return 0
        }
    }

    func getSummary() -> CostSummary {
        return CostSummary(
            totalCost: totalCost,
            costByProvider: providerCosts
        )
    }
}

private class FailoverManager {
    func getFailoverSequence(
        primaryProvider: LLMProvider,
        availableProviders: [LLMProvider]
    ) -> [LLMProvider] {
        // Define failover preferences
        let preferences: [LLMProvider: [LLMProvider]] = [
            .openAI: [.anthropic, .gemini],
            .anthropic: [.openAI, .gemini],
            .gemini: [.openAI, .anthropic]
        ]

        guard let preferred = preferences[primaryProvider] else {
            return availableProviders.filter { $0 != primaryProvider }
        }

        return preferred.filter { availableProviders.contains($0) }
    }
}

private class CircuitBreaker {
    let provider: LLMProvider
    var state: CircuitBreakerState = .closed
    var failureCount: Int = 0
    var lastFailureTime: Date?

    private let failureThreshold = 5
    private let recoveryTimeout: TimeInterval = 60

    init(provider: LLMProvider) {
        self.provider = provider
    }

    func canAttempt() -> Bool {
        switch state {
        case .closed:
            return true

        case .open:
            // Check if recovery timeout has passed
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) > recoveryTimeout {
                state = .halfOpen
                return true
            }
            return false

        case .halfOpen:
            return true
        }
    }

    func recordSuccess() {
        failureCount = 0
        state = .closed
    }

    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()

        if failureCount >= failureThreshold {
            state = .open
            print("⚠️ Circuit breaker OPEN for \(provider)")
        }
    }
}

// MARK: - Supporting Types

public struct RoutingMetrics {
    public var totalRequests: Int = 0
    public var successfulRequests: Int = 0
    public var failedRequests: Int = 0
    public var totalCost: Double = 0
    public var failoversSuccessful: Int = 0
    public var failoversFailed: Int = 0
    public var providerUsage: [LLMProvider: Int] = [:]
}

public struct RoutingHints {
    public let preferredProvider: LLMProvider?
    public let requireStreamingResponse: Bool
    public let maxLatency: TimeInterval?

    public init(preferredProvider: LLMProvider? = nil, requireStreamingResponse: Bool = false, maxLatency: TimeInterval? = nil) {
        self.preferredProvider = preferredProvider
        self.requireStreamingResponse = requireStreamingResponse
        self.maxLatency = maxLatency
    }
}

public struct CostSummary {
    public let totalCost: Double
    public let costByProvider: [LLMProvider: Double]
}

public struct ProviderStats {
    public let requestCount: Int
    public let health: ProviderHealthStatus
    public let loadScore: Double
    public let circuitBreakerState: CircuitBreakerState
}

private struct QueuedRequest {
    let id: UUID
    let messages: [[String: String]]
    let task: TaskType
    let priority: RequestPriority
    let timestamp: Date
}

// MARK: - Enums

public enum ProviderHealthStatus {
    case healthy, degraded, unhealthy
}

public enum CircuitBreakerState {
    case closed, open, halfOpen
}

public enum RequestPriority {
    case low, normal, high
}

public enum RoutingError: LocalizedError {
    case noProvidersAvailable
    case providerUnavailable(LLMProvider)
    case executionFailed
    case allFailoversFailed(originalError: Error)

    public var errorDescription: String? {
        switch self {
        case .noProvidersAvailable:
            return "No LLM providers available"
        case .providerUnavailable(let provider):
            return "\(provider.rawValue) is unavailable"
        case .executionFailed:
            return "Request execution failed"
        case .allFailoversFailed(let error):
            return "All failover attempts failed. Original error: \(error.localizedDescription)"
        }
    }
}
