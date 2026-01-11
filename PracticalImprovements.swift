import SwiftUI
import CoreData
import Network
import Combine
import AVFoundation
import Photos
import CoreLocation
import WatchConnectivity
import Intents
import UserNotifications
import BackgroundTasks

// MARK: - Offline Mode Manager
@MainActor
class OfflineModeManager: ObservableObject {
    static let shared = OfflineModeManager()

    @Published var isOffline = false
    @Published var cachedResponses: [String: String] = [:]
    @Published var pendingUploads: [PendingUpload] = []

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private let cacheLimit = 100 // Max cached AI responses

    struct PendingUpload {
        let id = UUID()
        let photo: Data
        let metadata: [String: Any]
        let timestamp: Date
    }

    init() {
        setupNetworkMonitoring()
        loadCachedResponses()
        preloadCommonResponses()
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied

                // Upload pending items when back online
                if wasOffline && path.status == .satisfied {
                    self?.uploadPendingItems()
                }
            }
        }
        monitor.start(queue: queue)
    }

    private func preloadCommonResponses() {
        // Cache common AI responses for offline use
        cachedResponses["what is this"] = "I need an internet connection to analyze images in detail."
        cachedResponses["take photo"] = "Photo captured and saved locally. Will analyze when online."
        cachedResponses["battery status"] = "Checking battery status..."
        cachedResponses["help"] = "Available offline commands: Take Photo, Save Note, View Recent Photos, Check Battery"
    }

    func getCachedResponse(for query: String) -> String? {
        // Try exact match first
        if let response = cachedResponses[query.lowercased()] {
            return response
        }

        // Try fuzzy matching
        for (key, value) in cachedResponses {
            if query.lowercased().contains(key) || key.contains(query.lowercased()) {
                return value
            }
        }

        return nil
    }

    func cacheResponse(_ response: String, for query: String) {
        cachedResponses[query.lowercased()] = response

        // Maintain cache size limit
        if cachedResponses.count > cacheLimit {
            // Remove oldest entries
            let sortedKeys = cachedResponses.keys.sorted()
            for key in sortedKeys.prefix(20) {
                cachedResponses.removeValue(forKey: key)
            }
        }

        saveCachedResponses()
    }

    func addPendingUpload(photo: Data, metadata: [String: Any]) {
        let upload = PendingUpload(photo: photo, metadata: metadata, timestamp: Date())
        pendingUploads.append(upload)

        // Limit pending uploads
        if pendingUploads.count > 50 {
            pendingUploads.removeFirst(10)
        }
    }

    private func uploadPendingItems() {
        guard !isOffline else { return }

        for upload in pendingUploads {
            // Upload logic here
            print("Uploading pending photo from \(upload.timestamp)")
        }

        pendingUploads.removeAll()
    }

    private func loadCachedResponses() {
        if let data = UserDefaults.standard.data(forKey: "CachedAIResponses"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            cachedResponses = decoded
        }
    }

    private func saveCachedResponses() {
        if let encoded = try? JSONEncoder().encode(cachedResponses) {
            UserDefaults.standard.set(encoded, forKey: "CachedAIResponses")
        }
    }
}

// MARK: - Battery Optimization Manager
@MainActor
class BatteryOptimizationManager: ObservableObject {
    static let shared = BatteryOptimizationManager()

    @Published var batteryLevel: Float = 1.0
    @Published var isLowPowerMode = false
    @Published var adaptiveQuality: PhotoQuality = .high
    @Published var backgroundTasksEnabled = true

    enum PhotoQuality: String, CaseIterable {
        case low = "Low (Battery Saver)"
        case medium = "Medium (Balanced)"
        case high = "High (Best Quality)"

        var compressionQuality: CGFloat {
            switch self {
            case .low: return 0.3
            case .medium: return 0.6
            case .high: return 0.9
            }
        }

        var targetSize: CGSize {
            switch self {
            case .low: return CGSize(width: 640, height: 480)
            case .medium: return CGSize(width: 1024, height: 768)
            case .high: return CGSize(width: 2048, height: 1536)
            }
        }
    }

    init() {
        monitorBattery()
        setupLowPowerNotifications()
    }

