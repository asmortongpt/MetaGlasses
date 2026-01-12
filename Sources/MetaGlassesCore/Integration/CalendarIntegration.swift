import Foundation
import EventKit
import CoreLocation

/// Calendar Integration
/// Integrates with iOS Calendar for event-based automation and intelligent reminders
@MainActor
public class CalendarIntegration: ObservableObject {

    // MARK: - Singleton
    public static let shared = CalendarIntegration()

    // MARK: - Published Properties
    @Published public var upcomingEvents: [CalendarEvent] = []
    @Published public var todayEvents: [CalendarEvent] = []
    @Published public var activeEvents: [CalendarEvent] = []
    @Published public var hasCalendarAccess = false

    // MARK: - Properties
    private let eventStore = EKEventStore()
    private var monitoringTimer: Timer?
    private let contextSystem = ContextAwarenessSystem.shared
    private let workflowEngine = WorkflowAutomationEngine.shared

    // Event tracking
    private var lastEventCheck: Date?
    private var notifiedEvents: Set<String> = []

    // MARK: - Initialization
    private init() {
        print("📅 CalendarIntegration initialized")
        requestCalendarAccess()
    }

    // MARK: - Public Methods

    /// Request calendar access
    public func requestCalendarAccess() {
        Task {
            do {
                let granted = try await eventStore.requestAccess(to: .event)
                hasCalendarAccess = granted

                if granted {
                    print("✅ Calendar access granted")
                    await loadEvents()
                    startMonitoring()
                } else {
                    print("⚠️ Calendar access denied")
                }
            } catch {
                print("❌ Calendar access error: \(error.localizedDescription)")
            }
        }
    }

