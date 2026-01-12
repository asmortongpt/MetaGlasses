import Foundation
import UIKit

/// Analytics & Monitoring System
/// Privacy-first analytics, error tracking, and performance metrics
@MainActor
public class AnalyticsMonitoring: ObservableObject {

    // MARK: - Singleton
    public static let shared = AnalyticsMonitoring()

    // MARK: - Published Properties
    @Published public var totalEvents: Int = 0
    @Published public var totalErrors: Int = 0
    @Published public var sessionDuration: TimeInterval = 0
    @Published public var performanceMetrics: PerformanceMetricsSummary

    // MARK: - Properties
    private var events: [AnalyticsEvent] = []
    private var errors: [ErrorEvent] = []
    private var sessionStart: Date
    private var metrics: [String: Double] = [:]

    private let maxEventsInMemory = 1000
    private let maxErrorsInMemory = 100

    // Privacy settings
    private let collectsPersonalData = false // Never collect PII
    private let anonymizesData = true

    // MARK: - Initialization
    private init() {
        self.sessionStart = Date()
        self.performanceMetrics = PerformanceMetricsSummary()

        print("📊 AnalyticsMonitoring initialized (Privacy-First Mode)")

        setupCrashReporting()
        startSessionTracking()
    }

    // MARK: - Event Tracking

    /// Track analytics event (privacy-preserving)
    public func trackEvent(
        category: EventCategory,
        action: String,
        label: String? = nil,
        value: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        // Anonymize any potential PII in metadata
        let sanitizedMetadata = anonymizesData ? anonymizeMetadata(metadata) : metadata

        let event = AnalyticsEvent(
            id: UUID(),
            timestamp: Date(),
            category: category,
            action: action,
            label: label,
            value: value,
            metadata: sanitizedMetadata,
            sessionId: getAnonymousSessionId()
        )

        events.append(event)
        totalEvents += 1

        // Trim old events
        if events.count > maxEventsInMemory {
            events.removeFirst(events.count - maxEventsInMemory)
        }

        // Persist event
        persistEvent(event)

        print("📊 Event: \(category.rawValue).\(action)")
    }

    /// Track screen view
    public func trackScreenView(screenName: String) {
        trackEvent(
            category: .navigation,
            action: "screen_view",
            label: screenName
        )
    }

    /// Track user action
    public func trackUserAction(action: String, context: String? = nil) {
        trackEvent(
            category: .interaction,
            action: action,
            label: context
        )
    }

    /// Track feature usage
    public func trackFeatureUse(feature: String, duration: TimeInterval? = nil) {
        trackEvent(
            category: .feature,
            action: "use_\(feature)",
            value: duration
        )
    }

    // MARK: - Error Tracking

    /// Track error
    public func trackError(
        error: Error,
        context: String,
        severity: ErrorSeverity = .medium,
        additionalInfo: [String: String] = [:]
    ) {
        let errorEvent = ErrorEvent(
            id: UUID(),
            timestamp: Date(),
            error: error,
            context: context,
            severity: severity,
            stackTrace: Thread.callStackSymbols,
            deviceInfo: getDeviceInfo(),
            additionalInfo: anonymizeMetadata(additionalInfo),
            sessionId: getAnonymousSessionId()
        )

        errors.append(errorEvent)
        totalErrors += 1

        // Trim old errors
        if errors.count > maxErrorsInMemory {
            errors.removeFirst(errors.count - maxErrorsInMemory)
        }

        // Persist error
        persistError(errorEvent)

        print("❌ Error: [\(severity.rawValue)] \(error.localizedDescription) in \(context)")

        // Log critical errors immediately
        if severity == .critical {
            reportCriticalError(errorEvent)
        }
    }

    /// Track non-fatal error
    public func trackNonFatal(message: String, context: String) {
        let error = NSError(
            domain: "com.metaglasses.nonfatal",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        )

        trackError(error: error, context: context, severity: .low)
    }

    // MARK: - Performance Metrics

