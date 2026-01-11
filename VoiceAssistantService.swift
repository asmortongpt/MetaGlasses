import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import Accelerate
import NaturalLanguage

// MARK: - Advanced Voice Assistant with Wake Word Detection
@MainActor
class VoiceAssistantService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcript = ""
    @Published var interimTranscript = ""
    @Published var voiceActivityDetected = false
    @Published var wakeWordDetected = false
    @Published var listeningMode: ListeningMode = .manual
    @Published var voiceProfile: VoiceProfile = .default
    @Published var audioLevel: Float = 0.0
    @Published var noiseLevel: Float = 0.0
    @Published var signalQuality: SignalQuality = .excellent
    @Published var processingState: ProcessingState = .idle

    // MARK: - Private Properties
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    // Wake word detection
    private var wakeWordDetector: WakeWordDetector
    private let wakeWords = ["hey meta", "okay glasses", "hey glasses", "meta", "assistant"]
    private var continuousListeningTimer: Timer?

    // Audio processing
    private var audioBuffer = AudioBuffer()
    private let audioProcessor = AudioProcessor()
    private let noiseReducer = NoiseReducer()
    private let voiceEnhancer = VoiceEnhancer()

    // Advanced features
    private var commandRecognizer = CommandRecognizer()
    private var contextManager = ContextManager()
    private var intentClassifier = IntentClassifier()
    private var emotionDetector = EmotionDetector()
    private let languageDetector = NLLanguageRecognizer()

    // Cancellables
    private var cancellables = Set<AnyCancellable>()

    // Configuration
    private var configuration = Configuration()

    // MARK: - Types
    enum ListeningMode {
        case manual
        case wakeWord
        case continuous
        case conversation
        case ambient

        var description: String {
            switch self {
            case .manual: return "Manual"
            case .wakeWord: return "Wake Word"
            case .continuous: return "Always On"
            case .conversation: return "Conversation"
            case .ambient: return "Ambient"
            }
        }
    }

    struct VoiceProfile {
        var pitch: Float
        var rate: Float
        var volume: Float
        var voice: AVSpeechSynthesisVoice?

        static let `default` = VoiceProfile(
            pitch: 1.0,
            rate: 0.52,
            volume: 0.9,
            voice: AVSpeechSynthesisVoice(language: "en-US")
        )

        static let friendly = VoiceProfile(
            pitch: 1.1,
            rate: 0.54,
            volume: 0.9,
            voice: AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-compact")
        )

        static let professional = VoiceProfile(
            pitch: 0.95,
            rate: 0.5,
            volume: 0.85,
            voice: AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Daniel-compact")
        )
    }

    enum SignalQuality {
        case excellent, good, fair, poor, noSignal

        var description: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            case .noSignal: return "No Signal"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .yellow
            case .poor: return .orange
            case .noSignal: return .red
            }
        }
    }

    enum ProcessingState {
        case idle
        case listening
        case processing
        case speaking
        case error(String)

        var description: String {
            switch self {
            case .idle: return "Ready"
            case .listening: return "Listening..."
            case .processing: return "Processing..."
            case .speaking: return "Speaking..."
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    struct Configuration {
        var enableWakeWord = true
        var enableContinuousListening = false
        var enableNoiseReduction = true
        var enableVoiceEnhancement = true
        var enableEmotionDetection = true
        var enableMultiLanguage = true
        var confidenceThreshold: Float = 0.7
        var silenceTimeout: TimeInterval = 2.0
        var maxRecordingDuration: TimeInterval = 60.0
        var preferredLanguage = "en-US"
        var alternativeLanguages = ["es-ES", "fr-FR", "de-DE", "zh-CN", "ja-JP"]
    }

    // MARK: - Initialization
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        self.wakeWordDetector = WakeWordDetector(wakeWords: wakeWords)

        super.init()

        setupAudioSession()
        setupSpeechSynthesizer()
        setupAudioProcessing()
        setupLanguageDetection()
        requestPermissions()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Configure for optimal voice processing
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
    }

    private func setupAudioProcessing() {
        // Configure audio processor for real-time processing
        audioProcessor.configure(sampleRate: 48000, bufferSize: 1024)

        // Setup noise reduction
        noiseReducer.noiseThreshold = 0.1
        noiseReducer.reductionFactor = 0.8

        // Setup voice enhancement
        voiceEnhancer.enhancementLevel = .medium
        voiceEnhancer.clarityBoost = true
    }

    private func setupLanguageDetection() {
        languageDetector.languageConstraints = [.english, .spanish, .french, .german, .chinese, .japanese]
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    self?.processingState = .error("Speech recognition denied")
                case .restricted:
                    self?.processingState = .error("Speech recognition restricted")
                case .notDetermined:
                    self?.processingState = .error("Speech recognition not determined")
                @unknown default:
                    break
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                Task { @MainActor in
                    self.processingState = .error("Microphone access denied")
                }
            }
        }
    }

    // MARK: - Public Methods
    func startListening(mode: ListeningMode = .manual) {
        guard !isListening else { return }

        self.listeningMode = mode
        isListening = true
        processingState = .listening
        transcript = ""
        interimTranscript = ""

        switch mode {
        case .wakeWord:
            startWakeWordDetection()
        case .continuous:
            startContinuousListening()
        case .conversation:
            startConversationMode()
        case .ambient:
            startAmbientListening()
        case .manual:
            startManualListening()
        }
    }

    func stopListening() {
        isListening = false
        processingState = .idle
        wakeWordDetected = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        continuousListeningTimer?.invalidate()
        wakeWordDetector.stop()
    }

    func speak(_ text: String, voice: VoiceProfile? = nil) {
        guard !text.isEmpty else { return }

        isSpeaking = true
        processingState = .speaking

        let utterance = AVSpeechUtterance(string: text)
        let profile = voice ?? voiceProfile

        utterance.rate = profile.rate
        utterance.pitchMultiplier = profile.pitch
        utterance.volume = profile.volume

        if let voice = profile.voice {
            utterance.voice = voice
        }

        // Add natural pauses
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        speechSynthesizer.speak(utterance)
    }

    func processCommand(_ command: String) async -> CommandResult {
        processingState = .processing

        // Detect language
        let language = detectLanguage(command)

        // Extract intent
        let intent = await intentClassifier.classify(command, language: language)

        // Get context
        let context = contextManager.getCurrentContext()

        // Recognize command
        let result = await commandRecognizer.recognize(
            command: command,
            intent: intent,
            context: context
        )

        processingState = .idle
        return result
    }

    // MARK: - Wake Word Detection
    private func startWakeWordDetection() {
        wakeWordDetector.start { [weak self] detected in
            if detected {
                Task { @MainActor in
                    self?.handleWakeWordDetected()
                }
            }
        }

        startAudioCapture(for: .wakeWord)
    }

    private func handleWakeWordDetected() {
        wakeWordDetected = true
        HapticManager.shared.impact(.medium)

        // Play activation sound
        playActivationSound()

        // Switch to active listening
        listeningMode = .conversation
        startActiveListening()

        // Auto-stop after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.maxRecordingDuration) { [weak self] in
            if self?.isListening == true {
                self?.stopListening()
            }
        }
    }

    private func playActivationSound() {
        // Play a subtle activation chime
        let systemSoundID: SystemSoundID = 1113
        AudioServicesPlaySystemSound(systemSoundID)
    }

    // MARK: - Continuous Listening
    private func startContinuousListening() {
        startAudioCapture(for: .continuous)

        // Setup continuous recognition
        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest!,
            resultHandler: handleContinuousRecognition
        )
    }

    private func handleContinuousRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else {
            if let error = error {
                processingState = .error(error.localizedDescription)
            }
            return
        }

        let bestTranscription = result.bestTranscription
        interimTranscript = bestTranscription.formattedString

        if result.isFinal {
            transcript = bestTranscription.formattedString

            // Process the final transcript
            Task {
                let command = await processCommand(transcript)
                handleCommandResult(command)
            }

            // Restart listening if in continuous mode
            if listeningMode == .continuous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startContinuousListening()
                }
            }
        }

        // Update voice activity
        voiceActivityDetected = !bestTranscription.formattedString.isEmpty
    }

    // MARK: - Conversation Mode
    private func startConversationMode() {
        startAudioCapture(for: .conversation)

        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest!
        ) { [weak self] result, error in
            self?.handleConversationRecognition(result: result, error: error)
        }
    }

    private func handleConversationRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else { return }

        interimTranscript = result.bestTranscription.formattedString

        // Detect end of speech
        if detectEndOfSpeech(result: result) {
            transcript = result.bestTranscription.formattedString

            // Process and respond
            Task {
                let response = await generateResponse(for: transcript)
                speak(response)
            }
        }
    }

    private func detectEndOfSpeech(result: SFSpeechRecognitionResult) -> Bool {
        // Check for natural pause
        if let lastSegment = result.bestTranscription.segments.last {
            let timeSinceLastWord = Date().timeIntervalSince(Date(timeIntervalSinceReferenceDate: lastSegment.timestamp + lastSegment.duration))
            return timeSinceLastWord > configuration.silenceTimeout
        }
        return false
    }

    // MARK: - Ambient Listening
    private func startAmbientListening() {
        startAudioCapture(for: .ambient)

        // Listen for specific triggers or keywords
        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest!
        ) { [weak self] result, error in
            self?.handleAmbientRecognition(result: result, error: error)
        }
    }

    private func handleAmbientRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else { return }

        let text = result.bestTranscription.formattedString.lowercased()

        // Check for ambient triggers
        let triggers = ["help", "emergency", "stop", "reminder", "note"]
        for trigger in triggers {
            if text.contains(trigger) {
                handleAmbientTrigger(trigger: trigger, fullText: text)
                break
            }
        }
    }

    private func handleAmbientTrigger(trigger: String, fullText: String) {
        // Process ambient trigger
        switch trigger {
        case "emergency":
            handleEmergencyCommand()
        case "reminder":
            createReminder(from: fullText)
        case "note":
            createNote(from: fullText)
        default:
            break
        }
    }

    // MARK: - Manual Listening
    private func startManualListening() {
        startAudioCapture(for: .manual)

        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest!
        ) { [weak self] result, error in
            self?.handleManualRecognition(result: result, error: error)
        }
    }

    private func handleManualRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else { return }

        interimTranscript = result.bestTranscription.formattedString

        if result.isFinal {
            transcript = result.bestTranscription.formattedString
            stopListening()
        }
    }

    // MARK: - Audio Capture
    private func startAudioCapture(for mode: ListeningMode) {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else { return }

        // Configure request
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        recognitionRequest.taskHint = mode == .conversation ? .dictation : .search

        // Add context if available
        if let contextualStrings = contextManager.getContextualStrings() {
            recognitionRequest.contextualStrings = contextualStrings
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap with audio processing
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            processingState = .error("Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Extract audio levels
        updateAudioLevels(from: buffer)

        // Apply noise reduction if enabled
        if configuration.enableNoiseReduction {
            noiseReducer.process(buffer)
        }

        // Apply voice enhancement if enabled
        if configuration.enableVoiceEnhancement {
            voiceEnhancer.process(buffer)
        }

        // Detect voice activity
        voiceActivityDetected = audioProcessor.detectVoiceActivity(in: buffer)

        // Process for wake word if enabled
        if configuration.enableWakeWord && !wakeWordDetected {
            wakeWordDetector.process(buffer)
        }

        // Store in buffer for analysis
        audioBuffer.append(buffer)
    }

    private func updateAudioLevels(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var rms: Float = 0

        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        Task { @MainActor in
            self.audioLevel = rms
            self.updateSignalQuality(rms: rms)
        }
    }

    private func updateSignalQuality(rms: Float) {
        let snr = audioLevel / max(noiseLevel, 0.001)

        if snr > 20 {
            signalQuality = .excellent
        } else if snr > 10 {
            signalQuality = .good
        } else if snr > 5 {
            signalQuality = .fair
        } else if snr > 2 {
            signalQuality = .poor
        } else {
            signalQuality = .noSignal
        }
    }

    // MARK: - Language Detection
    private func detectLanguage(_ text: String) -> String {
        languageDetector.processString(text)

        if let language = languageDetector.dominantLanguage {
            return language.rawValue
        }

        return configuration.preferredLanguage
    }

    // MARK: - Response Generation
    private func generateResponse(for input: String) async -> String {
        // Detect emotion if enabled
        var emotion: Emotion?
        if configuration.enableEmotionDetection {
            emotion = await emotionDetector.detect(from: input)
        }

        // Generate contextual response
        let context = contextManager.getCurrentContext()
        let response = await contextManager.generateResponse(
            input: input,
            context: context,
            emotion: emotion
        )

        return response
    }

    // MARK: - Command Handling
    private func handleCommandResult(_ result: CommandResult) {
        switch result.action {
        case .capturePhoto:
            NotificationCenter.default.post(name: .voiceCommandCapturePhoto, object: nil)
        case .startRecording:
            NotificationCenter.default.post(name: .voiceCommandStartRecording, object: nil)
        case .setReminder(let reminder):
            NotificationCenter.default.post(name: .voiceCommandSetReminder, object: reminder)
        case .navigate(let destination):
            NotificationCenter.default.post(name: .voiceCommandNavigate, object: destination)
        case .search(let query):
            NotificationCenter.default.post(name: .voiceCommandSearch, object: query)
        case .custom(let data):
            NotificationCenter.default.post(name: .voiceCommandCustom, object: data)
        case .none:
            break
        }

        // Speak response if available
        if let response = result.response {
            speak(response)
        }
    }

    private func handleEmergencyCommand() {
        // Emergency handling
        speak("Emergency detected. Calling for help.")
        NotificationCenter.default.post(name: .emergencyActivated, object: nil)
    }

    private func createReminder(from text: String) {
        // Extract reminder details
        let reminder = extractReminder(from: text)
        NotificationCenter.default.post(name: .createReminder, object: reminder)
    }

    private func createNote(from text: String) {
        // Extract and save note
        let note = extractNote(from: text)
        NotificationCenter.default.post(name: .createNote, object: note)
    }

    private func extractReminder(from text: String) -> [String: Any] {
        // Simple reminder extraction - could be enhanced with NLP
        return [
            "text": text,
            "timestamp": Date()
        ]
    }

    private func extractNote(from text: String) -> [String: Any] {
        // Simple note extraction
        return [
            "text": text,
            "timestamp": Date()
        ]
    }

    // MARK: - Active Listening
    private func startActiveListening() {
        startAudioCapture(for: .conversation)

        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest!
        ) { [weak self] result, error in
            if let result = result {
                self?.interimTranscript = result.bestTranscription.formattedString

                // Auto-process when speech ends
                if self?.detectEndOfSpeech(result: result) == true {
                    self?.transcript = result.bestTranscription.formattedString
                    Task {
                        await self?.handleActiveListeningResult()
                    }
                }
            }
        }
    }

    private func handleActiveListeningResult() async {
        let command = await processCommand(transcript)
        handleCommandResult(command)

        // Continue listening if in conversation mode
        if listeningMode == .conversation {
            startActiveListening()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceAssistantService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        processingState = .speaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        processingState = .idle

        // Resume listening if in conversation mode
        if listeningMode == .conversation && !isListening {
            startListening(mode: .conversation)
        }
    }
}

// MARK: - Supporting Classes
class WakeWordDetector {
    private let wakeWords: [String]
    private var isDetecting = false
    private var detectionCallback: ((Bool) -> Void)?

    init(wakeWords: [String]) {
        self.wakeWords = wakeWords.map { $0.lowercased() }
    }

    func start(callback: @escaping (Bool) -> Void) {
        isDetecting = true
        detectionCallback = callback
    }

    func stop() {
        isDetecting = false
        detectionCallback = nil
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard isDetecting else { return }

        // Convert buffer to text using on-device recognition
        // This is a simplified version - real implementation would use
        // acoustic models or neural networks for wake word detection

        // For now, trigger callback for testing
        // detectionCallback?(false)
    }
}

class AudioBuffer {
    private var buffers: [AVAudioPCMBuffer] = []
    private let maxBuffers = 100

    func append(_ buffer: AVAudioPCMBuffer) {
        buffers.append(buffer)

        if buffers.count > maxBuffers {
            buffers.removeFirst()
        }
    }

    func clear() {
        buffers.removeAll()
    }

    func getRecent(count: Int) -> [AVAudioPCMBuffer] {
        return Array(buffers.suffix(count))
    }
}

class AudioProcessor {
    private var sampleRate: Double = 48000
    private var bufferSize: Int = 1024

    func configure(sampleRate: Double, bufferSize: Int) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
    }

    func detectVoiceActivity(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }

        let frameLength = Int(buffer.frameLength)
        var energy: Float = 0

        vDSP_sve(channelData, 1, &energy, vDSP_Length(frameLength))

        // Simple VAD based on energy threshold
        return energy > 0.01
    }
}

