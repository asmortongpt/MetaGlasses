import Foundation
import UIKit

/// Real LLM Integration - OpenAI, Claude, Gemini
/// Provides intelligent analysis and natural language understanding
@MainActor
public class LLMIntegration {

    // MARK: - Singleton
    public static let shared = LLMIntegration()

    // MARK: - Properties
    private let openAIKey: String
    private let claudeKey: String
    private let geminiKey: String

    // API Endpoints
    private let openAIEndpoint = "https://api.openai.com/v1/chat/completions"
    private let claudeEndpoint = "https://api.anthropic.com/v1/messages"
    private let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"

    // MARK: - Initialization
    private init() {
        // Load keys from environment
        self.openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        self.claudeKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] ?? ""
        self.geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""

        print("🤖 LLM Integration initialized with multiple providers")
    }

    // MARK: - Image Analysis

    /// Analyze image with GPT-4 Vision
    public func analyzeImageWithGPT4Vision(_ image: UIImage, prompt: String = "Describe this image in detail") async throws -> String {
        guard !openAIKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw LLMError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Create request
        let payload: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                        ]
                    ]
                ]
            ],
            "max_tokens": 500
        ]

        let response = try await makeOpenAIRequest(payload: payload)

        return response
    }

    /// Analyze image with Claude Vision
    public func analyzeImageWithClaude(_ image: UIImage, prompt: String = "Describe this image") async throws -> String {
        guard !claudeKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw LLMError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Create request
        let payload: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let response = try await makeClaudeRequest(payload: payload)

        return response
    }

    /// Analyze image with Gemini Vision
    public func analyzeImageWithGemini(_ image: UIImage, prompt: String = "Describe this image") async throws -> String {
        guard !geminiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw LLMError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Create request
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let response = try await makeGeminiRequest(payload: payload)

        return response
    }

    // MARK: - Text Generation

    /// Generate text response using best available model
    public func generateResponse(prompt: String, context: String? = nil) async throws -> String {
        // Try Claude first (best quality)
        if !claudeKey.isEmpty {
            return try await generateWithClaude(prompt: prompt, context: context)
        }

        // Fallback to GPT-4
        if !openAIKey.isEmpty {
            return try await generateWithGPT4(prompt: prompt, context: context)
        }

        // Fallback to Gemini
        if !geminiKey.isEmpty {
            return try await generateWithGemini(prompt: prompt, context: context)
        }

        throw LLMError.noAPIKeysAvailable
    }

    private func generateWithClaude(prompt: String, context: String?) async throws -> String {
        var messages: [[String: Any]] = []

        if let context = context {
            messages.append([
                "role": "user",
                "content": "Context: \(context)"
            ])
        }

        messages.append([
            "role": "user",
            "content": prompt
        ])

        let payload: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": messages
        ]

        return try await makeClaudeRequest(payload: payload)
    }

    private func generateWithGPT4(prompt: String, context: String?) async throws -> String {
        var messages: [[String: Any]] = []

        if let context = context {
            messages.append([
                "role": "system",
                "content": context
            ])
        }

        messages.append([
            "role": "user",
            "content": prompt
        ])

        let payload: [String: Any] = [
            "model": "gpt-4",
            "messages": messages,
            "max_tokens": 500
        ]

        return try await makeOpenAIRequest(payload: payload)
    }

    private func generateWithGemini(prompt: String, context: String?) async throws -> String {
        let fullPrompt = context != nil ? "\(context!)\n\n\(prompt)" : prompt

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ]
        ]

        return try await makeGeminiRequest(payload: payload)
    }

    // MARK: - API Requests

    private func makeOpenAIRequest(payload: [String: Any]) async throws -> String {
        guard let url = URL(string: openAIEndpoint) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content
    }

    private func makeClaudeRequest(payload: [String: Any]) async throws -> String {
        guard let url = URL(string: claudeEndpoint) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(claudeKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }

        return text
    }

    private func makeGeminiRequest(payload: [String: Any]) async throws -> String {
        guard let url = URL(string: "\(geminiEndpoint)?key=\(geminiKey)") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw LLMError.invalidResponse
        }

        return text
    }
}

// MARK: - Supporting Types

public enum LLMError: LocalizedError {
    case missingAPIKey
    case imageConversionFailed
    case invalidURL
    case requestFailed
    case invalidResponse
    case noAPIKeysAvailable

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not configured"
        case .imageConversionFailed: return "Failed to convert image"
        case .invalidURL: return "Invalid API URL"
        case .requestFailed: return "API request failed"
        case .invalidResponse: return "Invalid API response"
        case .noAPIKeysAvailable: return "No LLM API keys available"
        }
    }
}
