import Foundation
import UIKit

/// Production-grade OpenAI API service with GPT-4, GPT-4 Vision, and streaming support
@MainActor
class OpenAIService: ObservableObject {
    // MARK: - Properties
    @Published var isProcessing = false
    @Published var lastError: String?

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession

    // Rate limiting
    private var requestCount = 0
    private var lastResetTime = Date()
    private let maxRequestsPerMinute = 50

    // MARK: - Models
    enum Model: String {
        case gpt4 = "gpt-4"
        case gpt4Turbo = "gpt-4-turbo-preview"
        case gpt4Vision = "gpt-4-vision-preview"
        case gpt35Turbo = "gpt-3.5-turbo"

        var costPerToken: Double {
            switch self {
            case .gpt4: return 0.00003
            case .gpt4Turbo: return 0.00001
            case .gpt4Vision: return 0.00001
            case .gpt35Turbo: return 0.0000015
            }
        }
    }

    // MARK: - Initialization
    init(apiKey: String? = nil) {
        // Try to load from environment or use provided key
        if let key = apiKey {
            self.apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            self.apiKey = envKey
        } else {
            // Fallback to hardcoded key from user's .env (PRODUCTION ONLY - normally use keychain)
            self.apiKey = "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"
        }

        // Configure session with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        print("✅ OpenAI Service initialized")
    }

    // MARK: - Chat Completion
    func chatCompletion(
        messages: [[String: String]],
        model: Model = .gpt4Turbo,
        temperature: Double = 0.7,
        maxTokens: Int = 1000
    ) async throws -> String {
        try await checkRateLimit()

        isProcessing = true
        defer { isProcessing = false }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ OpenAI API Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        print("✅ OpenAI response received (\(content.count) chars)")
        return content
    }

    // MARK: - Vision Analysis
    func analyzeImage(
        _ image: UIImage,
        prompt: String = "Describe this image in detail",
        model: Model = .gpt4Vision
    ) async throws -> String {
        try await checkRateLimit()

        isProcessing = true
        defer { isProcessing = false }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw OpenAIError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)",
                            "detail": "high"
                        ]
                    ]
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": messages,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Vision API Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        print("✅ Vision analysis completed")
        return content
    }

    // MARK: - Streaming Chat
    func streamChatCompletion(
        messages: [[String: String]],
        model: Model = .gpt4Turbo,
        onChunk: @escaping (String) -> Void
    ) async throws {
        try await checkRateLimit()

        isProcessing = true
        defer { isProcessing = false }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": messages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAIError.invalidResponse
        }

        // Parse SSE stream
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))

                if data == "[DONE]" {
                    break
                }

                guard let jsonData = data.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any],
                      let content = delta["content"] as? String else {
                    continue
                }

                await MainActor.run {
                    onChunk(content)
                }
            }
        }

        print("✅ Streaming completed")
    }

    // MARK: - Embeddings
    func createEmbedding(text: String) async throws -> [Double] {
        try await checkRateLimit()

        let url = URL(string: "\(baseURL)/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "text-embedding-ada-002",
            "input": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]],
              let first = dataArray.first,
              let embedding = first["embedding"] as? [Double] else {
            throw OpenAIError.parseError
        }

        return embedding
    }

    // MARK: - Rate Limiting
    private func checkRateLimit() async throws {
        let now = Date()

        // Reset counter every minute
        if now.timeIntervalSince(lastResetTime) >= 60 {
            requestCount = 0
            lastResetTime = now
        }

        guard requestCount < maxRequestsPerMinute else {
            let waitTime = 60 - now.timeIntervalSince(lastResetTime)
            print("⚠️ Rate limit reached. Waiting \(Int(waitTime))s...")
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            requestCount = 0
            lastResetTime = Date()
        }

        requestCount += 1
    }
}

// MARK: - Error Types
enum OpenAIError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case imageConversionFailed
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .parseError:
            return "Failed to parse OpenAI response"
        case .imageConversionFailed:
            return "Failed to convert image to required format"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait."
        }
    }
}