    private func monitorBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.updateBatteryStatus()
        }

        updateBatteryStatus()
    }

    private func updateBatteryStatus() {
        batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState

        // Auto-adjust quality based on battery
        if batteryLevel < 0.2 {
            adaptiveQuality = .low
            backgroundTasksEnabled = false
            isLowPowerMode = true
        } else if batteryLevel < 0.5 {
            adaptiveQuality = .medium
            backgroundTasksEnabled = true
            isLowPowerMode = false
        } else {
            adaptiveQuality = .high
            backgroundTasksEnabled = true
            isLowPowerMode = false
        }

        // If charging, use best quality
        if batteryState == .charging || batteryState == .full {
            adaptiveQuality = .high
            backgroundTasksEnabled = true
        }
    }

    private func setupLowPowerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    @objc private func powerStateChanged() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if isLowPowerMode {
            adaptiveQuality = .low
        }
    }

    func optimizePhoto(_ image: UIImage) -> Data? {
        let targetSize = adaptiveQuality.targetSize
        let quality = adaptiveQuality.compressionQuality

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.jpegData(compressionQuality: quality)
    }
}

// MARK: - Haptic Feedback Manager
class HapticManager: ObservableObject {
    static let shared = HapticManager()

    enum HapticType {
        case photoCapture
        case connectionSuccess
        case connectionLost
        case commandReceived
        case error
        case lowBattery
        case notification
    }

    func trigger(_ type: HapticType) {
        switch type {
        case .photoCapture:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()

        case .connectionSuccess:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        case .connectionLost:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)

        case .commandReceived:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

        case .lowBattery:
            // Custom pattern for low battery
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                generator.impactOccurred()
            }

        case .notification:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    func customPattern(_ pattern: [TimeInterval]) {
        for (index, interval) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + pattern[0..<index].reduce(0, +)) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}

// MARK: - Smart Photo Organizer
class SmartPhotoOrganizer: ObservableObject {
    @Published var organizedPhotos: [PhotoCollection] = []
    @Published var bestShots: [UIImage] = []

    struct PhotoCollection {
        let id = UUID()
        let title: String
        let photos: [UIImage]
        let location: String?
        let date: Date
        let eventType: EventType
    }

    enum EventType: String, CaseIterable {
        case work = "Work"
        case travel = "Travel"
        case social = "Social"
        case family = "Family"
        case outdoor = "Outdoor"
        case food = "Food"
        case other = "Other"
    }

    func organizePhotos(_ photos: [UIImage]) {
        // Group by time proximity (photos taken within 30 minutes)
        var collections: [PhotoCollection] = []
        var currentGroup: [UIImage] = []
        var groupStartTime = Date()

        for photo in photos {
            // In real implementation, get actual photo metadata
            currentGroup.append(photo)

            if currentGroup.count >= 5 {
                let collection = PhotoCollection(
                    title: generateTitle(for: currentGroup),
                    photos: currentGroup,
                    location: "Current Location",
                    date: groupStartTime,
                    eventType: detectEventType(from: currentGroup)
                )
                collections.append(collection)
                currentGroup = []
                groupStartTime = Date()
            }
        }

        organizedPhotos = collections
    }

    func selectBestShots(from photos: [UIImage]) -> [UIImage] {
        // Simple quality scoring based on:
        // - Sharpness (using Laplacian variance)
        // - Exposure (histogram analysis)
        // - Composition (rule of thirds)

        return photos.sorted { photo1, photo2 in
            calculateQualityScore(photo1) > calculateQualityScore(photo2)
        }.prefix(5).map { $0 }
    }

    private func calculateQualityScore(_ image: UIImage) -> Double {
        // Simplified quality scoring
        var score = 0.0

        // Check image size
        if let cgImage = image.cgImage {
            score += Double(cgImage.width * cgImage.height) / 1000000.0
        }

        // Add randomness for demo (in real app, implement actual quality metrics)
        score += Double.random(in: 0...10)

        return score
    }

    private func generateTitle(for photos: [UIImage]) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .medium
        timeFormatter.timeStyle = .short

        return "\(photos.count) photos - \(timeFormatter.string(from: Date()))"
    }

    private func detectEventType(from photos: [UIImage]) -> EventType {
        // In real implementation, use AI to detect event type
        return EventType.allCases.randomElement() ?? .other
    }
}

// MARK: - Lens Cleaning Reminder
class LensCleaningReminder: ObservableObject {
    @Published var needsCleaning = false
    @Published var lastCleanedDate: Date?
    @Published var photoQualityScore: Double = 100.0

    private var blurryPhotoCount = 0
    private let blurryThreshold = 3

