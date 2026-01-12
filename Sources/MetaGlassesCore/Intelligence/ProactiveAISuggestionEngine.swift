import Foundation
import CoreLocation

/// Proactive AI Suggestion Engine
/// Generates intelligent, context-aware suggestions based on user patterns and current context
@MainActor
public class ProactiveAISuggestionEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = ProactiveAISuggestionEngine()

    // MARK: - Published Properties
    @Published public var currentSuggestions: [AISuggestion] = []
    @Published public var suggestionHistory: [AISuggestion] = []
    @Published public var isActive = false

    // MARK: - Properties
    private let contextSystem = ContextAwarenessSystem.shared
    private let weatherService = WeatherService.shared
    private let memorySystem = ProductionRAGMemory.shared
    private var suggestionTimer: Timer?

    // Learning data
    private var acceptedSuggestions: [String] = []
    private var dismissedSuggestions: [String] = []
    private var suggestionPatterns: [String: SuggestionPattern] = [:]

    // MARK: - Initialization
    private init() {
        print("🤖 ProactiveAISuggestionEngine initialized")
        loadSuggestionHistory()
    }

    // MARK: - Public Methods

    /// Start generating proactive suggestions
    public func startSuggestions() {
        guard !isActive else { return }

        isActive = true

        // Generate suggestions every 5 minutes
        suggestionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.generateSuggestions()
            }
        }

        // Generate initial suggestions
        Task {
            await generateSuggestions()
        }

        print("✅ Proactive suggestions started")
    }

    /// Stop generating suggestions
    public func stopSuggestions() {
        suggestionTimer?.invalidate()
        suggestionTimer = nil
        isActive = false

        print("⏹ Proactive suggestions stopped")
    }

    // MARK: - Suggestion Generation

    /// Generate context-aware suggestions
    public func generateSuggestions() async {
        var newSuggestions: [AISuggestion] = []

        // Get current context
        let context = contextSystem.getCurrentContext()

        // Time-based suggestions
        newSuggestions.append(contentsOf: await generateTimeSuggestions(context: context))

        // Location-based suggestions
        newSuggestions.append(contentsOf: await generateLocationSuggestions(context: context))

        // Weather-based suggestions
        newSuggestions.append(contentsOf: await generateWeatherSuggestions(context: context))

        // Activity-based suggestions
        newSuggestions.append(contentsOf: await generateActivitySuggestions(context: context))

        // Pattern-based suggestions (learned from history)
        newSuggestions.append(contentsOf: await generatePatternSuggestions(context: context))

        // Memory-based suggestions
        newSuggestions.append(contentsOf: await generateMemorySuggestions(context: context))

        // Battery-based suggestions
        if context.batteryLevel < 0.2 {
            newSuggestions.append(AISuggestion(
                id: UUID(),
                type: .reminder,
                priority: .high,
                title: "Low Battery",
                message: "Your battery is below 20%. Consider charging your device.",
                action: SuggestionAction.openSettings,
                context: context,
                createdAt: Date()
            ))
        }

        // Filter duplicates and low-priority suggestions
        newSuggestions = filterSuggestions(newSuggestions)

        // Sort by priority
        newSuggestions.sort { $0.priority.rawValue > $1.priority.rawValue }

        // Update current suggestions (limit to top 5)
        currentSuggestions = Array(newSuggestions.prefix(5))

        // Add to history
        suggestionHistory.append(contentsOf: currentSuggestions)
        if suggestionHistory.count > 100 {
            suggestionHistory.removeFirst(suggestionHistory.count - 100)
        }

        saveSuggestionHistory()

        print("💡 Generated \(currentSuggestions.count) suggestions")
    }

    // MARK: - Time-Based Suggestions

    private func generateTimeSuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []
        let hour = Calendar.current.component(.hour, from: Date())

        switch context.timeOfDay {
        case .earlyMorning:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .action,
                priority: .medium,
                title: "Good Morning!",
                message: "Start your day with a photo of the sunrise.",
                action: .openCamera,
                context: context,
                createdAt: Date()
            ))

        case .morning:
            if context.isWorkHours {
                suggestions.append(AISuggestion(
                    id: UUID(),
                    type: .reminder,
                    priority: .medium,
                    title: "Work Day Started",
                    message: "Capture important moments during meetings.",
                    action: .enableAutoCapture,
                    context: context,
                    createdAt: Date()
                ))
            }

        case .afternoon:
            // Lunch time suggestion
            if hour >= 12 && hour < 14 {
                suggestions.append(AISuggestion(
                    id: UUID(),
                    type: .action,
                    priority: .low,
                    title: "Lunch Time",
                    message: "Document your meal for nutrition tracking.",
                    action: .openCamera,
                    context: context,
                    createdAt: Date()
                ))
            }

        case .evening:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .insight,
                priority: .medium,
                title: "Golden Hour",
                message: "Perfect lighting for outdoor photos right now!",
                action: .openCamera,
                context: context,
                createdAt: Date()
            ))

        case .night:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .reminder,
                priority: .low,
                title: "Review Your Day",
                message: "Look back at today's captured moments.",
                action: .openGallery,
                context: context,
                createdAt: Date()
            ))

        case .unknown:
            break
        }

        return suggestions
    }

    // MARK: - Location-Based Suggestions

    private func generateLocationSuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        guard let location = context.location else { return suggestions }

        // Check if this is a new location
        let predictedLocation = contextSystem.predictNextLocation()

        if let placeName = location.placeName, placeName != predictedLocation {
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .action,
                priority: .medium,
                title: "New Location Detected",
                message: "You're at \(placeName). Capture this moment!",
                action: .openCamera,
                context: context,
                createdAt: Date()
            ))
        }

        // Check for memorable locations
        if let placeName = location.placeName {
            do {
                let memories = try await memorySystem.retrieveRelevant(query: placeName, limit: 3)

                if !memories.isEmpty {
                    suggestions.append(AISuggestion(
                        id: UUID(),
                        type: .insight,
                        priority: .medium,
                        title: "Familiar Location",
                        message: "You have \(memories.count) memories here. Want to add another?",
                        action: .openCamera,
                        context: context,
                        createdAt: Date()
                    ))
                }
            } catch {
                print("❌ Memory retrieval failed: \(error)")
            }
        }

        return suggestions
    }

    // MARK: - Weather-Based Suggestions

    private func generateWeatherSuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        // Get current weather if available
        guard let weather = weatherService.currentWeather else {
            return suggestions
        }

        let temp = weather.currentWeather.temperature.value

        // Temperature-based suggestions
        if temp > 30 {
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .reminder,
                priority: .high,
                title: "Hot Weather Alert",
                message: "It's \(Int(temp))°C. Keep your glasses protected from heat.",
                action: .none,
                context: context,
                createdAt: Date()
            ))
        }

        // Photo tip suggestions
        let photoTips = weatherService.getPhotoTips()
        if !photoTips.isEmpty, let firstTip = photoTips.first {
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .insight,
                priority: .low,
                title: "Photo Tip",
                message: firstTip,
                action: .openCamera,
                context: context,
                createdAt: Date()
            ))
        }

        return suggestions
    }

    // MARK: - Activity-Based Suggestions

    private func generateActivitySuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        switch context.activityType {
        case .walking:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .action,
                priority: .low,
                title: "Walking Detected",
                message: "Capture interesting sights along your walk.",
                action: .enableAutoCapture,
                context: context,
                createdAt: Date()
            ))

        case .driving:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .reminder,
                priority: .high,
                title: "Focus on Driving",
                message: "Stay safe. Voice commands are available hands-free.",
                action: .none,
                context: context,
                createdAt: Date()
            ))

        case .stationary:
            // No specific suggestion for stationary
            break

        case .running, .cycling:
            suggestions.append(AISuggestion(
                id: UUID(),
                type: .action,
                priority: .medium,
                title: "Exercise Detected",
                message: "Capture your workout route or achievements.",
                action: .openCamera,
                context: context,
                createdAt: Date()
            ))

        case .unknown:
            break
        }

        return suggestions
    }

    // MARK: - Pattern-Based Suggestions

    private func generatePatternSuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        // Analyze suggestion patterns
        for (suggestionKey, pattern) in suggestionPatterns {
            // If this suggestion was accepted often at this time/location
            if pattern.acceptanceRate > 0.7 && pattern.occurrences > 3 {
                // Suggest similar action
                suggestions.append(AISuggestion(
                    id: UUID(),
                    type: .action,
                    priority: .medium,
                    title: "Suggested Action",
                    message: pattern.description,
                    action: .custom(suggestionKey),
                    context: context,
                    createdAt: Date()
                ))
            }
        }

        return suggestions
    }

    // MARK: - Memory-Based Suggestions

    private func generateMemorySuggestions(context: UserContext) async -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        // Check for anniversary memories (same date last year)
        let calendar = Calendar.current
        let lastYear = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()

        do {
            let memories = try await memorySystem.retrieveRelevant(
                query: "memories from one year ago",
                limit: 3,
                threshold: 0.6
            )

            if !memories.isEmpty {
                suggestions.append(AISuggestion(
                    id: UUID(),
                    type: .insight,
                    priority: .medium,
                    title: "Memory Lane",
                    message: "You have memories from this time last year. Want to revisit?",
                    action: .openMemories,
                    context: context,
                    createdAt: Date()
                ))
            }
        } catch {
            print("❌ Memory-based suggestion failed: \(error)")
        }

        return suggestions
    }

    // MARK: - Suggestion Management

    /// Mark suggestion as accepted
    public func acceptSuggestion(_ suggestion: AISuggestion) {
        acceptedSuggestions.append(suggestion.id.uuidString)

        // Update pattern learning
        updateSuggestionPattern(for: suggestion, accepted: true)

        // Remove from current suggestions
        currentSuggestions.removeAll { $0.id == suggestion.id }

        print("✅ Suggestion accepted: \(suggestion.title)")
    }

    /// Mark suggestion as dismissed
    public func dismissSuggestion(_ suggestion: AISuggestion) {
        dismissedSuggestions.append(suggestion.id.uuidString)

        // Update pattern learning
        updateSuggestionPattern(for: suggestion, accepted: false)

        // Remove from current suggestions
        currentSuggestions.removeAll { $0.id == suggestion.id }

        print("❌ Suggestion dismissed: \(suggestion.title)")
    }

    // MARK: - Pattern Learning

    private func updateSuggestionPattern(for suggestion: AISuggestion, accepted: Bool) {
        let key = "\(suggestion.type.rawValue)-\(suggestion.context.timeOfDay.rawValue)"

        if var pattern = suggestionPatterns[key] {
            pattern.occurrences += 1
            if accepted {
                pattern.acceptances += 1
            }
            pattern.acceptanceRate = Double(pattern.acceptances) / Double(pattern.occurrences)
            suggestionPatterns[key] = pattern
        } else {
            suggestionPatterns[key] = SuggestionPattern(
                type: suggestion.type,
                timeOfDay: suggestion.context.timeOfDay,
                description: suggestion.message,
                occurrences: 1,
                acceptances: accepted ? 1 : 0,
                acceptanceRate: accepted ? 1.0 : 0.0
            )
        }
    }

    // MARK: - Filtering

    private func filterSuggestions(_ suggestions: [AISuggestion]) -> [AISuggestion] {
        var filtered: [AISuggestion] = []
        var seenTitles = Set<String>()

        for suggestion in suggestions {
            // Skip duplicates
            if seenTitles.contains(suggestion.title) {
                continue
            }

            // Skip if recently dismissed
            if dismissedSuggestions.suffix(10).contains(suggestion.id.uuidString) {
                continue
            }

            filtered.append(suggestion)
            seenTitles.insert(suggestion.title)
        }

        return filtered
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("suggestion_history.json")
    }

    private func saveSuggestionHistory() {
        // Save last 100 suggestions
        let recentHistory = Array(suggestionHistory.suffix(100))

        if let data = try? JSONEncoder().encode(recentHistory) {
            try? data.write(to: fileURL)
        }
    }

    private func loadSuggestionHistory() {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode([AISuggestion].self, from: data) else {
            return
        }

        suggestionHistory = history
        print("📚 Loaded \(suggestionHistory.count) suggestion history entries")
    }
}

