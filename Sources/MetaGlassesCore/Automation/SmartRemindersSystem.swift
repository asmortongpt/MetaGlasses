import Foundation
import UserNotifications
import CoreLocation

/// Smart Reminders System
/// Context-aware intelligent reminders that learn from user behavior
@MainActor
public class SmartRemindersSystem: ObservableObject {

    // MARK: - Singleton
    public static let shared = SmartRemindersSystem()

    // MARK: - Published Properties
    @Published public var activeReminders: [SmartReminder] = []
    @Published public var scheduledReminders: [SmartReminder] = []
    @Published public var reminderHistory: [ReminderEvent] = []

    // MARK: - Properties
    private let contextSystem = ContextAwarenessSystem.shared
    private let patternLearning = UserPatternLearningSystem.shared
    private let calendar = CalendarIntegration.shared
    private let health = HealthTracking.shared

    private var monitoringTimer: Timer?
    private var dismissalPatterns: [String: DismissalPattern] = [:]

    // Reminder templates
    public var reminderTemplates: [ReminderTemplate] = []

    // MARK: - Initialization
    private init() {
        loadReminders()
        loadDismissalPatterns()
        createDefaultTemplates()
        print("⏰ SmartRemindersSystem initialized")
    }

    // MARK: - Public Methods

    /// Start reminder monitoring
    public func startMonitoring() {
        // Check reminders every minute
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkReminders()
            }
        }

        print("✅ Smart reminders monitoring started")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("⏹ Smart reminders monitoring stopped")
    }

    /// Create new reminder
    public func createReminder(_ reminder: SmartReminder) {
        scheduledReminders.append(reminder)
        saveReminders()

        print("➕ Created reminder: \(reminder.title)")
    }

    /// Remove reminder
    public func removeReminder(_ reminderId: UUID) {
        scheduledReminders.removeAll { $0.id == reminderId }
        activeReminders.removeAll { $0.id == reminderId }
        saveReminders()

        print("➖ Removed reminder: \(reminderId)")
    }

    /// Dismiss reminder
    public func dismissReminder(_ reminderId: UUID, reason: DismissalReason) {
        if let index = activeReminders.firstIndex(where: { $0.id == reminderId }) {
            let reminder = activeReminders[index]

            // Record dismissal
            recordDismissal(reminder, reason: reason)

            // Remove from active
            activeReminders.remove(at: index)

            // Reschedule if recurring
            if reminder.isRecurring {
                if let nextReminder = rescheduleReminder(reminder) {
                    scheduledReminders.append(nextReminder)
                }
            }

            saveReminders()

            print("✓ Dismissed reminder: \(reminder.title)")
        }
    }

    /// Snooze reminder
    public func snoozeReminder(_ reminderId: UUID, duration: TimeInterval) {
        if let index = activeReminders.firstIndex(where: { $0.id == reminderId }) {
            var reminder = activeReminders[index]
            reminder.scheduledTime = Date().addingTimeInterval(duration)

            activeReminders.remove(at: index)
            scheduledReminders.append(reminder)

            saveReminders()

            print("💤 Snoozed reminder: \(reminder.title) for \(Int(duration/60)) minutes")
        }
    }

    // MARK: - Reminder Checking

    private func checkReminders() async {
        let now = Date()
        let context = contextSystem.getCurrentContext()

        for reminder in scheduledReminders {
            // Check if reminder should fire
            let shouldFire = await shouldFireReminder(reminder, at: now, context: context)

            if shouldFire {
                await fireReminder(reminder)
            }
        }
    }

    private func shouldFireReminder(_ reminder: SmartReminder, at time: Date, context: UserContext) async -> Bool {
        // Check time condition
        guard time >= reminder.scheduledTime else {
            return false
        }

        // Check context conditions
        if !matchesContextConditions(reminder, context: context) {
            return false
        }

        // Check dismissal patterns (learning)
        if shouldDelayBasedOnPatterns(reminder, context: context) {
            return false
        }

        // Check priority-based scheduling
        if !isPriorityTimeSlot(reminder.priority, context: context) {
            return false
        }

        return true
    }

    private func matchesContextConditions(_ reminder: SmartReminder, context: UserContext) -> Bool {
        guard let conditions = reminder.contextConditions else {
            return true
        }

        for (key, value) in conditions {
            switch key {
            case "timeOfDay":
                if context.timeOfDay.rawValue != value {
                    return false
                }

            case "activity":
                if context.activityType.rawValue != value {
                    return false
                }

            case "location":
                if context.location?.placeName?.contains(value) != true {
                    return false
                }

            case "batteryAbove":
                if let threshold = Float(value) {
                    if context.batteryLevel < threshold {
                        return false
                    }
                }

            case "notDriving":
                if value == "true" && context.activityType == .driving {
                    return false
                }

            default:
                break
            }
        }

        return true
    }

    private func shouldDelayBasedOnPatterns(_ reminder: SmartReminder, context: UserContext) -> Bool {
        let patternKey = reminder.category.rawValue

        guard let pattern = dismissalPatterns[patternKey] else {
            return false
        }

        // If user typically dismisses this type of reminder at this time, delay it
        if pattern.dismissalRate > 0.7 {
            // Check current time matches typical dismissal time
            let calendar = Calendar.current
            let currentHour = calendar.component(.hour, from: Date())

            if pattern.typicalDismissalHours.contains(currentHour) {
                print("⏳ Delaying reminder based on dismissal patterns")
                return true
            }
        }

        return false
    }

    private func isPriorityTimeSlot(_ priority: ReminderPriority, context: UserContext) -> Bool {
        switch priority {
        case .high:
            // High priority can fire anytime
            return true

        case .medium:
            // Medium priority avoids driving and late night
            if context.activityType == .driving {
                return false
            }

            if context.timeOfDay == .night {
                return false
            }

            return true

        case .low:
            // Low priority only during free time
            if context.activityType == .driving || context.activityType == .running {
                return false
            }

            if context.timeOfDay == .night {
                return false
            }

            // Check if in a meeting
            if calendar.isInMeeting() {
                return false
            }

            return true
        }
    }

    // MARK: - Reminder Firing

    private func fireReminder(_ reminder: SmartReminder) async {
        print("🔔 Firing reminder: \(reminder.title)")

        // Move to active reminders
        if let index = scheduledReminders.firstIndex(where: { $0.id == reminder.id }) {
            let activeReminder = scheduledReminders[index]
            activeReminders.append(activeReminder)
            scheduledReminders.remove(at: index)
        }

        // Send notification
        await sendReminderNotification(reminder)

        // Record event
        let event = ReminderEvent(
            id: UUID(),
            reminderId: reminder.id,
            reminderTitle: reminder.title,
            firedAt: Date(),
            context: contextSystem.getCurrentContext()
        )

        reminderHistory.append(event)

        // Keep only last 200 events
        if reminderHistory.count > 200 {
            reminderHistory.removeFirst()
        }

        saveReminders()
    }

    private func sendReminderNotification(_ reminder: SmartReminder) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message
        content.sound = .default
        content.categoryIdentifier = "REMINDER"

        // Add actions
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze 10 min",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [dismissAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Recurring Reminders

    private func rescheduleReminder(_ reminder: SmartReminder) -> SmartReminder? {
        guard let recurrence = reminder.recurrence else {
            return nil
        }

        var nextDate: Date?

        switch recurrence {
        case .daily:
            nextDate = Calendar.current.date(byAdding: .day, value: 1, to: reminder.scheduledTime)

        case .weekly:
            nextDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: reminder.scheduledTime)

        case .monthly:
            nextDate = Calendar.current.date(byAdding: .month, value: 1, to: reminder.scheduledTime)

        case .custom(let interval):
            nextDate = reminder.scheduledTime.addingTimeInterval(interval)
        }

        guard let next = nextDate else {
            return nil
        }

        var newReminder = reminder
        newReminder.id = UUID()
        newReminder.scheduledTime = next

        return newReminder
    }

    // MARK: - Learning from Dismissals

    private func recordDismissal(_ reminder: SmartReminder, reason: DismissalReason) {
        let patternKey = reminder.category.rawValue

        var pattern = dismissalPatterns[patternKey] ?? DismissalPattern(category: reminder.category)

        pattern.totalShown += 1

        if reason == .dismissed || reason == .expired {
            pattern.totalDismissed += 1

            // Record dismissal hour
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            pattern.typicalDismissalHours.insert(hour)
        }

        pattern.dismissalRate = Double(pattern.totalDismissed) / Double(pattern.totalShown)

        dismissalPatterns[patternKey] = pattern
        saveDismissalPatterns()

        print("📊 Updated dismissal pattern for \(reminder.category.rawValue): \(String(format: "%.1f%%", pattern.dismissalRate * 100))")
    }

    // MARK: - Smart Suggestions

    /// Generate smart reminder suggestions based on context and patterns
    public func generateSmartSuggestions() async -> [SmartReminder] {
        var suggestions: [SmartReminder] = []
        let context = contextSystem.getCurrentContext()

        // Suggest based on time of day
        if context.timeOfDay == .morning {
            suggestions.append(SmartReminder(
                id: UUID(),
                title: "Morning Review",
                message: "Review your photos from yesterday",
                scheduledTime: Date().addingTimeInterval(3600),
                priority: .low,
                category: .photo,
                isRecurring: true,
                recurrence: .daily
            ))
        }

        // Suggest based on activity
        if context.activityType == .walking {
            suggestions.append(SmartReminder(
                id: UUID(),
                title: "Capture Moment",
                message: "You're walking. Great time for photos!",
                scheduledTime: Date(),
                priority: .medium,
                category: .photo
            ))
        }

        // Suggest based on calendar
        if let nextEvent = calendar.getNextEvent() {
            let timeUntilEvent = nextEvent.startDate.timeIntervalSinceNow

            if timeUntilEvent > 0 && timeUntilEvent < 7200 { // Within 2 hours
                suggestions.append(SmartReminder(
                    id: UUID(),
                    title: "Prepare for Meeting",
                    message: "\(nextEvent.title) starts in \(Int(timeUntilEvent/60)) minutes",
                    scheduledTime: Date(),
                    priority: .high,
                    category: .calendar
                ))
            }
        }

        // Suggest based on health
        let wellnessSuggestions = health.getWellnessSuggestions()

        for wellness in wellnessSuggestions.prefix(2) {
            suggestions.append(SmartReminder(
                id: UUID(),
                title: wellness.title,
                message: wellness.message,
                scheduledTime: Date(),
                priority: wellness.priority == .high ? .high : .medium,
                category: .health
            ))
        }

        return suggestions
    }

    // MARK: - Templates

    private func createDefaultTemplates() {
        reminderTemplates = [
            ReminderTemplate(
                id: UUID(),
                name: "Daily Photo Review",
                description: "Review photos every evening",
                category: .photo,
                defaultTime: createTime(hour: 20, minute: 0),
                recurrence: .daily,
                priority: .low
            ),
            ReminderTemplate(
                id: UUID(),
                name: "Weekly Backup",
                description: "Backup photos weekly",
                category: .photo,
                defaultTime: createTime(hour: 10, minute: 0),
                recurrence: .weekly,
                priority: .medium
            ),
            ReminderTemplate(
                id: UUID(),
                name: "Morning Exercise",
                description: "Morning workout reminder",
                category: .health,
                defaultTime: createTime(hour: 7, minute: 0),
                recurrence: .daily,
                priority: .medium,
                contextConditions: ["notDriving": "true"]
            ),
            ReminderTemplate(
                id: UUID(),
                name: "Hydration Check",
                description: "Drink water reminder",
                category: .health,
                defaultTime: Date(),
                recurrence: .custom(7200), // Every 2 hours
                priority: .low
            )
        ]

        print("📋 Created \(reminderTemplates.count) reminder templates")
    }

    private func createTime(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    /// Create reminder from template
    public func createFromTemplate(_ templateId: UUID, customTime: Date? = nil) -> SmartReminder? {
        guard let template = reminderTemplates.first(where: { $0.id == templateId }) else {
            return nil
        }

        let reminder = SmartReminder(
            id: UUID(),
            title: template.name,
            message: template.description,
            scheduledTime: customTime ?? template.defaultTime,
            priority: template.priority,
            category: template.category,
            isRecurring: true,
            recurrence: template.recurrence,
            contextConditions: template.contextConditions
        )

        createReminder(reminder)
        return reminder
    }

    // MARK: - Persistence

    private var remindersFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("smart_reminders.json")
    }

    private var patternsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("dismissal_patterns.json")
    }

    private func saveReminders() {
        let data = ReminderData(
            scheduled: scheduledReminders,
            active: activeReminders,
            history: Array(reminderHistory.suffix(200))
        )

        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: remindersFileURL)
        }
    }

    private func loadReminders() {
        if let data = try? Data(contentsOf: remindersFileURL),
           let decoded = try? JSONDecoder().decode(ReminderData.self, from: data) {
            scheduledReminders = decoded.scheduled
            activeReminders = decoded.active
            reminderHistory = decoded.history

            print("📚 Loaded \(scheduledReminders.count) scheduled, \(activeReminders.count) active reminders")
        }
    }

    private func saveDismissalPatterns() {
        if let data = try? JSONEncoder().encode(dismissalPatterns) {
            try? data.write(to: patternsFileURL)
        }
    }

    private func loadDismissalPatterns() {
        if let data = try? Data(contentsOf: patternsFileURL),
           let patterns = try? JSONDecoder().decode([String: DismissalPattern].self, from: data) {
            dismissalPatterns = patterns
            print("🧠 Loaded dismissal patterns for \(dismissalPatterns.count) categories")
        }
    }

    /// Clear all reminders and patterns
    public func clearAllReminders() {
        scheduledReminders.removeAll()
        activeReminders.removeAll()
        reminderHistory.removeAll()
        dismissalPatterns.removeAll()

        saveReminders()
        saveDismissalPatterns()

        print("🗑️ Cleared all reminders")
    }
}

