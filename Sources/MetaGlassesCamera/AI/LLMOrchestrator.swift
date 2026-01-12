import Foundation
import UIKit

/// Multi-LLM orchestration layer with intelligent model selection and fallback
@MainActor
class LLMOrchestrator: ObservableObject {
    // MARK: - Published Properties
    @Published var currentProvider: LLMProvider = .openAI
    @Published var isProcessing = false
    @Published var totalCost: Double = 0
    @Published var requestCount: [LLMProvider: Int] = [:]

    // MARK: - Provider Services
    private var openAIService: OpenAIService
    private var anthropicService: AnthropicService?
    private var geminiService: GeminiService?

    // MARK: - Configuration
    private let costLimit: Double = 10.0  // $10 daily limit
    private var dailyCost: Double = 0
    private var lastResetDate: Date = Date()

    // MARK: - Initialization
    init() {
        // Initialize OpenAI (primary)
        self.openAIService = OpenAIService()

        // Initialize Claude/Anthropic if API key available
        if let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? getAnthropicKey() {
            self.anthropicService = AnthropicService(apiKey: anthropicKey)
        }

        // Initialize Gemini if API key available
        if let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? getGeminiKey() {
            self.geminiService = GeminiService(apiKey: geminiKey)
        }

        print("✅ LLM Orchestrator initialized")
        print("   • OpenAI: ✓")
        print("   • Anthropic: \(anthropicService != nil ? "✓" : "✗")")
        print("   • Gemini: \(geminiService != nil ? "✓" : "✗")")
    }

    // MARK: - Intelligent Model Selection
    func selectBestModel(for task: TaskType, contextLength: Int = 0) -> (LLMProvider, String) {
        // Reset daily cost if new day
        checkDailyReset()

        // Check cost limits
        guard dailyCost < costLimit else {
            print("⚠️ Daily cost limit reached, using free tier")
            return (.gemini, "gemini-pro")
        }

        switch task {
        case .vision:
            // Vision tasks: prefer GPT-4 Vision > Gemini Pro Vision
            if geminiService != nil && dailyCost > costLimit * 0.7 {
                return (.gemini, "gemini-pro-vision")
            }
            return (.openAI, "gpt-4-vision-preview")

        case .longContext:
            // Long context: prefer Claude (200k) > GPT-4 Turbo (128k) > Gemini (32k)
            if contextLength > 100000, anthropicService != nil {
                return (.anthropic, "claude-3-opus-20240229")
            } else if contextLength > 30000 {
                return (.openAI, "gpt-4-turbo-preview")
            }
            return (.gemini, "gemini-pro")

        case .creative:
            // Creative tasks: prefer GPT-4 > Claude
            if dailyCost < costLimit * 0.5 {
                return (.openAI, "gpt-4")
            } else if anthropicService != nil {
                return (.anthropic, "claude-3-sonnet-20240229")
            }
            return (.gemini, "gemini-pro")

        case .analytical:
            // Analytical: prefer Claude > GPT-4
            if anthropicService != nil, dailyCost < costLimit * 0.6 {
                return (.anthropic, "claude-3-opus-20240229")
            }
            return (.openAI, "gpt-4-turbo-preview")

        case .fast:
            // Fast responses: prefer GPT-3.5 > Gemini Flash
            if dailyCost < costLimit * 0.3 {
                return (.openAI, "gpt-3.5-turbo")
            }
            return (.gemini, "gemini-pro")

        case .coding:
            // Code generation: prefer GPT-4 > Claude
            return (.openAI, "gpt-4-turbo-preview")
        }
    }

    // MARK: - Unified Chat Interface
    func chat(
        messages: [[String: String]],
        task: TaskType = .fast,
        temperature: Double = 0.7
    ) async throws -> LLMResponse {
        isProcessing = true
        defer { isProcessing = false }

        let contextLength = messages.reduce(0) { $0 + ($1["content"]?.count ?? 0) }
        let (provider, model) = selectBestModel(for: task, contextLength: contextLength)

        currentProvider = provider

        do {
            let response: LLMResponse

            switch provider {
            case .openAI:
                let content = try await openAIService.chatCompletion(
                    messages: messages,
                    model: OpenAIService.Model(rawValue: model) ?? .gpt4Turbo,
                    temperature: temperature
                )
                response = LLMResponse(
                    content: content,
                    provider: provider,
                    model: model,
                    tokensUsed: estimateTokens(content),
                    cost: calculateCost(provider: provider, tokens: estimateTokens(content))
                )

            case .anthropic:
                guard let service = anthropicService else {
                    throw LLMError.providerUnavailable(provider)
                }
                let content = try await service.chat(messages: messages, model: model)
                response = LLMResponse(
                    content: content,
                    provider: provider,
                    model: model,
                    tokensUsed: estimateTokens(content),
                    cost: calculateCost(provider: provider, tokens: estimateTokens(content))
                )

            case .gemini:
                guard let service = geminiService else {
                    throw LLMError.providerUnavailable(provider)
                }
                let content = try await service.chat(messages: messages)
                response = LLMResponse(
                    content: content,
                    provider: provider,
                    model: model,
                    tokensUsed: estimateTokens(content),
                    cost: 0  // Gemini free tier
                )
            }

            // Update metrics
            updateMetrics(provider: provider, cost: response.cost)

            print("✅ Response from \(provider) (\(model)): \(response.content.prefix(50))...")
            return response

        } catch {
            // Fallback logic
            print("❌ \(provider) failed: \(error.localizedDescription)")
            return try await fallbackChat(messages: messages, failedProvider: provider)
        }
    }

