import Foundation
import Speech
import AVFoundation
import UIKit

/// Production-grade Voice Assistant with Speech Recognition + ChatGPT + TTS
@MainActor
class VoiceAssistantService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcript = ""
    @Published var lastResponse = ""
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var error: String?

    // MARK: - Services
    private let openAI: OpenAIService
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Context awareness
    private var currentImage: UIImage?
    private var currentLocation: String?

    // MARK: - Initialization
    override init() {
        self.openAI = OpenAIService()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        super.init()

        speechSynthesizer.delegate = self
        requestPermissions()

        print("✅ Voice Assistant initialized")
    }

    // MARK: - Permissions
    private func requestPermissions() {
        // Speech recognition
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    self.error = "Speech recognition not available"
                    print("❌ Speech recognition: \(status)")
                @unknown default:
                    break
                }
            }
        }

        // Microphone
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("✅ Microphone access granted")
            } else {
                print("❌ Microphone access denied")
            }
        }
    }

    // MARK: - Start Listening
    func startListening() {
        guard !isListening else { return }

        // Stop any ongoing speech
        if isSpeaking {
            stopSpeaking()
        }

        do {
            // Cancel previous task
            recognitionTask?.cancel()
            recognitionTask = nil

            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }

            recognitionRequest.shouldReportPartialResults = true

            // Get input node
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Install tap
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()

            // Start recognition
            guard let speechRecognizer = speechRecognizer else { return }

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    Task { @MainActor in
                        self.transcript = result.bestTranscription.formattedString
                    }

                    // If final result, process it
                    if result.isFinal {
                        Task {
                            await self.processVoiceCommand(self.transcript)
                        }
                    }
                }

                if error != nil {
                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }

            isListening = true
            print("🎤 Listening started...")

        } catch {
            self.error = "Failed to start voice recognition: \(error.localizedDescription)"
            print("❌ \(error)")
        }
    }

    // MARK: - Stop Listening
    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        isListening = false
        print("🎤 Listening stopped")
    }

    // MARK: - Process Voice Command
    private func processVoiceCommand(_ command: String) async {
        guard !command.isEmpty else { return }

        print("💬 Processing: \(command)")

        // Add user message to history
        let userMessage = ConversationMessage(role: .user, content: command)
        conversationHistory.append(userMessage)

        do {
            // Build context-aware prompt
            var systemPrompt = """
            You are an intelligent AI assistant integrated into Meta Ray-Ban smart glasses.
            You can see what the user sees and help with various tasks.
            Be concise, helpful, and conversational.
            """

            if let image = currentImage {
                systemPrompt += "\nThe user is currently looking at an image/scene."
            }

            if let location = currentLocation {
                systemPrompt += "\nThe user is at: \(location)"
            }

            // Prepare messages for OpenAI
            var messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt]
            ]

            // Add conversation history (last 10 messages)
            let recentHistory = conversationHistory.suffix(10)
            for msg in recentHistory {
                messages.append(["role": msg.role.rawValue, "content": msg.content])
            }

            // Get AI response
            let response = try await openAI.chatCompletion(
                messages: messages,
                model: .gpt4Turbo,
                temperature: 0.8,
                maxTokens: 500
            )

            // Add assistant response to history
            let assistantMessage = ConversationMessage(role: .assistant, content: response)
            conversationHistory.append(assistantMessage)

            lastResponse = response

            // Speak the response
            await speak(response)

            print("✅ Response: \(response)")

        } catch {
            let errorMsg = "Sorry, I encountered an error: \(error.localizedDescription)"
            self.error = errorMsg
            await speak(errorMsg)
            print("❌ \(error)")
        }
    }

    // MARK: - Text-to-Speech
    func speak(_ text: String, rate: Float = 0.5, volume: Float = 1.0) async {
        guard !text.isEmpty else { return }

        await MainActor.run {
            isSpeaking = true
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.volume = volume
        utterance.pitchMultiplier = 1.0

        // Use higher quality voice if available
        if let voice = AVSpeechSynthesisVoice(identifier: AVSpeechSynthesisVoiceIdentifierAlex) {
            utterance.voice = voice
        }

        speechSynthesizer.speak(utterance)

        print("🔊 Speaking: \(text)")
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Context Setting
    func setCurrentImage(_ image: UIImage?) {
        self.currentImage = image
    }

    func setCurrentLocation(_ location: String?) {
        self.currentLocation = location
    }

    // MARK: - Conversation Management
    func clearConversation() {
        conversationHistory.removeAll()
        transcript = ""
        lastResponse = ""
        print("🗑️ Conversation cleared")
    }

    func sendTextMessage(_ text: String) async {
        transcript = text
        await processVoiceCommand(text)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceAssistantService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            print("🔊 Speaking finished")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            print("🔊 Speaking cancelled")
        }
    }
}

// MARK: - Conversation Models
struct ConversationMessage: Identifiable, Codable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date = Date()

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }
}