// MARK: - Models

public struct SmartReminder: Codable, Identifiable {
    public var id: UUID
    public let title: String
    public let message: String
    public var scheduledTime: Date
    public let priority: ReminderPriority
    public let category: ReminderCategory
    public let isRecurring: Bool
    public let recurrence: RecurrenceType?
    public let contextConditions: [String: String]?

    public init(id: UUID, title: String, message: String, scheduledTime: Date, priority: ReminderPriority, category: ReminderCategory, isRecurring: Bool = false, recurrence: RecurrenceType? = nil, contextConditions: [String: String]? = nil) {
        self.id = id
        self.title = title
        self.message = message
        self.scheduledTime = scheduledTime
        self.priority = priority
        self.category = category
        self.isRecurring = isRecurring
        self.recurrence = recurrence
        self.contextConditions = contextConditions
    }
}

public enum ReminderPriority: String, Codable {
    case low
    case medium
    case high
}

public enum ReminderCategory: String, Codable {
    case photo
    case health
    case calendar
    case task
    case custom
}

public enum RecurrenceType: Codable {
    case daily
    case weekly
    case monthly
    case custom(TimeInterval)
}

public struct ReminderEvent: Codable {
    public let id: UUID
    public let reminderId: UUID
    public let reminderTitle: String
    public let firedAt: Date
    public let context: UserContext