class NoiseReducer {
    var noiseThreshold: Float = 0.1
    var reductionFactor: Float = 0.8

    func process(_ buffer: AVAudioPCMBuffer) {
        // Spectral subtraction for noise reduction
        // This is a simplified implementation
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channelData[channel]

            for i in 0..<frameLength {
                if abs(data[i]) < noiseThreshold {
                    data[i] *= reductionFactor
                }
            }
        }
    }
}

class VoiceEnhancer {
    enum EnhancementLevel {
        case low, medium, high
    }

    var enhancementLevel: EnhancementLevel = .medium
    var clarityBoost: Bool = true

    func process(_ buffer: AVAudioPCMBuffer) {
        // Apply voice enhancement filters
        // This would typically involve:
        // - Formant enhancement
        // - Pitch correction
        // - Dynamic range compression
        // Simplified implementation for demonstration
    }
}

class CommandRecognizer {
    func recognize(command: String, intent: Intent, context: Context) async -> CommandResult {
        // Pattern matching for commands
        let lowercased = command.lowercased()

        if lowercased.contains("take") && lowercased.contains("photo") {
            return CommandResult(
                action: .capturePhoto,
                response: "Taking photo now",
                confidence: 0.95
            )
        } else if lowercased.contains("record") && lowercased.contains("video") {
            return CommandResult(
                action: .startRecording,
                response: "Starting video recording",
                confidence: 0.9
            )
        } else if lowercased.contains("remind") {
            return CommandResult(
                action: .setReminder(["text": command]),
                response: "Reminder set",
                confidence: 0.85
            )
        } else if lowercased.contains("navigate") || lowercased.contains("directions") {
            let destination = extractDestination(from: command)
            return CommandResult(
                action: .navigate(destination),
                response: "Navigating to \(destination)",
                confidence: 0.88
            )
        } else if lowercased.contains("search") || lowercased.contains("find") {
            let query = extractQuery(from: command)
            return CommandResult(
                action: .search(query),
                response: "Searching for \(query)",
                confidence: 0.82
            )
        }

        return CommandResult(
            action: .none,
            response: "I didn't understand that command",
            confidence: 0.3
        )
    }