    /// Record performance metric
    public func recordMetric(name: String, value: Double, unit: MetricUnit = .milliseconds) {
        metrics[name] = value

        trackEvent(
            category: .performance,
            action: "metric_\(name)",
            value: value,
            metadata: ["unit": unit.rawValue]
        )

        updatePerformanceMetrics(name: name, value: value)

        print("⚡️ Metric: \(name) = \(value) \(unit.rawValue)")
    }

    /// Measure execution time
    public func measureExecutionTime<T>(
        operationName: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()

        let result = try await operation()

        let duration = Date().timeIntervalSince(startTime) * 1000 // milliseconds
        recordMetric(name: operationName, value: duration)

        return result
    }

    /// Track API call performance
    public func trackAPICall(
        endpoint: String,
        method: String,
        duration: TimeInterval,
        statusCode: Int,
        success: Bool
    ) {
        recordMetric(name: "api_\(endpoint)", value: duration * 1000)

        trackEvent(
            category: .network,
            action: "api_call",
            label: "\(method) \(endpoint)",
            value: duration,
            metadata: [
                "status_code": "\(statusCode)",
                "success": "\(success)"
            ]
        )
    }

    // MARK: - Session Tracking

    private func startSessionTracking() {
        // Update session duration every minute
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSessionDuration()
            }
        }
    }

    private func updateSessionDuration() {
        sessionDuration = Date().timeIntervalSince(sessionStart)
    }

    /// End current session
    public func endSession() {
        updateSessionDuration()

        trackEvent(
            category: .session,
            action: "session_end",
            value: sessionDuration,
            metadata: [
                "events_count": "\(totalEvents)",
                "errors_count": "\(totalErrors)"
            ]
        )

        // Generate session report
        let report = generateSessionReport()
        persistSessionReport(report)

        print("📊 Session ended: \(Int(sessionDuration))s, \(totalEvents) events, \(totalErrors) errors")
    }

    // MARK: - Usage Analytics (Privacy-Preserving)

    /// Get usage statistics
    public func getUsageStats() -> UsageStatistics {
        let eventsByCategory = Dictionary(grouping: events) { $0.category }
            .mapValues { $0.count }

        let errorsBySeverity = Dictionary(grouping: errors) { $0.severity }
            .mapValues { $0.count }

        let mostUsedFeatures = getMostUsedFeatures()

        return UsageStatistics(
            totalEvents: totalEvents,
            totalErrors: totalErrors,
            sessionDuration: sessionDuration,
            eventsByCategory: eventsByCategory,
            errorsBySeverity: errorsBySeverity,
            mostUsedFeatures: mostUsedFeatures,
            averageSessionDuration: getAverageSessionDuration(),
            dailyActiveUsers: 1 // Single user device
        )
    }

    private func getMostUsedFeatures() -> [(feature: String, count: Int)] {
        let featureEvents = events.filter { $0.category == .feature }

        let featureCounts = Dictionary(grouping: featureEvents) { $0.action }
            .mapValues { $0.count }

        return featureCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (feature: $0.key, count: $0.value) }
    }

    private func getAverageSessionDuration() -> TimeInterval {
        // Would calculate from historical sessions
        return sessionDuration
    }

    // MARK: - Crash Reporting

    private func setupCrashReporting() {
        NSSetUncaughtExceptionHandler { exception in
            Task { @MainActor in
                let error = NSError(
                    domain: "com.metaglasses.crash",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: exception.reason ?? "Unknown crash",
                        "callStackSymbols": exception.callStackSymbols
                    ]
                )

                AnalyticsMonitoring.shared.trackError(
                    error: error,
                    context: "uncaught_exception",
                    severity: .critical,
                    additionalInfo: ["name": exception.name.rawValue]
                )
            }
        }
    }

    private func reportCriticalError(_ errorEvent: ErrorEvent) {
        // In production, would send to error reporting service
        // For now, just log locally
        print("🚨 CRITICAL ERROR: \(errorEvent.error.localizedDescription)")
    }

    // MARK: - Privacy & Anonymization

    private func anonymizeMetadata(_ metadata: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]

        for (key, value) in metadata {
            // Remove any potential PII
            let lowerKey = key.lowercased()

            if lowerKey.contains("email") ||
               lowerKey.contains("name") ||
               lowerKey.contains("phone") ||
               lowerKey.contains("address") {
                // Skip PII fields
                continue
            }

            sanitized[key] = value
        }

        return sanitized
    }

    private func getAnonymousSessionId() -> String {
        // Generate consistent but anonymous session ID
        return UUID().uuidString
    }

    private func getDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current

        return DeviceInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            identifierForVendor: device.identifierForVendor?.uuidString ?? "unknown",
            screenSize: UIScreen.main.bounds.size,
            locale: Locale.current.identifier
        )
    }

    // MARK: - Performance Metrics Updates

    private func updatePerformanceMetrics(name: String, value: Double) {
        if name.contains("api") || name.contains("network") {
            performanceMetrics.averageAPIResponseTime =
                (performanceMetrics.averageAPIResponseTime + value) / 2.0
        }

        if name.contains("pattern") || name.contains("analysis") {
            performanceMetrics.averagePatternDetectionTime =
                (performanceMetrics.averagePatternDetectionTime + value) / 2.0
        }

        if name.contains("graph") || name.contains("query") {
            performanceMetrics.averageGraphQueryTime =
                (performanceMetrics.averageGraphQueryTime + value) / 2.0
        }

        if name.contains("embedding") {
            performanceMetrics.averageEmbeddingGenerationTime =
                (performanceMetrics.averageEmbeddingGenerationTime + value) / 2.0
        }
    }

    // MARK: - Persistence

    private var eventsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("analytics_events.json")
    }

    private var errorsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("error_events.json")
    }

    private func persistEvent(_ event: AnalyticsEvent) {
        // Append to file (in production, would batch writes)
        if let data = try? JSONEncoder().encode(event) {
            // Save to file
            if var existingData = try? Data(contentsOf: eventsFileURL) {
                existingData.append(data)
                try? existingData.write(to: eventsFileURL)
            } else {
                try? data.write(to: eventsFileURL)
            }
        }
    }

    private func persistError(_ error: ErrorEvent) {
        if let data = try? JSONEncoder().encode(error) {
            if var existingData = try? Data(contentsOf: errorsFileURL) {
                existingData.append(data)
                try? existingData.write(to: errorsFileURL)
            } else {
                try? data.write(to: errorsFileURL)
            }
        }
    }

    private func persistSessionReport(_ report: SessionReport) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "session_\(Int(Date().timeIntervalSince1970)).json"
        let fileURL = documentsPath.appendingPathComponent(filename)

        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - Reporting

    private func generateSessionReport() -> SessionReport {
        return SessionReport(
            sessionId: getAnonymousSessionId(),
            startTime: sessionStart,
            endTime: Date(),
            duration: sessionDuration,
            totalEvents: totalEvents,
            totalErrors: totalErrors,
            usageStats: getUsageStats(),
            performanceMetrics: performanceMetrics,
            deviceInfo: getDeviceInfo()
        )
    }

    /// Export analytics data
    public func exportAnalyticsData() -> AnalyticsExport {
        return AnalyticsExport(
            exportDate: Date(),
            sessionReport: generateSessionReport(),
            recentEvents: Array(events.suffix(100)),
            recentErrors: Array(errors.suffix(50)),
            metrics: metrics
        )
    }
}