    /// Start monitoring calendar events
    public func startMonitoring() {
        guard hasCalendarAccess else { return }

        // Check for events every minute
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEvents()
                await self?.checkEventReminders()
                await self?.checkActiveEvents()
            }
        }

        print("✅ Calendar monitoring started")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("⏹ Calendar monitoring stopped")
    }

    /// Load calendar events
    public func loadEvents() async {
        guard hasCalendarAccess else { return }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

        // Convert to CalendarEvent
        upcomingEvents = events.map { convertToCalendarEvent($0) }

        // Filter today's events
        let calendar = Calendar.current
        todayEvents = upcomingEvents.filter { event in
            calendar.isDateInToday(event.startDate)
        }

        // Filter active events (happening now)
        activeEvents = upcomingEvents.filter { event in
            now >= event.startDate && now <= event.endDate
        }

        print("📅 Loaded \(upcomingEvents.count) upcoming events")
    }

    /// Get events for specific date
    public func getEvents(for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current

        return upcomingEvents.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }

    /// Get next event
    public func getNextEvent() -> CalendarEvent? {
        let now = Date()

        return upcomingEvents
            .filter { $0.startDate > now }
            .min(by: { $0.startDate < $1.startDate })
    }

    /// Check if currently in a meeting
    public func isInMeeting() -> Bool {
        return !activeEvents.isEmpty
    }

    // MARK: - Event Reminders

    private func checkEventReminders() async {
        let now = Date()

        for event in upcomingEvents {
            // Skip if already notified
            if notifiedEvents.contains(event.id) {
                continue
            }

            // Check various reminder times
            let timeUntilEvent = event.startDate.timeIntervalSince(now)

            if timeUntilEvent <= 0 && timeUntilEvent > -60 {
                // Event just started
                await handleEventStarted(event)
            } else if timeUntilEvent > 0 && timeUntilEvent <= 300 {
                // 5 minutes before
                await sendReminder(event, minutesBefore: 5)
            } else if timeUntilEvent > 0 && timeUntilEvent <= 900 {
                // 15 minutes before
                await sendReminder(event, minutesBefore: 15)
            }
        }
    }

    private func handleEventStarted(_ event: CalendarEvent) async {
        print("▶️ Event started: \(event.title)")

        notifiedEvents.insert(event.id)

        // Auto-capture if enabled
        if event.autoCapture {
            await triggerAutoCapture(for: event)
        }

        // Send notification
        await sendNotification(
            title: "Event Started",
            body: "\(event.title) is now in progress"
        )
    }

    private func sendReminder(_ event: CalendarEvent, minutesBefore: Int) async {
        let key = "\(event.id)_\(minutesBefore)"

        if notifiedEvents.contains(key) {
            return
        }

        notifiedEvents.insert(key)

        // Calculate travel time if location available
        var message = "\(event.title) in \(minutesBefore) minutes"

        if let location = event.location {
            if let travelTime = await calculateTravelTime(to: location) {
                message += "\nTravel time: \(Int(travelTime / 60)) minutes"
            }
        }

        await sendNotification(
            title: "Upcoming Event",
            body: message
        )

        print("⏰ Reminder sent for: \(event.title)")
    }

    // MARK: - Active Event Monitoring

    private func checkActiveEvents() async {
        // Refresh active events
        await loadEvents()

        // Check if we should enable meeting mode
        if !activeEvents.isEmpty {
            let event = activeEvents[0]

            // Suggest meeting capture workflow
            if !notifiedEvents.contains("\(event.id)_meetingCapture") {
                notifiedEvents.insert("\(event.id)_meetingCapture")

                await suggestMeetingCapture(event)
            }
        }
    }

    private func suggestMeetingCapture(_ event: CalendarEvent) async {
        // Create suggestion for auto-capture during meeting
        let message = "Start auto-capture for '\(event.title)'?"

        await sendNotification(
            title: "Meeting Capture",
            body: message
        )
    }

    // MARK: - Travel Time Calculation

    private func calculateTravelTime(to destination: String) async -> TimeInterval? {
        // Get current location
        let currentContext = contextSystem.getCurrentContext()

        guard let currentLocation = currentContext.location?.coordinate else {
            return nil
        }

        // Geocode destination
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.geocodeAddressString(destination)

            guard let destinationLocation = placemarks.first?.location else {
                return nil
            }

            // Calculate distance
            let start = CLLocation(
                latitude: currentLocation.latitude,
                longitude: currentLocation.longitude
            )
            let end = destinationLocation

            let distance = start.distance(from: end)

            // Estimate travel time (simplified: 40 km/h average speed)
            let travelTime = (distance / 1000) / 40 * 3600 // seconds

            return travelTime
        } catch {
            print("❌ Geocoding failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Auto-Capture

    private func triggerAutoCapture(for event: CalendarEvent) async {
        print("📸 Triggering auto-capture for: \(event.title)")

        // Create capture workflow
        let workflow = Workflow(
            id: UUID(),
            name: "Meeting Capture: \(event.title)",
            description: "Auto-capture during meeting",
            steps: [
                WorkflowStep(
                    id: UUID(),
                    name: "Initial capture",
                    type: .action(WorkflowAction(type: .capturePhoto))
                ),
                WorkflowStep(
                    id: UUID(),
                    name: "Periodic capture",
                    type: .loop(
                        LoopType.count(Int(event.duration / 300)), // Every 5 minutes
                        loopSteps: [
                            WorkflowStep(
                                id: UUID(),
                                name: "Wait 5 min",
                                type: .delay(300)
                            ),
                            WorkflowStep(
                                id: UUID(),
                                name: "Capture",
                                type: .action(WorkflowAction(type: .capturePhoto))
                            )
                        ]
                    )
                )
            ]
        )

        // Execute workflow
        await workflowEngine.executeWorkflow(workflow.id)
    }

    // MARK: - Event Creation Helpers

    /// Create event with auto-capture enabled
    public func createCaptureEvent(
        title: String,
        startDate: Date,
        duration: TimeInterval,
        location: String? = nil
    ) async -> Bool {
        guard hasCalendarAccess else { return false }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.location = location

        do {
            try eventStore.save(event, span: .thisEvent)
            await loadEvents()
            print("✅ Created calendar event: \(title)")
            return true
        } catch {
            print("❌ Failed to create event: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Event Analysis

    /// Analyze event patterns
    public func analyzeEventPatterns() -> EventPatternAnalysis {
        var analysis = EventPatternAnalysis()

        // Analyze by time of day
        let calendar = Calendar.current

        for event in upcomingEvents {
            let hour = calendar.component(.hour, from: event.startDate)

            if hour < 12 {
                analysis.morningEventCount += 1
            } else if hour < 17 {
                analysis.afternoonEventCount += 1
            } else {
                analysis.eveningEventCount += 1
            }

            // Analyze by location
            if let location = event.location, !location.isEmpty {
                analysis.locationsFrequency[location, default: 0] += 1
            }

            // Analyze by duration
            if event.duration < 1800 { // < 30 min
                analysis.shortEventCount += 1
            } else if event.duration < 3600 { // < 1 hour
                analysis.mediumEventCount += 1
            } else {
                analysis.longEventCount += 1
            }
        }

        // Find most common meeting location
        analysis.mostCommonLocation = analysis.locationsFrequency
            .max(by: { $0.value < $1.value })?.key

        print("📊 Event analysis complete")
        return analysis
    }

    /// Get free time slots
    public func getFreeTimeSlots(for date: Date, slotDuration: TimeInterval = 3600) -> [TimeSlot] {
        let calendar = Calendar.current
        var freeSlots: [TimeSlot] = []

        // Define work hours (9am - 6pm)
        guard let dayStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date),
              let dayEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) else {
            return []
        }

        let dayEvents = getEvents(for: date).sorted(by: { $0.startDate < $1.startDate })

        var currentTime = dayStart

        for event in dayEvents {
            // Check if there's free time before this event
            if currentTime < event.startDate {
                let freeSlot = TimeSlot(
                    start: currentTime,
                    end: event.startDate,
                    duration: event.startDate.timeIntervalSince(currentTime)
                )

                if freeSlot.duration >= slotDuration {
                    freeSlots.append(freeSlot)
                }
            }

            currentTime = max(currentTime, event.endDate)
        }

        // Check for free time after last event
        if currentTime < dayEnd {
            let freeSlot = TimeSlot(
                start: currentTime,
                end: dayEnd,
                duration: dayEnd.timeIntervalSince(currentTime)
            )

            if freeSlot.duration >= slotDuration {
                freeSlots.append(freeSlot)
            }
        }

        return freeSlots
    }

    // MARK: - Utility Methods

    private func convertToCalendarEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "Untitled",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            duration: ekEvent.endDate.timeIntervalSince(ekEvent.startDate),
            location: ekEvent.location,
            notes: ekEvent.notes,
            isAllDay: ekEvent.isAllDay,
            attendees: ekEvent.attendees?.compactMap { $0.name } ?? [],
            autoCapture: false // Default, can be configured
        )
    }

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Clear notification cache
    public func clearNotifications() {
        notifiedEvents.removeAll()
        print("🗑️ Cleared notification cache")
    }
}

