import Foundation
import CoreLocation
import UserNotifications

/// Event Trigger System
/// Automates actions based on time, location, activity, and context triggers
@MainActor
public class EventTriggerSystem: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = EventTriggerSystem()

    // MARK: - Published Properties
    @Published public var activeTriggers: [EventTrigger] = []
    @Published public var triggeredEvents: [TriggeredEvent] = []
    @Published public var isMonitoring = false

    // MARK: - Properties
    private let contextSystem = ContextAwarenessSystem.shared
    private let patternLearning = UserPatternLearningSystem.shared
    private var monitoringTimer: Timer?
    private var geofenceMonitor: CLLocationManager?
    private var activeGeofences: Set<UUID> = []

    // MARK: - Initialization
    override init() {
        super.init()
        loadTriggers()
        print("🎯 EventTriggerSystem initialized")
    }

    // MARK: - Public Methods

    /// Start monitoring all triggers
    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Monitor time-based triggers
        startTimeMonitoring()

        // Monitor location-based triggers
        startLocationMonitoring()

        // Monitor activity-based triggers
        startActivityMonitoring()

        // Monitor context-based triggers
        startContextMonitoring()

        print("✅ Event trigger monitoring started")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil

        print("⏹ Event trigger monitoring stopped")
    }

    /// Add new trigger
    public func addTrigger(_ trigger: EventTrigger) {
        activeTriggers.append(trigger)
        saveTriggers()

        // If location trigger, setup geofence
        if case .location = trigger.type {
            setupGeofence(for: trigger)
        }

        print("➕ Added trigger: \(trigger.name)")
    }

    /// Remove trigger
    public func removeTrigger(_ triggerId: UUID) {
        if let index = activeTriggers.firstIndex(where: { $0.id == triggerId }) {
            let trigger = activeTriggers[index]

            // Remove geofence if location trigger
            if case .location = trigger.type {
                removeGeofence(for: trigger)
            }

            activeTriggers.remove(at: index)
            saveTriggers()

            print("➖ Removed trigger: \(trigger.name)")
        }
    }

    /// Enable/disable trigger
    public func setTriggerEnabled(_ triggerId: UUID, enabled: Bool) {
        if let index = activeTriggers.firstIndex(where: { $0.id == triggerId }) {
            activeTriggers[index].isEnabled = enabled
            saveTriggers()
        }
    }

    // MARK: - Time-Based Triggers

    private func startTimeMonitoring() {
        // Check time-based triggers every minute
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkTimeTriggers()
            }
        }
    }

    private func checkTimeTriggers() async {
        let now = Date()
        let calendar = Calendar.current

        for trigger in activeTriggers where trigger.isEnabled {
            guard case .time(let schedule) = trigger.type else { continue }

            // Check if trigger should fire
            var shouldFire = false

            switch schedule {
            case .daily(let hour, let minute):
                let currentHour = calendar.component(.hour, from: now)
                let currentMinute = calendar.component(.minute, from: now)
                shouldFire = (currentHour == hour && currentMinute == minute)

            case .weekly(let weekday, let hour, let minute):
                let currentWeekday = calendar.component(.weekday, from: now)
                let currentHour = calendar.component(.hour, from: now)
                let currentMinute = calendar.component(.minute, from: now)
                shouldFire = (currentWeekday == weekday && currentHour == hour && currentMinute == minute)

            case .specific(let targetDate):
                let timeDiff = abs(now.timeIntervalSince(targetDate))
                shouldFire = timeDiff < 60 // Within 1 minute

            case .interval(let seconds):
                if let lastFired = trigger.lastTriggered {
                    shouldFire = now.timeIntervalSince(lastFired) >= seconds
                } else {
                    shouldFire = true
                }
            }

            if shouldFire {
                await fireTrigger(trigger)
            }
        }
    }

    // MARK: - Location-Based Triggers

    private func startLocationMonitoring() {
        geofenceMonitor = CLLocationManager()
        geofenceMonitor?.delegate = self
        geofenceMonitor?.requestAlwaysAuthorization()

        // Setup geofences for all location triggers
        for trigger in activeTriggers where trigger.isEnabled {
            if case .location = trigger.type {
                setupGeofence(for: trigger)
            }
        }
    }

    private func setupGeofence(for trigger: EventTrigger) {
        guard case .location(let location) = trigger.type else { return }

        let region = CLCircularRegion(
            center: location.coordinate,
            radius: location.radius,
            identifier: trigger.id.uuidString
        )

        region.notifyOnEntry = (location.event == .enter || location.event == .both)
        region.notifyOnExit = (location.event == .leave || location.event == .both)

        geofenceMonitor?.startMonitoring(for: region)
        activeGeofences.insert(trigger.id)

        print("📍 Geofence setup for: \(trigger.name)")
    }

    private func removeGeofence(for trigger: EventTrigger) {
        if let regions = geofenceMonitor?.monitoredRegions {
            for region in regions where region.identifier == trigger.id.uuidString {
                geofenceMonitor?.stopMonitoring(for: region)
                activeGeofences.remove(trigger.id)
                print("🚫 Geofence removed for: \(trigger.name)")
            }
        }
    }

    // MARK: - Activity-Based Triggers

    private func startActivityMonitoring() {
        // Monitor context changes for activity triggers
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkActivityTriggers()
            }
        }
    }

    private func checkActivityTriggers() async {
        let context = contextSystem.getCurrentContext()

        for trigger in activeTriggers where trigger.isEnabled {
            guard case .activity(let activityType, let event) = trigger.type else { continue }

            // Check if activity matches
            var shouldFire = false

            switch event {
            case .start:
                // Check if activity just started
                if context.activityType == activityType {
                    if let lastFired = trigger.lastTriggered {
                        shouldFire = Date().timeIntervalSince(lastFired) > 300 // 5 min cooldown
                    } else {
                        shouldFire = true
                    }
                }

            case .stop:
                // Check if activity stopped (requires previous state tracking)
                break

            case .continuous:
                // Fire while activity is ongoing
                if context.activityType == activityType {
                    if let lastFired = trigger.lastTriggered {
                        shouldFire = Date().timeIntervalSince(lastFired) > 600 // 10 min interval
                    } else {
                        shouldFire = true
                    }
                }
            }

            if shouldFire {
                await fireTrigger(trigger)
            }
        }
    }

    // MARK: - Context-Based Triggers

    private func startContextMonitoring() {
        // Monitor complex context conditions
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkContextTriggers()
            }
        }
    }

    private func checkContextTriggers() async {
        let context = contextSystem.getCurrentContext()

        for trigger in activeTriggers where trigger.isEnabled {
            guard case .context(let conditions) = trigger.type else { continue }

            // Check if all conditions are met
            var allConditionsMet = true

            for (key, value) in conditions {
                switch key {
                case "timeOfDay":
                    if context.timeOfDay.rawValue != value {
                        allConditionsMet = false
                    }

                case "activity":
                    if context.activityType.rawValue != value {
                        allConditionsMet = false
                    }

                case "batteryBelow":
                    if let threshold = Float(value) {
                        if context.batteryLevel > threshold {
                            allConditionsMet = false
                        }
                    }

                case "isWeekend":
                    if let expectedWeekend = Bool(value) {
                        if context.isWeekend != expectedWeekend {
                            allConditionsMet = false
                        }
                    }

                default:
                    break
                }
            }

            if allConditionsMet {
                if let lastFired = trigger.lastTriggered {
                    // Cooldown: only fire once per hour
                    if Date().timeIntervalSince(lastFired) > 3600 {
                        await fireTrigger(trigger)
                    }
                } else {
                    await fireTrigger(trigger)
                }
            }
        }
    }

    // MARK: - Trigger Execution

    private func fireTrigger(_ trigger: EventTrigger) async {
        print("🔥 Firing trigger: \(trigger.name)")

        // Update last triggered time
        if let index = activeTriggers.firstIndex(where: { $0.id == trigger.id }) {
            activeTriggers[index].lastTriggered = Date()
            activeTriggers[index].timesTriggered += 1
            saveTriggers()
        }

        // Execute actions
        for action in trigger.actions {
            await executeAction(action, triggerName: trigger.name)
        }

        // Record triggered event
        let event = TriggeredEvent(
            id: UUID(),
            triggerId: trigger.id,
            triggerName: trigger.name,
            timestamp: Date(),
            actionsExecuted: trigger.actions.count
        )

        triggeredEvents.append(event)

        // Keep only last 100 events
        if triggeredEvents.count > 100 {
            triggeredEvents.removeFirst()
        }

        // Send notification if enabled
        if trigger.notifyUser {
            await sendNotification(trigger)
        }
    }

    private func executeAction(_ action: TriggerAction, triggerName: String) async {
        print("⚡️ Executing action: \(action.type.rawValue)")

        switch action.type {
        case .capturePhoto:
            // Trigger photo capture
            // In real implementation, would integrate with camera system
            print("📸 Auto-capturing photo")

        case .startRecording:
            print("🎥 Auto-starting video recording")

        case .sendNotification:
            if let message = action.parameters["message"] {
                await sendCustomNotification(message)
            }

        case .executeWorkflow:
            if let workflowId = action.parameters["workflowId"],
               let uuid = UUID(uuidString: workflowId) {
                // Execute workflow (will integrate with WorkflowAutomationEngine)
                print("🔄 Executing workflow: \(uuid)")
            }

        case .logEvent:
            if let event = action.parameters["event"] {
                print("📝 Logging event: \(event)")
            }

        case .custom:
            print("🔧 Executing custom action")
        }
    }

    private func sendNotification(_ trigger: EventTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = "MetaGlasses"
        content.body = "Trigger '\(trigger.name)' activated"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: trigger.id.uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func sendCustomNotification(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "MetaGlasses"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private var triggersFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("event_triggers.json")
    }

    private func saveTriggers() {
        if let data = try? JSONEncoder().encode(activeTriggers) {
            try? data.write(to: triggersFileURL)
        }
    }

    private func loadTriggers() {
        if let data = try? Data(contentsOf: triggersFileURL),
           let triggers = try? JSONDecoder().decode([EventTrigger].self, from: data) {
            activeTriggers = triggers
            print("📚 Loaded \(activeTriggers.count) triggers")
        }
    }

    /// Clear all triggers
    public func clearAllTriggers() {
        // Remove all geofences
        for trigger in activeTriggers {
            if case .location = trigger.type {
                removeGeofence(for: trigger)
            }
        }

        activeTriggers.removeAll()
        triggeredEvents.removeAll()
        saveTriggers()

        print("🗑️ Cleared all triggers")
    }
}