    func analyzePhotoQuality(_ image: UIImage) {
        // Simple blur detection
        let quality = detectBlur(in: image)
        photoQualityScore = quality

        if quality < 70 {
            blurryPhotoCount += 1

            if blurryPhotoCount >= blurryThreshold {
                needsCleaning = true
                sendCleaningReminder()
            }
        } else {
            blurryPhotoCount = max(0, blurryPhotoCount - 1)
        }
    }

    private func detectBlur(in image: UIImage) -> Double {
        // Simplified blur detection
        // In real app, use Laplacian variance or other blur detection algorithms
        return Double.random(in: 60...100)
    }

    private func sendCleaningReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Clean Your Glasses"
        content.body = "Your recent photos appear blurry. Try cleaning your Meta glasses lenses."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lens-cleaning",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        HapticManager.shared.trigger(.notification)
    }

    func markAsCleaned() {
        needsCleaning = false
        blurryPhotoCount = 0
        lastCleanedDate = Date()
        photoQualityScore = 100.0
    }
}

// MARK: - Weather-Based Suggestions
class WeatherSuggestions: ObservableObject {
    @Published var currentSuggestion: String = ""
    @Published var glassesMode: GlassesMode = .auto

    enum GlassesMode: String, CaseIterable {
        case auto = "Auto"
        case sunny = "Sunny"
        case cloudy = "Cloudy"
        case indoor = "Indoor"
        case night = "Night"

        var cameraSettings: CameraSettings {
            switch self {
            case .sunny:
                return CameraSettings(iso: 100, exposureCompensation: -0.5)
            case .cloudy:
                return CameraSettings(iso: 200, exposureCompensation: 0.0)
            case .indoor:
                return CameraSettings(iso: 400, exposureCompensation: 0.5)
            case .night:
                return CameraSettings(iso: 800, exposureCompensation: 1.0)
            case .auto:
                return CameraSettings(iso: 200, exposureCompensation: 0.0)
            }
        }
    }

    struct CameraSettings {
        let iso: Int
        let exposureCompensation: Float
    }

    func updateSuggestions(for weather: String, temperature: Double) {
        switch weather.lowercased() {
        case "sunny", "clear":
            currentSuggestion = "☀️ Bright conditions detected. Transition lenses activated."
            glassesMode = .sunny

        case "cloudy", "overcast":
            currentSuggestion = "☁️ Soft lighting ideal for portraits."
            glassesMode = .cloudy

        case "rain", "drizzle":
            currentSuggestion = "🌧️ Keep glasses dry. Water droplets may affect photos."

        case "snow":
            currentSuggestion = "❄️ Beautiful lighting! Watch for lens fogging."

        default:
            currentSuggestion = "📸 Ready to capture memories!"
            glassesMode = .auto
        }

        // Temperature-based suggestions
        if temperature < 32 {
            currentSuggestion += "\n🥶 Cold weather: Glasses may fog when entering warm spaces."
        } else if temperature > 90 {
            currentSuggestion += "\n🥵 Hot weather: Take breaks to prevent overheating."
        }
    }
}

// MARK: - Quick Actions Widget
struct QuickActionsWidget: View {
    @StateObject private var haptics = HapticManager.shared
    @State private var expandedActions = false

    let quickActions = [
        QuickAction(icon: "camera.fill", title: "Photo", action: .capturePhoto),
        QuickAction(icon: "video.fill", title: "Video", action: .recordVideo),
        QuickAction(icon: "mic.fill", title: "Note", action: .voiceNote),
        QuickAction(icon: "location.fill", title: "Location", action: .saveLocation),
        QuickAction(icon: "person.2.fill", title: "Group", action: .groupPhoto),
        QuickAction(icon: "timer", title: "Timer", action: .timerPhoto)
    ]

    struct QuickAction {
        let icon: String
        let title: String
        let action: ActionType