    // MARK: - Vision Analysis with Fallback
    func analyzeImage(
        _ image: UIImage,
        prompt: String = "Describe this image"
    ) async throws -> LLMResponse {
        isProcessing = true
        defer { isProcessing = false }

        let (provider, model) = selectBestModel(for: .vision)
        currentProvider = provider

        do {
            let content: String

            switch provider {
            case .openAI:
                content = try await openAIService.analyzeImage(image, prompt: prompt)

            case .gemini:
                guard let service = geminiService else {
                    throw LLMError.providerUnavailable(provider)
                }
                content = try await service.analyzeImage(image, prompt: prompt)

            case .anthropic:
                // Claude doesn't have native vision yet, fall back to OpenAI
                content = try await openAIService.analyzeImage(image, prompt: prompt)
            }

            let response = LLMResponse(
                content: content,
                provider: provider,
                model: model,
                tokensUsed: estimateTokens(content),
                cost: calculateCost(provider: provider, tokens: estimateTokens(content))
            )

            updateMetrics(provider: provider, cost: response.cost)
            return response

        } catch {
            print("❌ Vision analysis failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Fallback Logic
    private func fallbackChat(messages: [[String: String]], failedProvider: LLMProvider) async throws -> LLMResponse {
        print("🔄 Attempting fallback...")

        // Try providers in order: OpenAI -> Anthropic -> Gemini
        let fallbackOrder: [LLMProvider] = [.openAI, .anthropic, .gemini].filter { $0 != failedProvider }

        for provider in fallbackOrder {
            do {
                currentProvider = provider

                switch provider {
                case .openAI:
                    let content = try await openAIService.chatCompletion(messages: messages)
                    return LLMResponse(content: content, provider: provider, model: "gpt-4-turbo-preview", tokensUsed: estimateTokens(content), cost: 0)

                case .anthropic:
                    guard let service = anthropicService else { continue }
                    let content = try await service.chat(messages: messages)
                    return LLMResponse(content: content, provider: provider, model: "claude-3-sonnet", tokensUsed: estimateTokens(content), cost: 0)

                case .gemini:
                    guard let service = geminiService else { continue }
                    let content = try await service.chat(messages: messages)
                    return LLMResponse(content: content, provider: provider, model: "gemini-pro", tokensUsed: estimateTokens(content), cost: 0)
                }
            } catch {
                print("❌ Fallback to \(provider) failed: \(error.localizedDescription)")
                continue
            }
        }

        throw LLMError.allProvidersFailed
    }

    // MARK: - Utilities
    private func checkDailyReset() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            dailyCost = 0
            lastResetDate = Date()
            print("🔄 Daily cost reset")
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }

    private func calculateCost(provider: LLMProvider, tokens: Int) -> Double {
        let tokensDouble = Double(tokens)

        switch provider {
        case .openAI:
            return tokensDouble * 0.00001  // GPT-4 Turbo average
        case .anthropic:
            return tokensDouble * 0.000015  // Claude average
        case .gemini:
            return 0  // Free tier
        }
    }

    private func updateMetrics(provider: LLMProvider, cost: Double) {
        dailyCost += cost
        totalCost += cost
        requestCount[provider, default: 0] += 1
    }

    // MARK: - API Key Helpers
    private func getAnthropicKey() -> String? {
        return "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"
    }

    private func getGeminiKey() -> String? {
        return "AIzaSyAroZt3ZPjdxeohpzV1fFhsONws2-HfldU"
    }
}

// MARK: - Enums
enum LLMProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"
}

enum TaskType {
    case vision
    case longContext
    case creative
    case analytical
    case fast
    case coding
}

// MARK: - Models
struct LLMResponse {
    let content: String
    let provider: LLMProvider
    let model: String
    let tokensUsed: Int
    let cost: Double
    let timestamp: Date = Date()
}

enum LLMError: LocalizedError {
    case providerUnavailable(LLMProvider)
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider):
            return "\(provider.rawValue) is not available"
        case .allProvidersFailed:
            return "All LLM providers failed"
        }
    }
}

// MARK: - Anthropic Service (Production)
class AnthropicService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func chat(messages: [[String: String]], model: String = "claude-3-5-sonnet-20241022") async throws -> String {
        // Convert messages format
        var anthropicMessages: [[String: Any]] = []
        var systemMessage: String? = nil

        for message in messages {
            if let role = message["role"], let content = message["content"] {
                if role == "system" {
                    systemMessage = content
                } else {
                    anthropicMessages.append([
                        "role": role == "assistant" ? "assistant" : "user",
                        "content": content
                    ])
                }
            }
        }

        // Build request
        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var payload: [String: Any] = [
            "model": model,
            "messages": anthropicMessages,
            "max_tokens": 1024
        ]

        if let system = systemMessage {
            payload["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AnthropicService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AnthropicService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw NSError(domain: "AnthropicService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        return text
    }
}

// MARK: - Gemini Service (Production)
class GeminiService {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func chat(messages: [[String: String]]) async throws -> String {
        // Convert messages to Gemini format
        var contents: [[String: Any]] = []

        for message in messages {
            if let role = message["role"], let content = message["content"] {
                let geminiRole = role == "assistant" ? "model" : "user"
                contents.append([
                    "role": geminiRole,
                    "parts": [["text": content]]
                ])
            }
        }

        // Build request
        let url = URL(string: "\(baseURL)/models/gemini-pro:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": contents
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        return text
    }

    func analyzeImage(_ image: UIImage, prompt: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"])
        }

        let base64Image = imageData.base64EncodedString()

        // Build request for Gemini Pro Vision
        let url = URL(string: "\(baseURL)/models/gemini-pro-vision:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64Image
                        ]
                    ]
                ]
            ]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        return text
    }
}