// MARK: - Models

public enum EventCategory: String, Codable {
    case navigation
    case interaction
    case feature
    case performance
    case network
    case session
    case error
}

public struct AnalyticsEvent: Codable {
    let id: UUID
    let timestamp: Date
    let category: EventCategory
    let action: String
    let label: String?
    let value: Double?
    let metadata: [String: String]
    let sessionId: String
}

public enum ErrorSeverity: String, Codable {
    case low
    case medium
    case high
    case critical
}

public struct ErrorEvent: Codable {
    let id: UUID
    let timestamp: Date
    let error: CodableError
    let context: String
    let severity: ErrorSeverity
    let stackTrace: [String]
    let deviceInfo: DeviceInfo
    let additionalInfo: [String: String]
    let sessionId: String

    init(id: UUID, timestamp: Date, error: Error, context: String, severity: ErrorSeverity, stackTrace: [String], deviceInfo: DeviceInfo, additionalInfo: [String: String], sessionId: String) {
        self.id = id
        self.timestamp = timestamp
        self.error = CodableError(error: error)
        self.context = context
        self.severity = severity
        self.stackTrace = stackTrace
        self.deviceInfo = deviceInfo
        self.additionalInfo = additionalInfo
        self.sessionId = sessionId
    }
}

public struct CodableError: Codable {
    let domain: String
    let code: Int
    let localizedDescription: String

