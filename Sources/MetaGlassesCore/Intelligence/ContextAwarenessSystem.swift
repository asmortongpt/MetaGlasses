import Foundation
import CoreLocation
import CoreMotion
import UIKit

/// Context Awareness System
/// Tracks and analyzes user context: location, time, activity, environment
@MainActor
public class ContextAwarenessSystem: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = ContextAwarenessSystem()

    // MARK: - Published Properties
    @Published public var currentContext: UserContext
    @Published public var isTrackingLocation = false
    @Published public var isTrackingActivity = false

    // MARK: - Properties
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let activityQueue = OperationQueue()
    private var lastKnownLocation: CLLocation?
    private var currentActivity: CMMotionActivity?
    private var contextHistory: [UserContext] = []

    // Context learning
    private var locationPatterns: [String: LocationPattern] = [:]
    private var timePatterns: [String: TimePattern] = [:]

    // MARK: - Initialization
    override init() {
        self.currentContext = UserContext()
        super.init()

        // Setup location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 50 // Update every 50 meters

        print("🧭 ContextAwarenessSystem initialized")
    }

    // MARK: - Public Methods

    /// Start tracking all context
    public func startTracking() {
        requestPermissions()
        startLocationTracking()
        startActivityTracking()
        startTimeTracking()

        print("✅ Context tracking started")
    }

    /// Stop tracking
    public func stopTracking() {
        stopLocationTracking()
        stopActivityTracking()

        print("⏹ Context tracking stopped")
    }

    /// Get current context
    public func getCurrentContext() -> UserContext {
        updateContext()
        return currentContext
    }

    // MARK: - Location Tracking

    private func startLocationTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        isTrackingLocation = true
    }

    private func stopLocationTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        isTrackingLocation = false
    }

    private func requestPermissions() {
        // Location
        locationManager.requestWhenInUseAuthorization()

        // Motion
        if CMMotionActivityManager.isActivityAvailable() {
            // Will request on first use
        }
    }

    // MARK: - Activity Tracking

    private func startActivityTracking() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ Motion activity not available on this device")
            return
        }

        motionManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
            guard let self = self, let activity = activity else { return }

            Task { @MainActor in
                self.currentActivity = activity
                self.updateActivityContext(activity)
            }
        }

        isTrackingActivity = true
    }

    private func stopActivityTracking() {
        motionManager.stopActivityUpdates()
        isTrackingActivity = false
    }

    // MARK: - Time Tracking

    private func startTimeTracking() {
        // Update time context every minute
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimeContext()
            }
        }

        updateTimeContext()
    }

    // MARK: - Context Updates

    private func updateContext() {
        currentContext.timestamp = Date()

        // Location context
        if let location = lastKnownLocation {
            currentContext.location = LocationContext(
                coordinate: location.coordinate,
                altitude: location.altitude,
                accuracy: location.horizontalAccuracy,
                placeName: nil // Will be geocoded
            )

            // Geocode location
            Task {
                await geocodeLocation(location)
            }
        }

        // Time context
        updateTimeContext()

        // Activity context
        if let activity = currentActivity {
            updateActivityContext(activity)
        }

        // Environment context
        updateEnvironmentContext()

        // Learn patterns
        learnContextPatterns()

        // Save to history
        contextHistory.append(currentContext)
        if contextHistory.count > 1000 {
            contextHistory.removeFirst()
        }
    }

    private func updateTimeContext() {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // Determine time of day
        currentContext.timeOfDay = TimeOfDay.from(hour: hour)

        // Determine day of week
        let weekday = calendar.component(.weekday, from: now)
        currentContext.isWeekend = (weekday == 1 || weekday == 7) // Sunday or Saturday

        // Work hours detection (9am - 5pm weekdays)
        currentContext.isWorkHours = !currentContext.isWeekend && hour >= 9 && hour < 17
    }

    private func updateActivityContext(_ activity: CMMotionActivity) {
        if activity.stationary {
            currentContext.activityType = .stationary
        } else if activity.walking {
            currentContext.activityType = .walking
        } else if activity.running {
            currentContext.activityType = .running
        } else if activity.cycling {
            currentContext.activityType = .cycling
        } else if activity.automotive {
            currentContext.activityType = .driving
        } else {
            currentContext.activityType = .unknown
        }

        currentContext.activityConfidence = ActivityConfidence.from(confidence: activity.confidence)
    }

    private func updateEnvironmentContext() {
        // Battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        currentContext.batteryLevel = UIDevice.current.batteryLevel

        // Network connectivity (simplified)
        currentContext.isOnline = true // Would check actual network status

        // Screen state
        currentContext.isScreenOn = UIApplication.shared.applicationState == .active
    }

    private func geocodeLocation(_ location: CLLocation) async {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)

            if let placemark = placemarks.first {
                var components: [String] = []

                if let name = placemark.name { components.append(name) }
                if let locality = placemark.locality { components.append(locality) }
                if let adminArea = placemark.administrativeArea { components.append(adminArea) }

                let placeName = components.joined(separator: ", ")

                currentContext.location?.placeName = placeName
                currentContext.location?.country = placemark.country
                currentContext.location?.city = placemark.locality

                print("📍 Location: \(placeName)")
            }
        } catch {
            print("❌ Geocoding failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pattern Learning

    private func learnContextPatterns() {
        // Learn location patterns
        if let location = currentContext.location, let placeName = location.placeName {
            let key = placeName

            if var pattern = locationPatterns[key] {
                pattern.visitCount += 1
                pattern.lastVisit = Date()
                pattern.typicalActivities.append(currentContext.activityType.rawValue)
                locationPatterns[key] = pattern
            } else {
                locationPatterns[key] = LocationPattern(
                    placeName: placeName,
                    coordinate: location.coordinate,
                    visitCount: 1,
                    firstVisit: Date(),
                    lastVisit: Date(),
                    typicalActivities: [currentContext.activityType.rawValue]
                )
            }
        }

        // Learn time patterns
        let hourKey = "\(currentContext.timeOfDay.rawValue)"

        if var pattern = timePatterns[hourKey] {
            pattern.occurrenceCount += 1
            pattern.typicalLocations.append(currentContext.location?.placeName ?? "unknown")
            pattern.typicalActivities.append(currentContext.activityType.rawValue)
            timePatterns[hourKey] = pattern
        } else {
            timePatterns[hourKey] = TimePattern(
                timeOfDay: currentContext.timeOfDay,
                occurrenceCount: 1,
                typicalLocations: [currentContext.location?.placeName ?? "unknown"],
                typicalActivities: [currentContext.activityType.rawValue]
            )
        }
    }

    // MARK: - Context Queries

    /// Get context at specific time
    public func getContextAt(date: Date) -> UserContext? {
        return contextHistory.first { context in
            guard let timestamp = context.timestamp else { return false }
            return abs(timestamp.timeIntervalSince(date)) < 300 // Within 5 minutes
        }
    }

    /// Get typical activity for location
    public func getTypicalActivity(for placeName: String) -> [String] {
        return locationPatterns[placeName]?.typicalActivities ?? []
    }

    /// Get typical locations for time of day
    public func getTypicalLocations(for timeOfDay: TimeOfDay) -> [String] {
        return timePatterns[timeOfDay.rawValue]?.typicalLocations ?? []
    }

    /// Predict next location based on patterns
    public func predictNextLocation() -> String? {
        let currentTime = currentContext.timeOfDay
        let typicalLocations = getTypicalLocations(for: currentTime)

        // Return most common location for this time
        let locationCounts = Dictionary(grouping: typicalLocations) { $0 }
            .mapValues { $0.count }

        return locationCounts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - CLLocationManagerDelegate
extension ContextAwarenessSystem: CLLocationManagerDelegate {

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.lastKnownLocation = location
            self.updateContext()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startLocationTracking()
            case .denied, .restricted:
                print("⚠️ Location access denied")
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Models

public struct UserContext: Codable {
    public var timestamp: Date?
    public var location: LocationContext?
    public var timeOfDay: TimeOfDay = .unknown
    public var isWeekend: Bool = false
    public var isWorkHours: Bool = false
    public var activityType: ActivityType = .unknown
    public var activityConfidence: ActivityConfidence = .low
    public var batteryLevel: Float = 1.0
    public var isOnline: Bool = true
    public var isScreenOn: Bool = true
    public var weather: WeatherConditions?

    public init() {}
}

public struct LocationContext: Codable {
    public var coordinate: CLLocationCoordinate2D
    public var altitude: Double
    public var accuracy: Double
    public var placeName: String?
    public var city: String?
    public var country: String?

    public init(coordinate: CLLocationCoordinate2D, altitude: Double, accuracy: Double, placeName: String?) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.accuracy = accuracy
        self.placeName = placeName
    }
}

public enum TimeOfDay: String, Codable {
    case earlyMorning = "early_morning"   // 5am-8am
    case morning = "morning"               // 8am-12pm
    case afternoon = "afternoon"           // 12pm-5pm
    case evening = "evening"               // 5pm-9pm
    case night = "night"                   // 9pm-5am
    case unknown = "unknown"

    static func from(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        case 21...23, 0..<5: return .night
        default: return .unknown
        }
    }
}

public enum ActivityType: String, Codable {
    case stationary
    case walking
    case running
    case cycling
    case driving
    case unknown
}

public enum ActivityConfidence: String, Codable {
    case low
    case medium
    case high

    static func from(confidence: CMMotionActivityConfidence) -> ActivityConfidence {
        switch confidence {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .low
        }
    }
}

struct LocationPattern {
    var placeName: String
    var coordinate: CLLocationCoordinate2D
    var visitCount: Int
    var firstVisit: Date
    var lastVisit: Date
    var typicalActivities: [String]
}

struct TimePattern {
    var timeOfDay: TimeOfDay
    var occurrenceCount: Int
    var typicalLocations: [String]
    var typicalActivities: [String]
}

// Extension to make CLLocationCoordinate2D Codable
extension CLLocationCoordinate2D: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}
