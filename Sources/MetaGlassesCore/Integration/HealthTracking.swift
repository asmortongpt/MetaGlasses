import Foundation
import HealthKit
import CoreLocation

/// Health Tracking Integration
/// Integrates with HealthKit to track activity, correlate with photos, and provide wellness insights
@MainActor
public class HealthTracking: ObservableObject {

    // MARK: - Singleton
    public static let shared = HealthTracking()

    // MARK: - Published Properties
    @Published public var hasHealthAccess = false
    @Published public var todayStats: DailyHealthStats = DailyHealthStats()
    @Published public var currentActivity: ActivityMetrics?
    @Published public var wellnessScore: Double = 0.0

    // MARK: - Properties
    private let healthStore = HKHealthStore()
    private var monitoringTimer: Timer?
    private let contextSystem = ContextAwarenessSystem.shared

    // Health data types to read
    private let healthTypesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType()
    ]

    // Activity correlation
    private var activityPhotoCorrelations: [ActivityPhotoCorrelation] = []

    // MARK: - Initialization
    private init() {
        print("💪 HealthTracking initialized")

        if HKHealthStore.isHealthDataAvailable() {
            requestHealthAccess()
        } else {
            print("⚠️ HealthKit not available on this device")
        }
    }

    // MARK: - Public Methods

    /// Request HealthKit access
    public func requestHealthAccess() {
        Task {
            do {
                try await healthStore.requestAuthorization(toShare: [], read: healthTypesToRead)
                hasHealthAccess = true

                print("✅ HealthKit access granted")

                await loadTodayStats()
                startMonitoring()
            } catch {
                print("❌ HealthKit authorization error: \(error.localizedDescription)")
            }
        }
    }

    /// Start monitoring health data
    public func startMonitoring() {
        guard hasHealthAccess else { return }

        // Update health stats every 5 minutes
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadTodayStats()
                await self?.updateActivityMetrics()
                await self?.calculateWellnessScore()
            }
        }

        print("✅ Health monitoring started")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("⏹ Health monitoring stopped")
    }

    // MARK: - Today's Statistics

    /// Load today's health statistics
    public func loadTodayStats() async {
        guard hasHealthAccess else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        // Load steps
        if let steps = await queryQuantitySum(
            identifier: .stepCount,
            start: startOfDay,
            end: now
        ) {
            todayStats.steps = Int(steps)
        }

        // Load distance
        if let distance = await queryQuantitySum(
            identifier: .distanceWalkingRunning,
            start: startOfDay,
            end: now
        ) {
            todayStats.distance = distance / 1000 // Convert to km
        }

        // Load calories
        if let calories = await queryQuantitySum(
            identifier: .activeEnergyBurned,
            start: startOfDay,
            end: now
        ) {
            todayStats.activeCalories = Int(calories)
        }

        // Load heart rate
        if let heartRate = await queryQuantityMostRecent(identifier: .heartRate) {
            todayStats.currentHeartRate = Int(heartRate)
        }

        // Load resting heart rate
        if let restingHR = await queryQuantityMostRecent(identifier: .restingHeartRate) {
            todayStats.restingHeartRate = Int(restingHR)
        }

        // Load sleep data
        todayStats.sleepHours = await querySleepHours(for: now)

        print("📊 Today's stats: \(todayStats.steps) steps, \(String(format: "%.1f", todayStats.distance)) km")
    }

    // MARK: - Activity Metrics

    /// Update current activity metrics
    private func updateActivityMetrics() async {
        let context = contextSystem.getCurrentContext()

        var metrics = ActivityMetrics()
        metrics.activityType = context.activityType
        metrics.timestamp = Date()

        // Get recent heart rate
        if let heartRate = await queryQuantityMostRecent(identifier: .heartRate) {
            metrics.heartRate = Int(heartRate)
        }

        // Get steps in last 10 minutes
        let tenMinutesAgo = Date().addingTimeInterval(-600)
        if let steps = await queryQuantitySum(
            identifier: .stepCount,
            start: tenMinutesAgo,
            end: Date()
        ) {
            metrics.recentSteps = Int(steps)
        }

        // Get calories in last 10 minutes
        if let calories = await queryQuantitySum(
            identifier: .activeEnergyBurned,
            start: tenMinutesAgo,
            end: Date()
        ) {
            metrics.recentCalories = Int(calories)
        }

        currentActivity = metrics
    }

    // MARK: - Health Queries

    private func queryQuantitySum(
        identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("❌ Health query error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                let unit = self.getUnit(for: identifier)
                let sum = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: sum)
            }

            healthStore.execute(query)
        }
    }

    private func queryQuantityMostRecent(identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("❌ Health query error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let unit = self.getUnit(for: identifier)
                    let value = sample.quantity.doubleValue(for: unit)
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    private func querySleepHours(for date: Date) async -> Double {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return 0
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("❌ Sleep query error: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }

                var totalSleepSeconds: TimeInterval = 0

                for case let sample as HKCategorySample in samples ?? [] {
                    if sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        totalSleepSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }

                let hours = totalSleepSeconds / 3600
                continuation.resume(returning: hours)
            }

            healthStore.execute(query)
        }
    }

    private func getUnit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .stepCount:
            return .count()
        case .distanceWalkingRunning:
            return .meter()
        case .activeEnergyBurned:
            return .kilocalorie()
        case .heartRate, .restingHeartRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .vo2Max:
            return HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .bodyMass:
            return .gramUnit(with: .kilo)
        default:
            return .count()
        }
    }

    // MARK: - Wellness Score

    /// Calculate overall wellness score (0-100)
    private func calculateWellnessScore() async {
        var score: Double = 0.0
        var components = 0

        // Steps component (0-30 points)
        let stepGoal = 10000.0
        let stepScore = min(30.0, (Double(todayStats.steps) / stepGoal) * 30.0)
        score += stepScore
        components += 1

        // Sleep component (0-25 points)
        let sleepGoal = 8.0
        let sleepScore = min(25.0, (todayStats.sleepHours / sleepGoal) * 25.0)
        score += sleepScore
        components += 1

        // Active calories component (0-20 points)
        let calorieGoal = 500.0
        let calorieScore = min(20.0, (Double(todayStats.activeCalories) / calorieGoal) * 20.0)
        score += calorieScore
        components += 1

        // Heart rate component (0-15 points)
        if todayStats.restingHeartRate > 0 {
            // Ideal resting heart rate: 60-80 bpm
            let hrScore: Double
            if todayStats.restingHeartRate >= 60 && todayStats.restingHeartRate <= 80 {
                hrScore = 15.0
            } else {
                let deviation = abs(70.0 - Double(todayStats.restingHeartRate))
                hrScore = max(0, 15.0 - deviation * 0.5)
            }
            score += hrScore
            components += 1
        }

        // Distance component (0-10 points)
        let distanceGoal = 5.0 // 5 km
        let distanceScore = min(10.0, (todayStats.distance / distanceGoal) * 10.0)
        score += distanceScore
        components += 1

        wellnessScore = score

        print("💯 Wellness score: \(Int(wellnessScore))/100")
    }

    // MARK: - Activity-Photo Correlation

    /// Record photo taken with current health metrics
    public func recordPhotoWithHealthData() async {
        guard hasHealthAccess else { return }

        await updateActivityMetrics()

        guard let activity = currentActivity else { return }

        let correlation = ActivityPhotoCorrelation(
            timestamp: Date(),
            activityType: activity.activityType,
            heartRate: activity.heartRate,
            steps: todayStats.steps,
            calories: todayStats.activeCalories,
            location: contextSystem.getCurrentContext().location?.placeName
        )

        activityPhotoCorrelations.append(correlation)

        // Keep only last 1000 correlations
        if activityPhotoCorrelations.count > 1000 {
            activityPhotoCorrelations.removeFirst()
        }

        saveCorrelations()
    }

    /// Analyze photo-taking patterns based on health data
    public func analyzePhotoHealthPatterns() -> PhotoHealthPatternAnalysis {
        var analysis = PhotoHealthPatternAnalysis()

        if activityPhotoCorrelations.isEmpty {
            return analysis
        }

        // Analyze by activity type
        let byActivity = Dictionary(grouping: activityPhotoCorrelations) { $0.activityType }

        for (activity, correlations) in byActivity {
            analysis.photosByActivity[activity.rawValue] = correlations.count
        }

        // Find most active photo-taking activity
        if let mostActive = analysis.photosByActivity.max(by: { $0.value < $1.value }) {
            analysis.mostActivePhotoActivity = mostActive.key
        }

        // Calculate average heart rate during photo taking
        let totalHR = activityPhotoCorrelations.compactMap { $0.heartRate }.reduce(0, +)
        let hrCount = activityPhotoCorrelations.filter { $0.heartRate != nil }.count

        if hrCount > 0 {
            analysis.averageHeartRateDuringPhotos = Double(totalHR) / Double(hrCount)
        }

        // Analyze steps correlation
        let avgSteps = activityPhotoCorrelations.map { $0.steps }.reduce(0, +) / max(1, activityPhotoCorrelations.count)
        analysis.averageStepsWhenPhotographing = avgSteps

        print("📊 Photo-health pattern analysis complete")
        return analysis
    }

    // MARK: - Wellness Suggestions

    /// Get personalized wellness suggestions
    public func getWellnessSuggestions() -> [WellnessSuggestion] {
        var suggestions: [WellnessSuggestion] = []

        // Step suggestions
        if todayStats.steps < 10000 {
            let remaining = 10000 - todayStats.steps
            suggestions.append(WellnessSuggestion(
                id: UUID(),
                type: .activity,
                title: "Keep Moving",
                message: "You need \(remaining) more steps to reach your goal. Take a short walk!",
                priority: .medium
            ))
        }

        // Sleep suggestions
        if todayStats.sleepHours < 7.0 {
            suggestions.append(WellnessSuggestion(
                id: UUID(),
                type: .sleep,
                title: "Rest Up",
                message: "You slept only \(String(format: "%.1f", todayStats.sleepHours)) hours. Aim for 7-8 hours tonight.",
                priority: .high
            ))
        }

        // Heart rate suggestions
        if let hr = currentActivity?.heartRate {
            if hr > 100 {
                suggestions.append(WellnessSuggestion(
                    id: UUID(),
                    type: .heartRate,
                    title: "Take a Break",
                    message: "Your heart rate is elevated (\(hr) bpm). Consider resting.",
                    priority: .high
                ))
            }
        }

        // Calorie suggestions
        if todayStats.activeCalories < 300 {
            suggestions.append(WellnessSuggestion(
                id: UUID(),
                type: .activity,
                title: "Get Active",
                message: "Low activity today. A 20-minute workout would help!",
                priority: .medium
            ))
        }

        // Distance suggestions
        if todayStats.distance < 3.0 {
            suggestions.append(WellnessSuggestion(
                id: UUID(),
                type: .activity,
                title: "Take a Walk",
                message: "You've walked \(String(format: "%.1f", todayStats.distance)) km today. Try for 5 km!",
                priority: .low
            ))
        }

        return suggestions.sorted(by: { $0.priority.rawValue > $1.priority.rawValue })
    }

    // MARK: - Persistence

    private var correlationsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("activity_photo_correlations.json")
    }

    private func saveCorrelations() {
        // Save last 1000 correlations
        let recentCorrelations = Array(activityPhotoCorrelations.suffix(1000))

        if let data = try? JSONEncoder().encode(recentCorrelations) {
            try? data.write(to: correlationsFileURL)
        }
    }

    private func loadCorrelations() {
        if let data = try? Data(contentsOf: correlationsFileURL),
           let correlations = try? JSONDecoder().decode([ActivityPhotoCorrelation].self, from: data) {
            activityPhotoCorrelations = correlations
            print("📚 Loaded \(activityPhotoCorrelations.count) activity correlations")
        }
    }

    /// Clear all health data
    public func clearHealthData() {
        activityPhotoCorrelations.removeAll()
        todayStats = DailyHealthStats()
        currentActivity = nil
        wellnessScore = 0.0
        saveCorrelations()

        print("🗑️ Cleared health data")
    }
}

