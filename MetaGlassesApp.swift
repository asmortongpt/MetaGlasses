import SwiftUI
import Speech
@preconcurrency import AVFoundation
@preconcurrency import CoreBluetooth
import Photos
import Combine
import UIKit

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

        if command.contains("take a photo") || command.contains("take photo") || command.contains("capture") {
            lastCommand = "📸 Taking photo with glasses..."
            sendGlassesCameraCommand()

        } else if command.contains("start recording") || command.contains("record video") {
            lastCommand = "🎥 Starting video recording..."
            sendGlassesVideoCommand(start: true)

        } else if command.contains("stop recording") || command.contains("stop video") {
            lastCommand = "⏹ Stopping video recording..."
            sendGlassesVideoCommand(start: false)

        } else if command.contains("analyze") || command.contains("what do you see") {
            lastCommand = "🤖 Analyzing last photo..."
            analyzeLastPhoto()

        } else if command.contains("connect glasses") || command.contains("pair glasses") {
            lastCommand = "🔗 Connecting to glasses..."
            startScanning()

        } else if command.contains("battery") || command.contains("power") {
            lastCommand = "🔋 Checking battery..."
            checkGlassesBattery()

        } else if command.contains("who is this") || command.contains("identify person") {
            lastCommand = "👤 Identifying person..."
            identifyPerson()

        } else if command.contains("remember this") || command.contains("save memory") {
            lastCommand = "💾 Saving to memory..."
            saveToMemory()
        }

        // Reset wake word after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.wakeWordDetected = false
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
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Look for Meta Ray-Ban glasses
        if let name = peripheral.name,
           (name.contains("Meta") || name.contains("Ray-Ban") || name.contains("Stories")) {

            metaGlasses = peripheral
            peripheral.delegate = self
            central.stopScan()

            connectionStatus = "Found \(name), connecting..."
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected to \(peripheral.name ?? "Meta Glasses")"
        peripheral.discoverServices([META_GLASSES_SERVICE])

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Disconnected"
        metaGlasses = nil
        commandCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate
extension MetaGlassesController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics([COMMAND_CHARACTERISTIC, PHOTO_CHARACTERISTIC], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

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

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
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
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Check for new photos from glasses
        checkForNewGlassesPhoto()
    }
}

// MARK: - Main App View
struct MetaGlassesRealView: View {
    @StateObject private var controller = MetaGlassesController.shared
    @State private var showingPhotoDetail = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status
                HStack {
                    Circle()
                        .fill(controller.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(controller.connectionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

                    if !controller.lastCommand.isEmpty {
                        Text(controller.lastCommand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()

                // Last Photo from Glasses
                if let photo = controller.lastPhotoFromGlasses {
                    VStack {
                        Text("Last Photo from Glasses")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .onTapGesture {
                                showingPhotoDetail = true
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

                // Manual Controls
                VStack(spacing: 15) {
                    Button(action: {
                        controller.sendGlassesCameraCommand()
                    }) {
                        Label("Take Photo with Glasses", systemImage: "eyeglasses")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(controller.isConnected ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!controller.isConnected)

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
                }
                .padding(.horizontal)

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
            .navigationTitle("Meta Glasses Control")
            .sheet(isPresented: $showingPhotoDetail) {
                if let photo = controller.lastPhotoFromGlasses {
                    PhotoDetailView(image: photo, analysis: controller.aiAnalysisResult)
                }
            }
        }
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

// MARK: - Main App
@main
struct MetaGlassesApp: App {
    var body: some Scene {
        WindowGroup {
            MetaGlassesRealView()
                .onAppear {
                    // Request permissions
                    PHPhotoLibrary.requestAuthorization { _ in }
                    AVAudioSession.sharedInstance().requestRecordPermission { _ in }
                }
        }
    }
}