// MARK: - Models

public struct AISuggestion: Codable, Identifiable {
    public let id: UUID
    public let type: SuggestionType
    public let priority: SuggestionPriority
    public let title: String
    public let message: String
    public let action: SuggestionAction
    public let context: UserContext
    public let createdAt: Date

    public init(id: UUID, type: SuggestionType, priority: SuggestionPriority, title: String, message: String, action: SuggestionAction, context: UserContext, createdAt: Date) {
        self.id = id
        self.type = type
        self.priority = priority
        self.title = title
        self.message = message
        self.action = action
        self.context = context
        self.createdAt = createdAt
    }
}

public enum SuggestionType: String, Codable {
    case reminder
    case action
    case insight
    case warning
}

public enum SuggestionPriority: Int, Codable {
    case low = 1
    case medium = 2
    case high = 3
}

public enum SuggestionAction: Codable, Equatable {
    case none
    case openCamera
    case openGallery
    case openMemories
    case enableAutoCapture
    case openSettings
    case custom(String)

    public static func == (lhs: SuggestionAction, rhs: SuggestionAction) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none),
             (.openCamera, .openCamera),
             (.openGallery, .openGallery),
             (.openMemories, .openMemories),
             (.enableAutoCapture, .enableAutoCapture),
             (.openSettings, .openSettings):
            return true
        case (.custom(let a), .custom(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct SuggestionPattern {
    var type: SuggestionType
    var timeOfDay: TimeOfDay
    var description: String
    var occurrences: Int
    var acceptances: Int
    var acceptanceRate: Double
}