    public init(id: UUID, reminderId: UUID, reminderTitle: String, firedAt: Date, context: UserContext) {
        self.id = id
        self.reminderId = reminderId
        self.reminderTitle = reminderTitle
        self.firedAt = firedAt
        self.context = context
    }
}

public enum DismissalReason {
    case completed
    case dismissed
    case snoozed
    case expired
}

public struct DismissalPattern: Codable {
    public let category: ReminderCategory
    public var totalShown: Int
    public var totalDismissed: Int
    public var dismissalRate: Double
    public var typicalDismissalHours: Set<Int>

    public init(category: ReminderCategory, totalShown: Int = 0, totalDismissed: Int = 0, dismissalRate: Double = 0.0, typicalDismissalHours: Set<Int> = []) {
        self.category = category
        self.totalShown = totalShown
        self.totalDismissed = totalDismissed
        self.dismissalRate = dismissalRate
        self.typicalDismissalHours = typicalDismissalHours
    }
}

public struct ReminderTemplate: Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: ReminderCategory
    public let defaultTime: Date
    public let recurrence: RecurrenceType
    public let priority: ReminderPriority
    public let contextConditions: [String: String]?

    public init(id: UUID, name: String, description: String, category: ReminderCategory, defaultTime: Date, recurrence: RecurrenceType, priority: ReminderPriority, contextConditions: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.defaultTime = defaultTime
        self.recurrence = recurrence
        self.priority = priority
        self.contextConditions = contextConditions
    }
}

struct ReminderData: Codable {
    let scheduled: [SmartReminder]
    let active: [SmartReminder]
    let history: [ReminderEvent]
}