// MARK: - Models

public struct DailyHealthStats {
    public var steps: Int = 0
    public var distance: Double = 0.0 // km
    public var activeCalories: Int = 0
    public var currentHeartRate: Int = 0
    public var restingHeartRate: Int = 0
    public var sleepHours: Double = 0.0

    public init() {}
}

public struct ActivityMetrics {
    public var activityType: ActivityType = .unknown
    public var heartRate: Int?
    public var recentSteps: Int = 0
    public var recentCalories: Int = 0
    public var timestamp: Date = Date()

    public init() {}
}

public struct ActivityPhotoCorrelation: Codable {
    public let timestamp: Date
    public let activityType: ActivityType
    public let heartRate: Int?
    public let steps: Int
    public let calories: Int
    public let location: String?

    public init(timestamp: Date, activityType: ActivityType, heartRate: Int?, steps: Int, calories: Int, location: String?) {
        self.timestamp = timestamp
        self.activityType = activityType
        self.heartRate = heartRate
        self.steps = steps
        self.calories = calories
        self.location = location
    }
}

public struct PhotoHealthPatternAnalysis {
    public var photosByActivity: [String: Int] = [:]
    public var mostActivePhotoActivity: String?
    public var averageHeartRateDuringPhotos: Double = 0.0
    public var averageStepsWhenPhotographing: Int = 0

    public init() {}
}

public struct WellnessSuggestion: Identifiable {
    public let id: UUID
    public let type: SuggestionType
    public let title: String
    public let message: String
    public let priority: Priority

    public init(id: UUID, type: SuggestionType, title: String, message: String, priority: Priority) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.priority = priority
    }

    public enum SuggestionType: String {
        case activity
        case sleep
        case heartRate
        case nutrition
        case hydration
    }

    public enum Priority: Int {
        case low = 1
        case medium = 2
        case high = 3
    }
}
