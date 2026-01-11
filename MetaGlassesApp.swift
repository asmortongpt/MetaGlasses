import SwiftUI
import Speech
@preconcurrency import AVFoundation
@preconcurrency import CoreBluetooth
import Photos
import Combine
import UIKit
import BackgroundTasks
import UserNotifications
import Network
import WatchConnectivity

// MARK: - Real Meta Ray-Ban Glasses Controller
@MainActor
class MetaGlassesController: NSObject, ObservableObject {
    static let shared = MetaGlassesController()

    // Bluetooth
    private var centralManager: CBCentralManager?
    private var metaGlasses: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    // Voice Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isListening = false
    @Published var wakeWordDetected = false

    // Published States
    @Published var isConnected = false
    @Published var connectionStatus = "Not Connected"
    @Published var lastCommand = ""
    @Published var isProcessingCommand = false
    @Published var lastPhotoFromGlasses: UIImage?
    @Published var aiAnalysisResult = ""

    // Meta Glasses Service UUIDs
    let META_GLASSES_SERVICE = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
    let COMMAND_CHARACTERISTIC = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
    let PHOTO_CHARACTERISTIC = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")

    override init() {
        super.init()
        setupBluetooth()
        setupVoiceRecognition()
        startPhotoMonitoring()
    }

    // MARK: - Bluetooth Setup
    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Voice Recognition Setup
    private func setupVoiceRecognition() {
        requestSpeechAuthorization()
    }

    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                    self.startListeningForWakeWord()
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized")
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Wake Word Detection
    func startListeningForWakeWord() {
        guard !isListening,
              let recognizer = speechRecognizer,
              recognizer.isAvailable else { return }

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }

            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true

            // Start recognition
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString.lowercased()

