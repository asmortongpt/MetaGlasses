import Foundation
import CoreLocation
import WeatherKit

/// Real Weather Service using Apple WeatherKit
/// Provides current weather, forecasts, and weather-based suggestions
@MainActor
public class WeatherService: ObservableObject {

    // MARK: - Singleton
    public static let shared = WeatherService()

    // MARK: - Properties
    @Published public var currentWeather: Weather?
    @Published public var suggestions: [String] = []
    private let weatherService = WeatherKit.WeatherService()
    private let locationManager = CLLocationManager()

    // MARK: - Initialization
    private init() {
        print("🌤️ WeatherService initialized - Using Apple WeatherKit")
    }

    // MARK: - Public Methods

    /// Get current weather for location
    public func getCurrentWeather(latitude: Double, longitude: Double) async throws -> Weather {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let weather = try await weatherService.weather(for: location)
            self.currentWeather = weather
            updateSuggestions(for: weather)
            return weather
        } catch {
            print("❌ Weather fetch failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get weather for current device location
    public func getWeatherForCurrentLocation() async throws -> Weather {
        guard let location = locationManager.location else {
            throw WeatherError.locationUnavailable
        }

        return try await getCurrentWeather(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    /// Get hourly forecast
    public func getHourlyForecast(latitude: Double, longitude: Double, hours: Int = 24) async throws -> [HourWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await weatherService.weather(for: location)

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(hours * 3600))

        return Array(forecast.hourlyForecast.filter { hourly in
            hourly.date >= startDate && hourly.date <= endDate
        })
    }

    /// Get daily forecast
    public func getDailyForecast(latitude: Double, longitude: Double, days: Int = 7) async throws -> [DayWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await weatherService.weather(for: location)

        return Array(forecast.dailyForecast.prefix(days))
    }

    // MARK: - Suggestions

    private func updateSuggestions(for weather: Weather) {
        var newSuggestions: [String] = []

        let current = weather.currentWeather
        let temp = current.temperature.value

        // Temperature-based suggestions
        if temp > 30 {
            newSuggestions.append("☀️ It's hot! Stay hydrated and wear sunglasses")
        } else if temp > 20 {
            newSuggestions.append("🌤️ Great weather for outdoor activities")
        } else if temp > 10 {
            newSuggestions.append("🧥 Light jacket recommended")
        } else if temp > 0 {
            newSuggestions.append("🥶 Cold weather - dress warmly")
        } else {
            newSuggestions.append("❄️ Freezing conditions - bundle up!")
        }

        // Condition-based suggestions
        switch current.condition {
        case .clear:
            newSuggestions.append("😎 Clear skies - perfect for glasses photos!")
        case .cloudy, .mostlyCloudy:
            newSuggestions.append("☁️ Good diffused lighting for photos")
        case .partlyCloudy:
            newSuggestions.append("⛅ Mixed lighting - great for creative shots")
        case .rain, .drizzle:
            newSuggestions.append("🌧️ Rainy - protect your glasses!")
        case .snow:
            newSuggestions.append("❄️ Snowy conditions - keep lenses dry")
        case .foggy, .haze:
            newSuggestions.append("🌫️ Foggy - wipe lenses frequently")
        default:
            break
        }

        // Wind-based suggestions
        if current.wind.speed.value > 10 {
            newSuggestions.append("💨 Windy - secure your glasses")
        }

        // UV Index suggestions
        if let uvIndex = current.uvIndex.value {
            if uvIndex > 8 {
                newSuggestions.append("🌞 High UV - use sun protection")
            } else if uvIndex > 5 {
                newSuggestions.append("☀️ Moderate UV - consider shade")
            }
        }

        self.suggestions = newSuggestions
    }

    /// Get weather-appropriate photo tips
    public func getPhotoTips() -> [String] {
        guard let weather = currentWeather else {
            return ["Enable location to get weather-based photo tips"]
        }

        var tips: [String] = []

        switch weather.currentWeather.condition {
        case .clear:
            tips.append("Golden hour: Best time is early morning or late afternoon")
            tips.append("Avoid harsh midday sun for portraits")
        case .cloudy, .mostlyCloudy:
            tips.append("Even lighting - great for all photo types")
            tips.append("No harsh shadows - perfect for portraits")
        case .partlyCloudy:
            tips.append("Watch for dynamic lighting changes")
            tips.append("Cloud breaks create dramatic lighting")
        case .rain:
            tips.append("Capture rain drops and reflections")
            tips.append("Use manual focus to avoid focus hunting")
        case .snow:
            tips.append("Increase exposure for bright snow scenes")
            tips.append("Protect gear from moisture")
        case .foggy:
            tips.append("Mysterious atmospheric shots")
            tips.append("Close-up subjects work best")
        default:
            break
        }

        return tips
    }
}

// MARK: - Supporting Types

public struct WeatherConditions {
    public let temperature: Double
    public let condition: String
    public let humidity: Double
    public let windSpeed: Double
    public let uvIndex: Int
    public let visibility: Double

    public init(temperature: Double, condition: String, humidity: Double, windSpeed: Double, uvIndex: Int, visibility: Double) {
        self.temperature = temperature
        self.condition = condition
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.uvIndex = uvIndex
        self.visibility = visibility
    }
}

public enum WeatherError: LocalizedError {
    case locationUnavailable
    case weatherKitUnavailable
    case networkError

    public var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Location services unavailable"
        case .weatherKitUnavailable:
            return "WeatherKit service unavailable"
        case .networkError:
            return "Network error fetching weather"
        }
    }
}