    private func extractDestination(from command: String) -> String {
        // Extract destination from command
        let words = command.components(separatedBy: " ")
        if let toIndex = words.firstIndex(of: "to") {
            return words[(toIndex + 1)...].joined(separator: " ")
        }
        return "unknown destination"
    }

    private func extractQuery(from command: String) -> String {
        // Extract search query from command
        let words = command.components(separatedBy: " ")
        if let forIndex = words.firstIndex(of: "for") {
            return words[(forIndex + 1)...].joined(separator: " ")
        }
        return command
    }
}

class ContextManager {
    private var currentContext = Context()

    func getCurrentContext() -> Context {
        return currentContext
    }

    func updateContext(_ update: ContextUpdate) {
        currentContext.apply(update)
    }

    func getContextualStrings() -> [String]? {
        // Return relevant contextual strings for speech recognition
        return currentContext.relevantTerms
    }

    func generateResponse(input: String, context: Context, emotion: Emotion?) async -> String {
        // Generate contextual response based on input, context, and emotion
        var response = "I understand you said: \(input)"

        if let emotion = emotion {
            switch emotion {
            case .happy:
                response = "Great to hear that! \(response)"
            case .sad:
                response = "I'm here to help. \(response)"
            case .angry:
                response = "Let me assist you with that. \(response)"
            case .neutral:
                break
            }
        }

        return response
    }
}