    init(error: Error) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.localizedDescription = error.localizedDescription
    }
}

public struct DeviceInfo: Codable {
    let model: String
    let systemName: String
    let systemVersion: String
    let identifierForVendor: String
    let screenSize: CGSize
    let locale: String
}

public enum MetricUnit: String {
    case milliseconds
    case seconds
    case bytes
    case megabytes
    case count
    case percentage
}

public struct PerformanceMetricsSummary {
    public var averageAPIResponseTime: Double = 0
    public var averagePatternDetectionTime: Double = 0
    public var averageGraphQueryTime: Double = 0
    public var averageEmbeddingGenerationTime: Double = 0

    public init() {}
}

public struct UsageStatistics {
    public let totalEvents: Int
    public let totalErrors: Int
    public let sessionDuration: TimeInterval
    public let eventsByCategory: [EventCategory: Int]
    public let errorsBySeverity: [ErrorSeverity: Int]
    public let mostUsedFeatures: [(feature: String, count: Int)]
    public let averageSessionDuration: TimeInterval
    public let dailyActiveUsers: Int
}

public struct SessionReport: Codable {
    let sessionId: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let totalEvents: Int
    let totalErrors: Int
    let usageStats: CodableUsageStatistics
    let performanceMetrics: CodablePerformanceMetrics
    let deviceInfo: DeviceInfo

    init(sessionId: String, startTime: Date, endTime: Date, duration: TimeInterval, totalEvents: Int, totalErrors: Int, usageStats: UsageStatistics, performanceMetrics: PerformanceMetricsSummary, deviceInfo: DeviceInfo) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.totalEvents = totalEvents
        self.totalErrors = totalErrors
        self.usageStats = CodableUsageStatistics(stats: usageStats)
        self.performanceMetrics = CodablePerformanceMetrics(metrics: performanceMetrics)
        self.deviceInfo = deviceInfo
    }
}

public struct CodableUsageStatistics: Codable {
    let totalEvents: Int
    let totalErrors: Int
    let sessionDuration: TimeInterval
    let averageSessionDuration: TimeInterval
    let dailyActiveUsers: Int

    init(stats: UsageStatistics) {
        self.totalEvents = stats.totalEvents
        self.totalErrors = stats.totalErrors
        self.sessionDuration = stats.sessionDuration
        self.averageSessionDuration = stats.averageSessionDuration
        self.dailyActiveUsers = stats.dailyActiveUsers
    }
}

public struct CodablePerformanceMetrics: Codable {
    let averageAPIResponseTime: Double
    let averagePatternDetectionTime: Double
    let averageGraphQueryTime: Double
    let averageEmbeddingGenerationTime: Double

    init(metrics: PerformanceMetricsSummary) {
        self.averageAPIResponseTime = metrics.averageAPIResponseTime
        self.averagePatternDetectionTime = metrics.averagePatternDetectionTime
        self.averageGraphQueryTime = metrics.averageGraphQueryTime
        self.averageEmbeddingGenerationTime = metrics.averageEmbeddingGenerationTime
    }
}

public struct AnalyticsExport: Codable {
    let exportDate: Date
    let sessionReport: SessionReport
    let recentEvents: [AnalyticsEvent]
    let recentErrors: [ErrorEvent]
    let metrics: [String: Double]
}