// MARK: - CLLocationManagerDelegate
extension EventTriggerSystem: CLLocationManagerDelegate {

    nonisolated public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            if let triggerId = UUID(uuidString: region.identifier),
               let trigger = activeTriggers.first(where: { $0.id == triggerId }) {
                print("📍 Entered region: \(trigger.name)")
                await fireTrigger(trigger)
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            if let triggerId = UUID(uuidString: region.identifier),
               let trigger = activeTriggers.first(where: { $0.id == triggerId }) {
                print("📍 Exited region: \(trigger.name)")
                await fireTrigger(trigger)
            }
        }
    }
}

// MARK: - Models

public struct EventTrigger: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let type: TriggerType
    public var actions: [TriggerAction]
    public var isEnabled: Bool
    public var notifyUser: Bool
    public var lastTriggered: Date?
    public var timesTriggered: Int
    public let createdAt: Date

    public init(id: UUID, name: String, description: String, type: TriggerType, actions: [TriggerAction], isEnabled: Bool = true, notifyUser: Bool = false, lastTriggered: Date? = nil, timesTriggered: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.actions = actions
        self.isEnabled = isEnabled
        self.notifyUser = notifyUser
        self.lastTriggered = lastTriggered
        self.timesTriggered = timesTriggered
        self.createdAt = createdAt
    }
}