class IntentClassifier {
    func classify(_ text: String, language: String) async -> Intent {
        // Use NLP to classify intent
        // Simplified version - real implementation would use ML models

        let lowercased = text.lowercased()

        if lowercased.contains("photo") || lowercased.contains("picture") {
            return .capture
        } else if lowercased.contains("record") || lowercased.contains("video") {
            return .record
        } else if lowercased.contains("remind") || lowercased.contains("reminder") {
            return .reminder
        } else if lowercased.contains("navigate") || lowercased.contains("directions") {
            return .navigation
        } else if lowercased.contains("search") || lowercased.contains("find") {
            return .search
        } else if lowercased.contains("call") || lowercased.contains("phone") {
            return .call
        } else if lowercased.contains("message") || lowercased.contains("text") {
            return .message
        }

        return .unknown
    }
}

class EmotionDetector {
    func detect(from text: String) async -> Emotion {
        // Detect emotion from text using sentiment analysis
        // Simplified implementation

        let sentiment = NLLanguageRecognizer()
        sentiment.processString(text)

        // This is a placeholder - real implementation would use
        // sentiment scores and emotion classification models

        return .neutral
    }
}

// MARK: - Supporting Types
struct CommandResult {
    enum Action {
        case capturePhoto
        case startRecording
        case setReminder([String: Any])
        case navigate(String)
        case search(String)
        case custom([String: Any])
        case none
    }

