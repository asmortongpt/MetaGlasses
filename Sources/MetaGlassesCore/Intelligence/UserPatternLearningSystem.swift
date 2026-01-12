import Foundation

/// User Pattern Learning System
/// Learns from user behavior to predict preferences and automate tasks
@MainActor
public class UserPatternLearningSystem: ObservableObject {

    // MARK: - Singleton
    public static let shared = UserPatternLearningSystem()

    // MARK: - Published Properties
    @Published public var learnedPatterns: [LearnedPattern] = []
    @Published public var predictions: [Prediction] = []
    @Published public var isLearning = false

    // MARK: - Properties
    private var actionHistory: [UserAction] = []
    private var contextHistory: [UserContext] = []

    private let contextSystem = ContextAwarenessSystem.shared
    private let knowledgeGraph = KnowledgeGraphSystem.shared
    private let maxHistorySize = 10000

    // Pattern detection thresholds
    private let minOccurrencesForPattern = 3
    private let minConfidenceForPrediction = 0.7

    // MARK: - Initialization
    private init() {
        print("🧠 UserPatternLearningSystem initialized")
        loadHistory()
    }

    // MARK: - Public Methods

    /// Start learning from user behavior
    public func startLearning() {
        guard !isLearning else { return }

        isLearning = true

        // Analyze patterns every 10 minutes
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.analyzePatterns()
            }
        }

        print("✅ Pattern learning started")
    }

    /// Stop learning
    public func stopLearning() {
        isLearning = false
        print("⏹ Pattern learning stopped")
    }

    /// Record user action
    public func recordAction(_ action: UserAction) {
        // Add to history
        actionHistory.append(action)

        // Trim history if needed
        if actionHistory.count > maxHistorySize {
            actionHistory.removeFirst(actionHistory.count - maxHistorySize)
        }

        // Record context at time of action
        let context = contextSystem.getCurrentContext()
        contextHistory.append(context)

        if contextHistory.count > maxHistorySize {
            contextHistory.removeFirst(contextHistory.count - maxHistorySize)
        }

        saveHistory()

        // Trigger pattern analysis if enough data
        if actionHistory.count % 100 == 0 {
            Task {
                await analyzePatterns()
            }
        }
    }

    // MARK: - Pattern Analysis

    /// Analyze patterns from user behavior
    public func analyzePatterns() async {
        print("🔍 Analyzing user patterns...")

        var newPatterns: [LearnedPattern] = []

        // Temporal patterns (time-based)
        newPatterns.append(contentsOf: detectTemporalPatterns())

        // Location patterns
        newPatterns.append(contentsOf: detectLocationPatterns())

        // Sequential patterns (action sequences)
        newPatterns.append(contentsOf: detectSequentialPatterns())

        // Contextual patterns (context → action)
        newPatterns.append(contentsOf: detectContextualPatterns())

        // Update learned patterns
        for pattern in newPatterns {
            if let existingIndex = learnedPatterns.firstIndex(where: { $0.id == pattern.id }) {
                // Update existing pattern
                learnedPatterns[existingIndex].occurrences += 1
                learnedPatterns[existingIndex].lastOccurrence = Date()
                learnedPatterns[existingIndex].confidence = pattern.confidence
            } else {
                // Add new pattern
                if pattern.occurrences >= minOccurrencesForPattern {
                    learnedPatterns.append(pattern)
                }
            }
        }

        // Generate predictions
        await generatePredictions()

        print("✅ Found \(learnedPatterns.count) patterns, generated \(predictions.count) predictions")
    }

    // MARK: - Temporal Patterns

    private func detectTemporalPatterns() -> [LearnedPattern] {
        var patterns: [LearnedPattern] = []

        // Group actions by hour of day
        let actionsWithContext = zip(actionHistory, contextHistory).map { ($0, $1) }

        let byHour = Dictionary(grouping: actionsWithContext) { pair in
            Calendar.current.component(.hour, from: pair.0.timestamp)
        }

        for (hour, actions) in byHour {
            guard actions.count >= minOccurrencesForPattern else { continue }

            // Find most common action at this hour
            let actionCounts = Dictionary(grouping: actions) { $0.0.type.rawValue }
                .mapValues { $0.count }

            if let mostCommon = actionCounts.max(by: { $0.value < $1.value }) {
                let confidence = Double(mostCommon.value) / Double(actions.count)

                if confidence >= minConfidenceForPrediction {
                    let pattern = LearnedPattern(
                        id: UUID(),
                        type: .temporal,
                        description: "User typically performs '\(mostCommon.key)' around \(hour):00",
                        conditions: ["hour": "\(hour)"],
                        predictedAction: ActionType(rawValue: mostCommon.key) ?? .unknown,
                        confidence: confidence,
                        occurrences: mostCommon.value,
                        firstOccurrence: actions.first?.0.timestamp ?? Date(),
                        lastOccurrence: actions.last?.0.timestamp ?? Date()
                    )

                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    // MARK: - Location Patterns

    private func detectLocationPatterns() -> [LearnedPattern] {
        var patterns: [LearnedPattern] = []

        // Group actions by location
        let actionsWithContext = zip(actionHistory, contextHistory).map { ($0, $1) }

        let byLocation = Dictionary(grouping: actionsWithContext) { pair -> String in
            pair.1.location?.placeName ?? "unknown"
        }

        for (location, actions) in byLocation where location != "unknown" {
            guard actions.count >= minOccurrencesForPattern else { continue }

            // Find most common action at this location
            let actionCounts = Dictionary(grouping: actions) { $0.0.type.rawValue }
                .mapValues { $0.count }

            if let mostCommon = actionCounts.max(by: { $0.value < $1.value }) {
                let confidence = Double(mostCommon.value) / Double(actions.count)

                if confidence >= minConfidenceForPrediction {
                    let pattern = LearnedPattern(
                        id: UUID(),
                        type: .location,
                        description: "User typically performs '\(mostCommon.key)' at \(location)",
                        conditions: ["location": location],
                        predictedAction: ActionType(rawValue: mostCommon.key) ?? .unknown,
                        confidence: confidence,
                        occurrences: mostCommon.value,
                        firstOccurrence: actions.first?.0.timestamp ?? Date(),
                        lastOccurrence: actions.last?.0.timestamp ?? Date()
                    )

                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    // MARK: - Sequential Patterns

    private func detectSequentialPatterns() -> [LearnedPattern] {
        var patterns: [LearnedPattern] = []

        // Look for action sequences (A → B)
        for i in 0..<(actionHistory.count - 1) {
            let action1 = actionHistory[i]
            let action2 = actionHistory[i + 1]

            // Check if action2 follows action1 within 5 minutes
            if action2.timestamp.timeIntervalSince(action1.timestamp) < 300 {
                let sequenceKey = "\(action1.type.rawValue) → \(action2.type.rawValue)"

                // Count occurrences of this sequence
                var occurrences = 0

                for j in 0..<(actionHistory.count - 1) {
                    let a1 = actionHistory[j]
                    let a2 = actionHistory[j + 1]

                    if a1.type == action1.type && a2.type == action2.type {
                        if a2.timestamp.timeIntervalSince(a1.timestamp) < 300 {
                            occurrences += 1
                        }
                    }
                }

                if occurrences >= minOccurrencesForPattern {
                    let pattern = LearnedPattern(
                        id: UUID(),
                        type: .sequential,
                        description: "After '\(action1.type.rawValue)', user usually does '\(action2.type.rawValue)'",
                        conditions: ["previous_action": action1.type.rawValue],
                        predictedAction: action2.type,
                        confidence: Double(occurrences) / Double(actionHistory.count),
                        occurrences: occurrences,
                        firstOccurrence: action1.timestamp,
                        lastOccurrence: Date()
                    )

                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    // MARK: - Contextual Patterns

    private func detectContextualPatterns() -> [LearnedPattern] {
        var patterns: [LearnedPattern] = []

        // Group actions by context type (activity + time of day)
        let actionsWithContext = zip(actionHistory, contextHistory).map { ($0, $1) }

        let byContext = Dictionary(grouping: actionsWithContext) { pair -> String in
            "\(pair.1.activityType.rawValue)_\(pair.1.timeOfDay.rawValue)"
        }

        for (contextKey, actions) in byContext {
            guard actions.count >= minOccurrencesForPattern else { continue }

            let actionCounts = Dictionary(grouping: actions) { $0.0.type.rawValue }
                .mapValues { $0.count }

            if let mostCommon = actionCounts.max(by: { $0.value < $1.value }) {
                let confidence = Double(mostCommon.value) / Double(actions.count)

                if confidence >= minConfidenceForPrediction {
                    let components = contextKey.split(separator: "_")

                    let pattern = LearnedPattern(
                        id: UUID(),
                        type: .contextual,
                        description: "When \(components[0]) during \(components[1]), user usually does '\(mostCommon.key)'",
                        conditions: [
                            "activity": String(components[0]),
                            "time_of_day": String(components[1])
                        ],
                        predictedAction: ActionType(rawValue: mostCommon.key) ?? .unknown,
                        confidence: confidence,
                        occurrences: mostCommon.value,
                        firstOccurrence: actions.first?.0.timestamp ?? Date(),
                        lastOccurrence: actions.last?.0.timestamp ?? Date()
                    )

                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    // MARK: - Predictions

    private func generatePredictions() async {
        var newPredictions: [Prediction] = []

        let currentContext = contextSystem.getCurrentContext()

        // Check each learned pattern
        for pattern in learnedPatterns {
            guard pattern.confidence >= minConfidenceForPrediction else { continue }

            // Check if pattern conditions match current context
            var matches = true

            for (key, value) in pattern.conditions {
                switch key {
                case "hour":
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    if value != "\(currentHour)" {
                        matches = false
                    }

                case "location":
                    if value != (currentContext.location?.placeName ?? "unknown") {
                        matches = false
                    }

                case "activity":
                    if value != currentContext.activityType.rawValue {
                        matches = false
                    }

                case "time_of_day":
                    if value != currentContext.timeOfDay.rawValue {
                        matches = false
                    }

                default:
                    break
                }
            }

            if matches {
                let prediction = Prediction(
                    id: UUID(),
                    patternId: pattern.id,
                    predictedAction: pattern.predictedAction,
                    confidence: pattern.confidence,
                    reasoning: pattern.description,
                    createdAt: Date()
                )

                newPredictions.append(prediction)
            }
        }

        // Sort by confidence
        newPredictions.sort { $0.confidence > $1.confidence }

        predictions = newPredictions
    }

    // MARK: - Persistence

    private var actionsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("user_actions.json")
    }

    private var patternsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("learned_patterns.json")
    }

    private func saveHistory() {
        // Save actions (last 1000)
        let recentActions = Array(actionHistory.suffix(1000))

        if let data = try? JSONEncoder().encode(recentActions) {
            try? data.write(to: actionsFileURL)
        }

        // Save patterns
        if let data = try? JSONEncoder().encode(learnedPatterns) {
            try? data.write(to: patternsFileURL)
        }
    }

    private func loadHistory() {
        // Load actions
        if let data = try? Data(contentsOf: actionsFileURL),
           let actions = try? JSONDecoder().decode([UserAction].self, from: data) {
            actionHistory = actions
            print("📚 Loaded \(actionHistory.count) user actions")
        }

        // Load patterns
        if let data = try? Data(contentsOf: patternsFileURL),
           let patterns = try? JSONDecoder().decode([LearnedPattern].self, from: data) {
            learnedPatterns = patterns
            print("🧠 Loaded \(learnedPatterns.count) learned patterns")
        }
    }

    /// Clear all learning data
    public func clearLearning() {
        actionHistory.removeAll()
        contextHistory.removeAll()
        learnedPatterns.removeAll()
        predictions.removeAll()

        saveHistory()

        print("🗑️ Cleared all learning data")
    }
}

// MARK: - Models

public struct UserAction: Codable {
    public let id: UUID
    public let type: ActionType
    public let timestamp: Date
    public let metadata: [String: String]

    public init(id: UUID, type: ActionType, timestamp: Date, metadata: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum ActionType: String, Codable {
    case capturePhoto
    case recordVideo
    case analyzePhoto
    case recognizeFace
    case addMemory
    case viewGallery
    case useVoiceCommand
    case acceptSuggestion
    case dismissSuggestion
    case unknown
}

public struct LearnedPattern: Codable, Identifiable {
    public let id: UUID
    public let type: PatternType
    public let description: String
    public let conditions: [String: String]
    public let predictedAction: ActionType
    public var confidence: Double
    public var occurrences: Int
    public let firstOccurrence: Date
    public var lastOccurrence: Date

    public init(id: UUID, type: PatternType, description: String, conditions: [String: String], predictedAction: ActionType, confidence: Double, occurrences: Int, firstOccurrence: Date, lastOccurrence: Date) {
        self.id = id
        self.type = type
        self.description = description
        self.conditions = conditions
        self.predictedAction = predictedAction
        self.confidence = confidence
        self.occurrences = occurrences
        self.firstOccurrence = firstOccurrence
        self.lastOccurrence = lastOccurrence
    }
}

public enum PatternType: String, Codable {
    case temporal       // Time-based pattern
    case location       // Location-based pattern
    case sequential     // Action sequence pattern
    case contextual     // Context-based pattern
}

public struct Prediction: Codable, Identifiable {
    public let id: UUID
    public let patternId: UUID
    public let predictedAction: ActionType
    public let confidence: Double
    public let reasoning: String
    public let createdAt: Date

    public init(id: UUID, patternId: UUID, predictedAction: ActionType, confidence: Double, reasoning: String, createdAt: Date) {
        self.id = id
        self.patternId = patternId
        self.predictedAction = predictedAction
        self.confidence = confidence
        self.reasoning = reasoning
        self.createdAt = createdAt
    }
}
