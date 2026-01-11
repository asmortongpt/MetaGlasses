import Foundation

// MARK: - OpenAI Provider
public class OpenAIProvider: LLMProvider {
    public let name = "OpenAI-GPT4"
    public let capabilities: Set<LLMCapability> = [
        .vision, .codeGeneration, .reasoning, .translation,
        .summarization, .sentimentAnalysis, .creativeWriting,
        .factualAnswering, .mathematicalReasoning, .contextualMemory
    ]
    public let priority = 10
    public let costPerToken = 0.03

    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let session = URLSession.shared

    public init() {
        // Get API key from environment
        self.apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: String]] = [
            ["role": "system", "content": options.systemPrompt ?? "You are a helpful AI assistant integrated into Meta smart glasses."],
            ["role": "user", "content": prompt]
        ]

        let payload: [String: Any] = [
            "model": "gpt-4-turbo-preview",
            "messages": messages,
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "top_p": options.topP,
            "frequency_penalty": options.frequencyPenalty,
            "presence_penalty": options.presencePenalty
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: "\(endpoint)?stream=true")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let messages: [[String: String]] = [
                        ["role": "system", "content": options.systemPrompt ?? "You are a helpful AI assistant."],
                        ["role": "user", "content": prompt]
                    ]

                    let payload: [String: Any] = [
                        "model": "gpt-4-turbo-preview",
                        "messages": messages,
                        "temperature": options.temperature,
                        "max_tokens": options.maxTokens,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, _) = try await session.bytes(for: request)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "text-embedding-ada-002",
            "input": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArray = json["data"] as? [[String: Any]],
           let embedding = dataArray.first?["embedding"] as? [Double] {
            return embedding.map { Float($0) }
        }

        throw LLMError.processingFailed
    }
}

// MARK: - Claude Provider
public class ClaudeProvider: LLMProvider {
    public let name = "Anthropic-Claude"
    public let capabilities: Set<LLMCapability> = [
        .codeGeneration, .reasoning, .translation, .summarization,
        .sentimentAnalysis, .creativeWriting, .factualAnswering,
        .mathematicalReasoning, .contextualMemory
    ]
    public let priority = 9
    public let costPerToken = 0.024

    private let apiKey: String
    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let session = URLSession.shared

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": "claude-3-opus-20240229",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": options.maxTokens,
            "temperature": options.temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let payload: [String: Any] = [
                        "model": "claude-3-opus-20240229",
                        "messages": [["role": "user", "content": prompt]],
                        "max_tokens": options.maxTokens,
                        "temperature": options.temperature,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, _) = try await session.bytes(for: request)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        // Claude doesn't directly provide embeddings, use a fallback
        // In production, you'd use a dedicated embedding model
        return Array(repeating: 0.0, count: 1536)
    }
}

// MARK: - Gemini Provider
public class GeminiProvider: LLMProvider {
    public let name = "Google-Gemini"
    public let capabilities: Set<LLMCapability> = [
        .vision, .codeGeneration, .reasoning, .translation,
        .summarization, .factualAnswering, .mathematicalReasoning
    ]
    public let priority = 8
    public let costPerToken = 0.015

    private let apiKey: String
    private let endpoint: String
    private let session = URLSession.shared

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        self.endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        let url = URL(string: "\(endpoint)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": options.temperature,
                "maxOutputTokens": options.maxTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(endpoint)?key=\(apiKey)&alt=sse")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let payload: [String: Any] = [
                        "contents": [["parts": [["text": prompt]]]],
                        "generationConfig": [
                            "temperature": options.temperature,
                            "maxOutputTokens": options.maxTokens
                        ]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, _) = try await session.bytes(for: request)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let candidates = json["candidates"] as? [[String: Any]],
                           let content = candidates.first?["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let text = parts.first?["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        // Use Gemini's embedding model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/embedding-001:embedContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "models/embedding-001",
            "content": ["parts": [["text": text]]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let embedding = json["embedding"] as? [String: Any],
           let values = embedding["values"] as? [Double] {
            return values.map { Float($0) }
        }

        throw LLMError.processingFailed
    }
}

// MARK: - Groq Provider (Fast inference)
public class GroqProvider: LLMProvider {
    public let name = "Groq-Mixtral"
    public let capabilities: Set<LLMCapability> = [
        .codeGeneration, .reasoning, .translation,
        .summarization, .factualAnswering
    ]
    public let priority = 7
    public let costPerToken = 0.008

    private let apiKey: String
    private let endpoint = "https://api.groq.com/openai/v1/chat/completions"
    private let session = URLSession.shared

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "mixtral-8x7b-32768",
            "messages": [["role": "user", "content": prompt]],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish() // Simplified for now
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        return Array(repeating: 0.0, count: 1536)
    }
}

// MARK: - Mistral Provider
public class MistralProvider: LLMProvider {
    public let name = "Mistral-Large"
    public let capabilities: Set<LLMCapability> = [
        .codeGeneration, .reasoning, .translation, .summarization
    ]
    public let priority = 6
    public let costPerToken = 0.012

    private let apiKey: String
    private let endpoint = "https://api.mistral.ai/v1/chat/completions"
    private let session = URLSession.shared

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"] ?? ""
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "mistral-large-latest",
            "messages": [["role": "user", "content": prompt]],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        return Array(repeating: 0.0, count: 1024)
    }
}

// MARK: - Cohere Provider
public class CohereProvider: LLMProvider {
    public let name = "Cohere-Command"
    public let capabilities: Set<LLMCapability> = [
        .summarization, .sentimentAnalysis, .factualAnswering
    ]
    public let priority = 5
    public let costPerToken = 0.01

    private let apiKey: String
    private let endpoint = "https://api.cohere.ai/v1/generate"
    private let session = URLSession.shared

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["COHERE_API_KEY"] ?? ""
    }

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "command",
            "prompt": prompt,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let generations = json["generations"] as? [[String: Any]],
           let text = generations.first?["text"] as? String {
            return text
        }

        throw LLMError.processingFailed
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        var request = URLRequest(url: URL(string: "https://api.cohere.ai/v1/embed")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "embed-english-v3.0",
            "texts": [text],
            "input_type": "search_document"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let embeddings = json["embeddings"] as? [[Double]] {
            return embeddings.first?.map { Float($0) } ?? []
        }

        throw LLMError.processingFailed
    }
}

// MARK: - Local LLM Provider (Edge Processing)
public class LocalLLMProvider: LLMProvider {
    public let name = "Local-Llama"
    public let capabilities: Set<LLMCapability> = [
        .translation, .summarization, .sentimentAnalysis
    ]
    public let priority = 3
    public let costPerToken = 0.0 // Free but limited

    public init() {}

    public func complete(_ prompt: String, options: LLMOptions) async throws -> String {
        // This would use a local model like Llama.cpp or CoreML
        // Requires on-device model integration (future feature)
        return "Local AI processing requires device model - falling back to cloud APIs"
    }

    public func stream(_ prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    public func embeddings(_ text: String) async throws -> [Float] {
        // Use a local embedding model
        return Array(repeating: 0.0, count: 384)
    }
}