    let action: Action
    let response: String?
    let confidence: Float
}

struct Context {
    var location: String?
    var time: Date
    var previousCommands: [String]
    var relevantTerms: [String]?
    var userPreferences: [String: Any]

    init() {
        self.time = Date()
        self.previousCommands = []
        self.userPreferences = [:]
    }

    mutating func apply(_ update: ContextUpdate) {
        switch update {
        case .location(let loc):
            self.location = loc
        case .addCommand(let cmd):
            self.previousCommands.append(cmd)
            if previousCommands.count > 10 {
                previousCommands.removeFirst()
            }
        case .terms(let terms):
            self.relevantTerms = terms
        case .preference(let key, let value):
            self.userPreferences[key] = value
        }
    }
}

enum ContextUpdate {
    case location(String)
    case addCommand(String)
    case terms([String])
    case preference(String, Any)
}

enum Intent {
    case capture
    case record
    case reminder
    case navigation
    case search
    case call
    case message
    case unknown
}

enum Emotion {
    case happy
    case sad
    case angry
    case neutral
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let voiceCommandCapturePhoto = Notification.Name("voiceCommandCapturePhoto")
    static let voiceCommandStartRecording = Notification.Name("voiceCommandStartRecording")
    static let voiceCommandSetReminder = Notification.Name("voiceCommandSetReminder")
    static let voiceCommandNavigate = Notification.Name("voiceCommandNavigate")
    static let voiceCommandSearch = Notification.Name("voiceCommandSearch")
    static let voiceCommandCustom = Notification.Name("voiceCommandCustom")
    static let emergencyActivated = Notification.Name("emergencyActivated")
    static let createReminder = Notification.Name("createReminder")
    static let createNote = Notification.Name("createNote")
}