        enum ActionType {
            case capturePhoto, recordVideo, voiceNote, saveLocation, groupPhoto, timerPhoto
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Collapsed view
            HStack(spacing: 20) {
                ForEach(quickActions.prefix(3), id: \.title) { action in
                    QuickActionButton(action: action) {
                        performAction(action.action)
                    }
                }

                Button(action: {
                    withAnimation(.spring()) {
                        expandedActions.toggle()
                    }
                }) {
                    Image(systemName: expandedActions ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
            }

            // Expanded actions
            if expandedActions {
                HStack(spacing: 20) {
                    ForEach(quickActions.suffix(3), id: \.title) { action in
                        QuickActionButton(action: action) {
                            performAction(action.action)
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10)
        )
    }

    func performAction(_ action: QuickAction.ActionType) {
        HapticManager.shared.trigger(.commandReceived)

        switch action {
        case .capturePhoto:
            MetaGlassesController.shared.sendGlassesCameraCommand()
        case .recordVideo:
            MetaGlassesController.shared.sendGlassesVideoCommand(start: true)
        case .voiceNote:
            // Start voice recording
            break
        case .saveLocation:
            // Save current location
            break
        case .groupPhoto:
            // Start group photo with timer
            break
        case .timerPhoto:
            // Start timer photo
            break
        }
    }
}

struct QuickActionButton: View {
    let action: QuickActionsWidget.QuickAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 24))
                Text(action.title)
                    .font(.caption2)
            }
            .frame(width: 60, height: 60)
            .foregroundColor(.blue)
        }
    }
}

// MARK: - Accessibility Manager
class AccessibilityManager: ObservableObject {
    @Published var voiceOverEnabled = UIAccessibility.isVoiceOverRunning
    @Published var largeTextEnabled = false
    @Published var colorBlindMode: ColorBlindMode = .none
    @Published var oneHandedMode = false

    enum ColorBlindMode: String, CaseIterable {
        case none = "Normal"
        case protanopia = "Protanopia"
        case deuteranopia = "Deuteranopia"
        case tritanopia = "Tritanopia"

        var colorAdjustment: ColorAdjustment {
            switch self {
            case .none:
                return ColorAdjustment(hue: 0, saturation: 1, brightness: 1)
            case .protanopia:
                return ColorAdjustment(hue: 0.1, saturation: 0.8, brightness: 1.1)
            case .deuteranopia:
                return ColorAdjustment(hue: -0.1, saturation: 0.9, brightness: 1.05)
            case .tritanopia:
                return ColorAdjustment(hue: 0.2, saturation: 0.85, brightness: 1.0)
            }
        }
    }

    struct ColorAdjustment {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    init() {
        setupAccessibilityNotifications()
        loadUserPreferences()
    }

    private func setupAccessibilityNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func voiceOverChanged() {
        voiceOverEnabled = UIAccessibility.isVoiceOverRunning
    }

    private func loadUserPreferences() {
        largeTextEnabled = UserDefaults.standard.bool(forKey: "LargeTextEnabled")
        if let modeString = UserDefaults.standard.string(forKey: "ColorBlindMode"),
           let mode = ColorBlindMode(rawValue: modeString) {
            colorBlindMode = mode
        }
        oneHandedMode = UserDefaults.standard.bool(forKey: "OneHandedMode")
    }

    func announceForVoiceOver(_ text: String) {
        guard voiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func setColorBlindMode(_ mode: ColorBlindMode) {
        colorBlindMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "ColorBlindMode")
    }
}

// MARK: - Performance Optimizer
class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()

    private var launchTime: Date?
    private let targetLaunchTime: TimeInterval = 1.0 // Target < 1 second

    func recordAppLaunch() {
        launchTime = Date()
    }

    func recordAppReady() {
        guard let launch = launchTime else { return }
        let launchDuration = Date().timeIntervalSince(launch)

        print("App launch time: \(String(format: "%.2f", launchDuration))s")

        if launchDuration > targetLaunchTime {
            optimizeLaunchTime()
        }
    }

    private func optimizeLaunchTime() {
        // Defer non-critical initialization
        DispatchQueue.main.async {
            // Load heavy resources after launch
        }
    }

    func preloadCommonOperations() {
        // Preload frequently used resources
        DispatchQueue.global(qos: .background).async {
            // Preload AI models
            // Preload common image filters
            // Cache frequently accessed data
        }
    }

    func enableSmartCaching() {
        // Setup intelligent caching
        URLCache.shared.memoryCapacity = 50 * 1024 * 1024 // 50 MB
        URLCache.shared.diskCapacity = 200 * 1024 * 1024 // 200 MB
    }
}

// MARK: - Auto Conversation Summarizer
class ConversationSummarizer: ObservableObject {
    @Published var currentTranscript: [String] = []
    @Published var summary: String = ""
    @Published var keyPoints: [String] = []

    private let maxTranscriptLength = 100 // Lines before auto-summarize

    func addToTranscript(_ text: String) {
        currentTranscript.append(text)

        if currentTranscript.count >= maxTranscriptLength {
            generateSummary()
        }
    }