// MARK: - Models

public struct CalendarEvent: Identifiable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let location: String?
    public let notes: String?
    public let isAllDay: Bool
    public let attendees: [String]
    public var autoCapture: Bool

    public init(id: String, title: String, startDate: Date, endDate: Date, duration: TimeInterval, location: String? = nil, notes: String? = nil, isAllDay: Bool = false, attendees: [String] = [], autoCapture: Bool = false) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
        self.attendees = attendees
        self.autoCapture = autoCapture
    }
}

public struct TimeSlot {
    public let start: Date
    public let end: Date
    public let duration: TimeInterval

    public init(start: Date, end: Date, duration: TimeInterval) {
        self.start = start
        self.end = end
        self.duration = duration
    }

    public var formattedDuration: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

public struct EventPatternAnalysis {
    public var morningEventCount = 0
    public var afternoonEventCount = 0
    public var eveningEventCount = 0
    public var shortEventCount = 0
    public var mediumEventCount = 0
    public var longEventCount = 0
    public var locationsFrequency: [String: Int] = [:]
    public var mostCommonLocation: String?

    public init() {}

    public var totalEvents: Int {
        morningEventCount + afternoonEventCount + eveningEventCount
    }

    public var averageEventsPerDay: Double {
        Double(totalEvents) / 7.0 // Assuming 7-day analysis
    }

    public var preferredTimeOfDay: String {
        if morningEventCount > afternoonEventCount && morningEventCount > eveningEventCount {
            return "Morning"
        } else if afternoonEventCount > eveningEventCount {
            return "Afternoon"
        } else {
            return "Evening"
        }
    }
}