public enum TriggerType: Codable {
    case time(TimeSchedule)
    case location(LocationTrigger)
    case activity(ActivityType, ActivityEvent)
    case context([String: String])
}

public enum TimeSchedule: Codable {
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case specific(date: Date)
    case interval(seconds: TimeInterval)
}

public struct LocationTrigger: Codable {
    public let coordinate: CLLocationCoordinate2D
    public let radius: CLLocationDistance
    public let event: LocationEvent

    public init(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance, event: LocationEvent) {
        self.coordinate = coordinate
        self.radius = radius
        self.event = event
    }
}

public enum LocationEvent: String, Codable {
    case enter
    case leave
    case both
}

public enum ActivityEvent: String, Codable {
    case start
    case stop
    case continuous
}

public struct TriggerAction: Codable {
    public let type: ActionType
    public let parameters: [String: String]

    public init(type: ActionType, parameters: [String: String] = [:]) {
        self.type = type
        self.parameters = parameters
    }

    public enum ActionType: String, Codable {
        case capturePhoto
        case startRecording
        case sendNotification
        case executeWorkflow
        case logEvent
        case custom
    }
}

public struct TriggeredEvent: Codable, Identifiable {
    public let id: UUID
    public let triggerId: UUID
    public let triggerName: String
    public let timestamp: Date
    public let actionsExecuted: Int

    public init(id: UUID, triggerId: UUID, triggerName: String, timestamp: Date, actionsExecuted: Int) {
        self.id = id
        self.triggerId = triggerId
        self.triggerName = triggerName
        self.timestamp = timestamp
        self.actionsExecuted = actionsExecuted
    }
}