    func generateSummary() {
        // In real app, use AI to summarize
        let recentConversation = currentTranscript.suffix(20).joined(separator: " ")

        summary = "Summary: Discussed \(currentTranscript.count) topics in the last conversation."

        // Extract key points (simplified)
        keyPoints = [
            "• Main topic discussed",
            "• Action items identified",
            "• Next steps agreed upon"
        ]

        // Clear old transcript, keep recent
        currentTranscript = Array(currentTranscript.suffix(20))
    }

    func clearTranscript() {
        currentTranscript.removeAll()
        summary = ""
        keyPoints.removeAll()
    }
}

// MARK: - Shortcuts Integration
class ShortcutsIntegration {
    static let shared = ShortcutsIntegration()

    func donateShortcuts() {
        // Donate common actions to Siri Shortcuts
        donateCapturePhotoShortcut()
        donateAnalyzeSceneShortcut()
        donateVoiceNoteShortcut()
    }

    private func donateCapturePhotoShortcut() {
        let activity = NSUserActivity(activityType: "com.meta.glasses.capture-photo")
        activity.title = "Capture Photo with Meta Glasses"
        activity.userInfo = ["action": "capture_photo"]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = "capture-photo"

        activity.becomeCurrent()
    }

    private func donateAnalyzeSceneShortcut() {
        let activity = NSUserActivity(activityType: "com.meta.glasses.analyze-scene")
        activity.title = "Analyze What I'm Looking At"
        activity.userInfo = ["action": "analyze_scene"]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = "analyze-scene"

        activity.becomeCurrent()
    }

    private func donateVoiceNoteShortcut() {
        let activity = NSUserActivity(activityType: "com.meta.glasses.voice-note")
        activity.title = "Record Voice Note"
        activity.userInfo = ["action": "voice_note"]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = "voice-note"

        activity.becomeCurrent()
    }
}

// MARK: - Apple Watch Companion Support
class WatchCompanion: NSObject, ObservableObject {
    @Published var isWatchConnected = false
    @Published var lastWatchCommand: String = ""

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    func sendToWatch(_ message: [String: Any]) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(message, replyHandler: nil) { error in
            print("Watch send error: \(error)")
        }
    }

    func sendPhotoToWatch(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.3) else { return }

        session?.sendMessageData(data, replyHandler: nil) { error in
            print("Watch photo send error: \(error)")
        }
    }
}

extension WatchCompanion: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let command = message["command"] as? String {
            DispatchQueue.main.async {
                self.lastWatchCommand = command
                self.handleWatchCommand(command)
            }
        }
    }

    private func handleWatchCommand(_ command: String) {
        switch command {
        case "capture":
            Task { @MainActor in
                MetaGlassesController.shared.sendGlassesCameraCommand()
            }
        case "analyze":
            Task { @MainActor in
                MetaGlassesController.shared.analyzeLastPhoto()
            }
        default:
            break
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
}

// MARK: - Custom Voice Commands
class CustomVoiceCommands: ObservableObject {
    @Published var customCommands: [VoiceCommand] = []

    struct VoiceCommand: Codable, Identifiable {
        let id = UUID()
        var trigger: String
        var action: String
        var response: String
    }

    init() {
        loadDefaultCommands()
        loadCustomCommands()
    }

    private func loadDefaultCommands() {
        customCommands = [
            VoiceCommand(trigger: "what's the weather", action: "check_weather", response: "Checking weather..."),
            VoiceCommand(trigger: "save this moment", action: "save_memory", response: "Moment saved!"),
            VoiceCommand(trigger: "identify this", action: "identify_object", response: "Analyzing..."),
            VoiceCommand(trigger: "translate this", action: "translate_text", response: "Translating..."),
            VoiceCommand(trigger: "find my car", action: "locate_vehicle", response: "Locating your vehicle...")
        ]
    }

    private func loadCustomCommands() {
        if let data = UserDefaults.standard.data(forKey: "CustomVoiceCommands"),
           let commands = try? JSONDecoder().decode([VoiceCommand].self, from: data) {
            customCommands.append(contentsOf: commands)
        }
    }

    func addCommand(_ command: VoiceCommand) {
        customCommands.append(command)
        saveCommands()
    }

    private func saveCommands() {
        if let encoded = try? JSONEncoder().encode(customCommands) {
            UserDefaults.standard.set(encoded, forKey: "CustomVoiceCommands")
        }
    }

    func findCommand(for text: String) -> VoiceCommand? {
        let lowercased = text.lowercased()
        return customCommands.first { command in
            lowercased.contains(command.trigger.lowercased())
        }
    }
}