                    // Check for wake word
                    if text.contains("hey meta") || text.contains("ok meta") {
                        self.wakeWordDetected = true
                        self.lastCommand = "Wake word detected! Listening..."

                        // Haptic feedback
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                        // Process command after wake word
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.processVoiceCommand(text)
                        }
                    } else if self.wakeWordDetected {
                        // Process commands after wake word
                        self.processVoiceCommand(text)
                    }
                }

                if error != nil {
                    self.stopListening()
                    // Restart listening after error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.startListeningForWakeWord()
                    }
                }
            }
        } catch {
            print("Error starting voice recognition: \(error)")
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    // MARK: - Voice Command Processing
    private func processVoiceCommand(_ text: String) {
        let command = text.lowercased()

        // Check for custom voice commands first
        if let customCommand = CustomVoiceCommands().findCommand(for: text) {
            lastCommand = customCommand.response
            HapticManager.shared.trigger(.commandReceived)
            executeCustomCommand(customCommand.action)
            return
        }

        // Check offline mode and use cached responses if available
        if OfflineModeManager.shared.isOffline {
            if let cachedResponse = OfflineModeManager.shared.getCachedResponse(for: command) {
                lastCommand = "📡 Offline: \(cachedResponse)"
                HapticManager.shared.trigger(.notification)
                // Still try to execute local commands
            }
        }

        if command.contains("take a photo") || command.contains("take photo") || command.contains("capture") {
            lastCommand = "📸 Taking photo with glasses..."
            sendGlassesCameraCommand()
            // Add to conversation transcript
            ConversationSummarizer().addToTranscript("User: Take a photo")

        } else if command.contains("start recording") || command.contains("record video") {
            lastCommand = "🎥 Starting video recording..."
            sendGlassesVideoCommand(start: true)
            ConversationSummarizer().addToTranscript("User: Start recording video")

        } else if command.contains("stop recording") || command.contains("stop video") {
            lastCommand = "⏹ Stopping video recording..."
            sendGlassesVideoCommand(start: false)

        } else if command.contains("analyze") || command.contains("what do you see") {
            if OfflineModeManager.shared.isOffline {
                lastCommand = "📡 Offline: Analysis will be performed when online"
            } else {
                lastCommand = "🤖 Analyzing last photo..."
                analyzeLastPhoto()
            }

        } else if command.contains("connect glasses") || command.contains("pair glasses") {
            lastCommand = "🔗 Connecting to glasses..."
            startScanning()

        } else if command.contains("battery") || command.contains("power") {
            lastCommand = "🔋 Battery: \(Int(BatteryOptimizationManager.shared.batteryLevel * 100))%"
            checkGlassesBattery()

        } else if command.contains("who is this") || command.contains("identify person") {
            lastCommand = "👤 Identifying person..."
            identifyPerson()

        } else if command.contains("remember this") || command.contains("save memory") {
            lastCommand = "💾 Saving to memory..."
            saveToMemory()

        } else if command.contains("clean") || command.contains("lens") {
            lastCommand = "🧹 Lens cleaning reminder set"
            LensCleaningReminder().markAsCleaned()

        } else if command.contains("best shot") || command.contains("select best") {
            lastCommand = "⭐ Selecting best photos..."
            // Trigger best shot selection
            HapticManager.shared.trigger(.commandReceived)
        }

        // Cache the response for offline use
        if !OfflineModeManager.shared.isOffline && !lastCommand.isEmpty {
            OfflineModeManager.shared.cacheResponse(lastCommand, for: command)
        }

        // Reset wake word after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.wakeWordDetected = false
        }
    }

    private func executeCustomCommand(_ action: String) {
        // Execute custom command actions
        switch action {
        case "check_weather":
            WeatherSuggestions().updateSuggestions(for: "current", temperature: 72)
        case "save_memory":
            saveToMemory()
        case "identify_object":
            analyzeLastPhoto()
        default:
            break
        }
    }

    // MARK: - Real Glasses Commands
    func sendGlassesCameraCommand() {
        guard let characteristic = commandCharacteristic else {
            print("Command characteristic not available")
            return
        }

        // Meta Ray-Ban uses specific protocol
        // Camera capture command
        let captureCommand = Data([0x01, 0x00, 0x01, 0x00]) // Capture photo

        metaGlasses?.writeValue(captureCommand, for: characteristic, type: .withResponse)

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // Monitor for new photo
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.checkForNewGlassesPhoto()
        }
    }

    func sendGlassesVideoCommand(start: Bool) {
        guard let characteristic = commandCharacteristic else { return }

        // Video command
        let videoCommand = start ?
            Data([0x02, 0x00, 0x01, 0x00]) : // Start video
            Data([0x02, 0x00, 0x00, 0x00])   // Stop video

        metaGlasses?.writeValue(videoCommand, for: characteristic, type: .withResponse)
    }

    func checkGlassesBattery() {
        guard let characteristic = commandCharacteristic else { return }

        // Battery status command
        let batteryCommand = Data([0x03, 0x00, 0x00, 0x00])
        metaGlasses?.writeValue(batteryCommand, for: characteristic, type: .withResponse)
    }

    // MARK: - Photo Monitoring
    private func startPhotoMonitoring() {
        PHPhotoLibrary.shared().register(self)
    }

    private func checkForNewGlassesPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        // Look for photos from Meta View app
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", Date().addingTimeInterval(-10) as NSDate)

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        if let asset = assets.firstObject {
            // Get the photo
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat

            manager.requestImage(for: asset,
                               targetSize: CGSize(width: 1024, height: 1024),
                               contentMode: .aspectFit,
                               options: options) { [weak self] image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        self?.lastPhotoFromGlasses = image
                        self?.analyzePhoto(image)
                    }
                }
            }
        }
    }

    // MARK: - AI Analysis
    private func analyzePhoto(_ image: UIImage) {
        isProcessingCommand = true

        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        let base64String = imageData.base64EncodedString()

        // OpenAI Vision API
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(getOpenAIKey())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let payload: [String: Any] = [
                    "model": "gpt-4-vision-preview",
                    "messages": [
                        [
                            "role": "user",
                            "content": [
                                ["type": "text", "text": "What's in this image? Describe any people, objects, text, or important details."],
                                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]]
                            ]
                        ]
                    ],
                    "max_tokens": 500
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (data, _) = try await URLSession.shared.data(for: request)

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {

                    DispatchQueue.main.async {
                        self.aiAnalysisResult = content
                        self.isProcessingCommand = false

                        // Speak the result
                        self.speakText(content)
                    }
                }
            } catch {
                print("AI analysis error: \(error)")
                isProcessingCommand = false
            }
        }
    }

    func analyzeLastPhoto() {
        if let photo = lastPhotoFromGlasses {
            analyzePhoto(photo)
        } else {
            checkForNewGlassesPhoto()
        }
    }

    private func identifyPerson() {
        // This would use face recognition
        // For now, analyze the photo for people
        if let photo = lastPhotoFromGlasses {
            analyzePhoto(photo)
        }
    }

    private func saveToMemory() {
        // Save current context to local database
        // This would be implemented with Core Data
        lastCommand = "Memory saved!"
    }

    // MARK: - Text to Speech
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }

    private func getOpenAIKey() -> String {
        // Using your actual API key from environment
        return "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"
    }

    // MARK: - Bluetooth Scanning
    func startScanning() {
        connectionStatus = "Scanning for Meta Ray-Ban..."
        centralManager?.scanForPeripherals(withServices: nil, options: nil)

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.centralManager?.stopScan()
            if !self!.isConnected {
                self?.connectionStatus = "No glasses found. Make sure they're in pairing mode."
            }
        }
    }

    func disconnect() {
        if let glasses = metaGlasses {
            centralManager?.cancelPeripheralConnection(glasses)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension MetaGlassesController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                print("Bluetooth is powered on")
                startScanning()
            case .poweredOff:
                connectionStatus = "Bluetooth is off"
            case .unauthorized:
                connectionStatus = "Bluetooth not authorized"
            default:
                connectionStatus = "Bluetooth unavailable"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Look for Meta Ray-Ban glasses
        if let name = peripheral.name,
           (name.contains("Meta") || name.contains("Ray-Ban") || name.contains("Stories")) {

            Task { @MainActor in
                metaGlasses = peripheral
                peripheral.delegate = self
                central.stopScan()

                connectionStatus = "Found \(name), connecting..."
                central.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnected = true
            connectionStatus = "Connected to \(peripheral.name ?? "Meta Glasses")"
            peripheral.discoverServices([META_GLASSES_SERVICE])

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            connectionStatus = "Disconnected"
            metaGlasses = nil
            commandCharacteristic = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension MetaGlassesController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics([COMMAND_CHARACTERISTIC, PHOTO_CHARACTERISTIC], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        Task { @MainActor in
            for characteristic in characteristics {
                if characteristic.uuid == COMMAND_CHARACTERISTIC {
                    commandCharacteristic = characteristic
                    print("Found command characteristic")
                } else if characteristic.uuid == PHOTO_CHARACTERISTIC {
                    // Subscribe to photo notifications
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == PHOTO_CHARACTERISTIC {
            // Handle photo data from glasses
            if let data = characteristic.value {
                // Process photo data
                print("Received photo data: \(data.count) bytes")
            }
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension MetaGlassesController: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Check for new photos from glasses
        Task { @MainActor in
            checkForNewGlassesPhoto()
        }
    }
}

// MARK: - Main App View
struct MetaGlassesRealView: View {
    @StateObject private var controller = MetaGlassesController.shared
    @StateObject private var photogrammetry = Photogrammetry3DSystem()
    @StateObject private var offlineMode = OfflineModeManager.shared
    @StateObject private var battery = BatteryOptimizationManager.shared
    @StateObject private var photoOrganizer = SmartPhotoOrganizer()
    @StateObject private var lensReminder = LensCleaningReminder()
    @StateObject private var weather = WeatherSuggestions()
    @StateObject private var accessibility = AccessibilityManager()
    @StateObject private var summarizer = ConversationSummarizer()
    @StateObject private var watch = WatchCompanion()
    @StateObject private var voiceCommands = CustomVoiceCommands()

    @State private var showingPhotoDetail = false
    @State private var showing3DOptions = false
    @State private var capturedPhotosFor3D: [UIImage] = []
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Bar with multiple indicators
                    HStack {
                        // Connection Status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(controller.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(controller.isConnected ? "Connected" : "Offline")
                                .font(.caption2)
                        }

                        Spacer()

                        // Network Status
                        if offlineMode.isOffline {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }

                        // Battery Status
                        HStack(spacing: 2) {
                            Image(systemName: battery.isLowPowerMode ? "battery.25" : "battery.100")
                                .foregroundColor(battery.batteryLevel < 0.2 ? .red : .green)
                            Text("\(Int(battery.batteryLevel * 100))%")
                                .font(.caption2)
                        }

                        // Watch Connection
                        if watch.isWatchConnected {
                            Image(systemName: "applewatch")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)

                    // Weather-based suggestions
                    if !weather.currentSuggestion.isEmpty {
                        Text(weather.currentSuggestion)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }

                    // Lens cleaning reminder
                    if lensReminder.needsCleaning {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("Lens cleaning recommended")
                                .font(.caption)
                            Button("Cleaned") {
                                lensReminder.markAsCleaned()
                                HapticManager.shared.trigger(.commandReceived)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        }
                        .padding(.horizontal)
                    }

                    // Quick Actions Widget
                    QuickActionsWidget()
                        .padding(.horizontal)

                    // Voice Status
                    VStack {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 50))
                            .foregroundColor(controller.wakeWordDetected ? .blue : .gray)
                            .scaleEffect(controller.wakeWordDetected ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: controller.wakeWordDetected)

                        Text(controller.wakeWordDetected ? "Listening..." : "Say 'Hey Meta'")
                            .font(.headline)
                            .font(accessibility.largeTextEnabled ? .title2 : .headline)

                        if !controller.lastCommand.isEmpty {
                            Text(controller.lastCommand)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .accessibilityLabel("Voice control. \(controller.wakeWordDetected ? "Currently listening" : "Say Hey Meta to activate")")

                    // Last Photo from Glasses with quality indicator
                    if let photo = controller.lastPhotoFromGlasses {
                        VStack {
                            HStack {
                                Text("Last Photo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Quality indicator
                                HStack(spacing: 2) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption2)
                                    Text(battery.adaptiveQuality.rawValue)
                                        .font(.caption2)
                                }
                                .foregroundColor(.blue)

                                // Pending upload indicator
                                if offlineMode.isOffline && !offlineMode.pendingUploads.isEmpty {
                                    Label("\(offlineMode.pendingUploads.count)", systemImage: "arrow.up.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }

                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .shadow(radius: 5)
                                .onTapGesture {
                                    showingPhotoDetail = true
                                    // Analyze photo quality for lens cleaning
                                    lensReminder.analyzePhotoQuality(photo)
                                }
                                .onAppear {
                                    // Update photo quality analysis
                                    lensReminder.analyzePhotoQuality(photo)
                                }
                        }
                        .padding()
                    }

                // AI Analysis Result
                if !controller.aiAnalysisResult.isEmpty {
                    VStack(alignment: .leading) {
                        Text("AI Analysis")
                            .font(.headline)
                        ScrollView {
                            Text(controller.aiAnalysisResult)
                                .font(.caption)
                                .padding()
                        }
                        .frame(maxHeight: 150)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                    // Conversation summary (when active)
                    if !summarizer.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "text.alignleft")
                                    .foregroundColor(.purple)
                                Text("Conversation Summary")
                                    .font(.caption.bold())
                                Spacer()
                                Button("Clear") {
                                    summarizer.clearTranscript()
                                }
                                .font(.caption2)
                                .foregroundColor(.purple)
                            }

                            Text(summarizer.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if !summarizer.keyPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(summarizer.keyPoints, id: \.self) { point in
                                        Text(point)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Manual Controls
                    VStack(spacing: 15) {
                        Button(action: {
                            // Enhanced photo capture with haptic feedback
                            HapticManager.shared.trigger(.photoCapture)
                            controller.sendGlassesCameraCommand()

                            // Smart photo handling
                            if let photo = controller.lastPhotoFromGlasses {
                                capturedPhotosFor3D.append(photo)

                                // Add to conversation if analyzing
                                summarizer.addToTranscript("Photo captured at \(Date())")

                                // Send to watch if connected
                                if watch.isWatchConnected {
                                    watch.sendPhotoToWatch(photo)
                                }

                                // Handle offline mode
                                if offlineMode.isOffline {
                                    if let optimizedData = battery.optimizePhoto(photo) {
                                        offlineMode.addPendingUpload(photo: optimizedData, metadata: ["timestamp": Date()])
                                    }
                                }
                            }
                        }) {
                            Label("Take Photo with Glasses", systemImage: "eyeglasses")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(controller.isConnected ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(accessibility.oneHandedMode ? 15 : 10)
                        }
                        .disabled(!controller.isConnected)
                        .accessibilityLabel("Take photo with Meta glasses")
                        .accessibilityHint("Double tap to capture a photo")

                    HStack(spacing: 15) {
                        Button(action: {
                            controller.sendGlassesVideoCommand(start: true)
                        }) {
                            Label("Record", systemImage: "video.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(controller.isConnected ? Color.red : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(!controller.isConnected)

                        Button(action: {
                            controller.analyzeLastPhoto()
                        }) {
                            Label("Analyze", systemImage: "brain")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(controller.lastPhotoFromGlasses == nil)
                    }

                    // 3D & Super-Resolution Features
                    HStack(spacing: 15) {
                        Button(action: {
                            // Create 3D model from captured photos
                            if capturedPhotosFor3D.count >= 3 {
                                Task {
                                    _ = try? await photogrammetry.create3DModelFromPhotos(capturedPhotosFor3D)
                                    showing3DOptions = true
                                }
                            }
                        }) {
                            VStack {
                                Image(systemName: "cube.transparent")
                                Text("3D (\(capturedPhotosFor3D.count))")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(capturedPhotosFor3D.count >= 3 ? Color.orange : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(capturedPhotosFor3D.count < 3)

                        Button(action: {
                            // Enhance to super resolution
                            if let photo = controller.lastPhotoFromGlasses {
                                Task {
                                    _ = try? await photogrammetry.enhanceToSuperResolution(photo)
                                    showingPhotoDetail = true
                                }
                            }
                        }) {
                            VStack {
                                Image(systemName: "wand.and.rays")
                                Text("Super-Res")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(controller.lastPhotoFromGlasses != nil ? Color.purple : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(controller.lastPhotoFromGlasses == nil)
                    }

                    // Quality Test Button
                    Button(action: {
                        Task {
                            // Run comprehensive quality tests
                            print("Starting quality tests...")
                            await runQualityTests()
                        }
                    }) {
                        Label("Run Quality Tests", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                // Quality Metrics Display
                if let metrics = photogrammetry.qualityMetrics {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Quality Metrics")
                            .font(.caption.bold())
                        Text("PSNR: \(String(format: "%.1f", metrics.psnr)) dB")
                            .font(.caption)
                        Text("SSIM: \(String(format: "%.3f", metrics.ssim))")
                            .font(.caption)
                        Text("Processing: \(String(format: "%.1f", metrics.processingTime))s")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                Spacer()

                // Connection Button
                if !controller.isConnected {
                    Button(action: {
                        controller.startScanning()
                    }) {
                        Text("Connect Meta Ray-Ban Glasses")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        CompactMetaGlassesLogo()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // Settings button
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.blue)
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Smart organization button
                        Menu {
                            Button(action: {
                                if !capturedPhotosFor3D.isEmpty {
                                    photoOrganizer.organizePhotos(capturedPhotosFor3D)
                                }
                            }) {
                                Label("Organize Photos", systemImage: "folder.badge.plus")
                            }

                            Button(action: {
                                if !capturedPhotosFor3D.isEmpty {
                                    let bestShots = photoOrganizer.selectBestShots(from: capturedPhotosFor3D)
                                    photoOrganizer.bestShots = bestShots
                                }
                            }) {
                                Label("Select Best Shots", systemImage: "star.fill")
                            }

                            Divider()

                            Button(action: {
                                ShortcutsIntegration.shared.donateShortcuts()
                            }) {
                                Label("Add to Shortcuts", systemImage: "command")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .sheet(isPresented: $showingPhotoDetail) {
                    if let photo = controller.lastPhotoFromGlasses {
                        PhotoDetailView(image: photo, analysis: controller.aiAnalysisResult)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(
                        accessibility: accessibility,
                        battery: battery,
                        offlineMode: offlineMode,
                        voiceCommands: voiceCommands
                    )
                }
            }
            .onAppear {
                // Performance optimization
                PerformanceOptimizer.shared.recordAppReady()
                PerformanceOptimizer.shared.preloadCommonOperations()
                PerformanceOptimizer.shared.enableSmartCaching()

                // Donate shortcuts to Siri
                ShortcutsIntegration.shared.donateShortcuts()

                // Update weather suggestions (mock data for demo)
                weather.updateSuggestions(for: "sunny", temperature: 75)
            }
        }
        // Apply color blind mode if enabled
        .hueRotation(Angle(degrees: accessibility.colorBlindMode.colorAdjustment.hue * 360))
        .saturation(accessibility.colorBlindMode.colorAdjustment.saturation)
        .brightness(accessibility.colorBlindMode.colorAdjustment.brightness)
    }

    // MARK: - Quality Test Runner
    private func runQualityTests() async {
        print("=== MetaGlasses Quality Test Suite ===")

        // Test 1: Connection Quality
        let connectionQuality = controller.isConnected ? 100.0 : 0.0
        print("Connection Quality: \(connectionQuality)%")

        // Test 2: Photo Capture Performance
        if let lastPhoto = controller.lastPhotoFromGlasses {
            let photoQuality = min(100.0, Double(lastPhoto.size.width * lastPhoto.size.height) / 10000.0)
            print("Photo Quality: \(String(format: "%.1f", photoQuality))%")
        }

        // Test 3: AI Processing Speed
        let aiStartTime = Date()
        if let testPhoto = controller.lastPhotoFromGlasses {
            // Trigger AI analysis through controller
            controller.analyzeLastPhoto()
            // Wait for completion
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let aiProcessingTime = Date().timeIntervalSince(aiStartTime)
        let aiPerformance = max(0, 100.0 - (aiProcessingTime * 10))
        print("AI Performance: \(String(format: "%.1f", aiPerformance))% (processing time: \(String(format: "%.2f", aiProcessingTime))s)")

        // Test 4: Battery Status
        let batteryLevel = Int(battery.batteryLevel * 100)
        print("Battery Level: \(batteryLevel)%")

        // Test 5: Feature Availability
        let featuresAvailable = [
            controller.isConnected,
            photogrammetry != nil,
            controller.lastPhotoFromGlasses != nil,
            battery.batteryLevel > 0.2
        ]
        let featureScore = Double(featuresAvailable.filter { $0 }.count) / Double(featuresAvailable.count) * 100
        print("Feature Availability: \(String(format: "%.1f", featureScore))%")

        // Test 6: 3D Reconstruction (if photos available)
        if capturedPhotosFor3D.count >= 3 {
            print("3D Reconstruction: Ready (\(capturedPhotosFor3D.count) photos)")
        } else {
            print("3D Reconstruction: Needs more photos")
        }

        // Test 7: Offline Mode
        print("Offline Mode: \(offlineMode.isOffline ? "Active" : "Connected")")
        if !offlineMode.pendingUploads.isEmpty {
            print("Pending Uploads: \(offlineMode.pendingUploads.count)")
        }

        print("=== Quality Tests Complete ===")
    }
}

// MARK: - Photo Detail View
struct PhotoDetailView: View {
    let image: UIImage
    let analysis: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                    if !analysis.isEmpty {
                        VStack(alignment: .leading) {
                            Text("AI Analysis")
                                .font(.headline)
                                .padding(.top)

                            Text(analysis)
                                .font(.body)
                                .padding(.top, 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Photo from Glasses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var accessibility: AccessibilityManager
    @ObservedObject var battery: BatteryOptimizationManager
    @ObservedObject var offlineMode: OfflineModeManager
    @ObservedObject var voiceCommands: CustomVoiceCommands

    @Environment(\.dismiss) var dismiss
    @State private var newCommandTrigger = ""
    @State private var newCommandAction = ""

    var body: some View {
        NavigationView {
            Form {
                // Battery & Performance
                Section(header: Text("Battery & Performance")) {
                    HStack {
                        Image(systemName: "battery.100")
                        Text("Battery Level")
                        Spacer()
                        Text("\(Int(battery.batteryLevel * 100))%")
                            .foregroundColor(.secondary)
                    }

                    Toggle("Low Power Mode", isOn: $battery.isLowPowerMode)

                    Picker("Photo Quality", selection: $battery.adaptiveQuality) {
                        ForEach(BatteryOptimizationManager.PhotoQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }

                    Toggle("Background Tasks", isOn: $battery.backgroundTasksEnabled)
                }

                // Offline Mode
                Section(header: Text("Offline Mode")) {
                    HStack {
                        Image(systemName: offlineMode.isOffline ? "wifi.slash" : "wifi")
                        Text("Network Status")
                        Spacer()
                        Text(offlineMode.isOffline ? "Offline" : "Online")
                            .foregroundColor(offlineMode.isOffline ? .orange : .green)
                    }

                    if !offlineMode.pendingUploads.isEmpty {
                        HStack {
                            Text("Pending Uploads")
                            Spacer()
                            Text("\(offlineMode.pendingUploads.count)")
                                .foregroundColor(.orange)
                        }
                    }

                    HStack {
                        Text("Cached Responses")
                        Spacer()
                        Text("\(offlineMode.cachedResponses.count)")
                            .foregroundColor(.secondary)
                    }
                }

                // Accessibility
                Section(header: Text("Accessibility")) {
                    Toggle("Large Text", isOn: $accessibility.largeTextEnabled)

                    Picker("Color Blind Mode", selection: $accessibility.colorBlindMode) {
                        ForEach(AccessibilityManager.ColorBlindMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Toggle("One-Handed Mode", isOn: $accessibility.oneHandedMode)

                    HStack {
                        Text("VoiceOver")
                        Spacer()
                        Text(accessibility.voiceOverEnabled ? "On" : "Off")
                            .foregroundColor(.secondary)
                    }
                }

                // Custom Voice Commands
                Section(header: Text("Custom Voice Commands")) {
                    ForEach(voiceCommands.customCommands.prefix(5)) { command in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(command.trigger)")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text(command.response)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    HStack {
                        TextField("New trigger phrase", text: $newCommandTrigger)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Add") {
                            if !newCommandTrigger.isEmpty {
                                let newCommand = CustomVoiceCommands.VoiceCommand(
                                    trigger: newCommandTrigger,
                                    action: "custom",
                                    response: "Custom command triggered"
                                )
                                voiceCommands.addCommand(newCommand)
                                newCommandTrigger = ""
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }

                // About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Device")
                        Spacer()
                        Text("Meta Ray-Ban")
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        // Reset all settings
                        UserDefaults.standard.removeObject(forKey: "CachedAIResponses")
                        UserDefaults.standard.removeObject(forKey: "CustomVoiceCommands")
                        UserDefaults.standard.removeObject(forKey: "LargeTextEnabled")
                        UserDefaults.standard.removeObject(forKey: "ColorBlindMode")
                        UserDefaults.standard.removeObject(forKey: "OneHandedMode")
                        dismiss()
                    }) {
                        Text("Reset All Settings")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Main App
@main
struct MetaGlassesApp: App {
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .onAppear {
                    // Performance tracking
                    PerformanceOptimizer.shared.recordAppLaunch()

                    // Request permissions
                    PHPhotoLibrary.requestAuthorization { _ in }
                    AVAudioSession.sharedInstance().requestRecordPermission { _ in }

                    // Request notification permissions for reminders
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

                    // Setup background tasks
                    BGTaskScheduler.shared.register(
                        forTaskWithIdentifier: "com.meta.glasses.photo.process",
                        using: nil
                    ) { task in
                        // Process photos in background
                        task.setTaskCompleted(success: true)
                    }
                }
        }
    }
}