import UIKit
import Foundation
import Contacts
import EventKit
import CoreLocation
import Vision

/// Your Personal AI Companion
/// Learns about you, your preferences, and your life to provide intelligent assistance
@MainActor
public class PersonalAI {

    // MARK: - Singleton
    public static let shared = PersonalAI()

    // MARK: - Properties
    private var userProfile: UserProfile
    private var vipFaces: [VIPPerson] = []
    private var lifeMoments: [LifeMoment] = []
    private var preferences: UserPreferences
    private let ragEngine: RAGManager
    private let cagEngine: CAGManager
    private let mcpClient: MCPClient

    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()

    // MARK: - Initialization
    private init() {
        self.userProfile = UserProfile.load() ?? UserProfile.default()
        self.preferences = UserPreferences.load() ?? UserPreferences.default()
        self.ragEngine = RAGManager.shared
        self.cagEngine = CAGManager.shared
        self.mcpClient = MCPClient.shared

        loadVIPFaces()
        loadLifeMoments()

        print("🤖 PersonalAI initialized - Learning about you...")
    }

    // MARK: - Context Awareness

    /// Get complete context about current situation
    public func getCurrentContext() async -> PersonalContext {
        async let location = getCurrentLocation()
        async let calendar = getUpcomingEvents()
        async let weather = getCurrentWeather()
        async let timeOfDay = getTimeOfDay()
        async let nearbyVIPs = detectNearbyVIPs()

        return PersonalContext(
            location: await location,
            upcomingEvents: await calendar,
            weather: await weather,
            timeOfDay: await timeOfDay,
            nearbyVIPs: await nearbyVIPs,
            currentActivity: await detectCurrentActivity(),
            mood: preferences.currentMood,
            recentPhotos: getRecentPhotoContext()
        )
    }

    /// Analyze captured image with personal context
    public func analyzeWithContext(_ image: UIImage, stereoPair: StereoPair? = nil) async throws -> PersonalAnalysis {
        print("🧠 Analyzing image with your personal context...")

        // Get current context
        let context = await getCurrentContext()

        // Detect faces and match with VIPs
        let faces = try await detectFaces(in: image)
        let recognizedPeople = await recognizeVIPs(faces: faces, in: image)

        // Analyze scene with your preferences
        let sceneAnalysis = try await analyzeScene(image, context: context)

        // Generate personalized suggestions
        let suggestions = await generatePersonalizedSuggestions(
            image: image,
            context: context,
            people: recognizedPeople,
            scene: sceneAnalysis
        )

        // Check if this is a moment you'd want to remember
        let momentScore = calculateMomentScore(
            context: context,
            people: recognizedPeople,
            scene: sceneAnalysis
        )

        return PersonalAnalysis(
            context: context,
            recognizedPeople: recognizedPeople,
            sceneDescription: sceneAnalysis.description,
            emotionalTone: sceneAnalysis.emotion,
            momentScore: momentScore,
            suggestions: suggestions,
            shouldAutoCapture: momentScore > 0.8,
            shouldNotify: !recognizedPeople.isEmpty,
            personalRelevance: calculatePersonalRelevance(recognizedPeople, context)
        )
    }

    // MARK: - VIP Recognition

    /// Learn a new VIP face
    public func learnVIPFace(image: UIImage, name: String, relationship: String) async throws {
        print("📸 Learning face for: \(name) (\(relationship))")

        guard let cgImage = image.cgImage else {
            throw PersonalAIError.invalidImage
        }

        // Extract face features
        let faceRequest = VNDetectFaceRectanglesRequest()
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([faceRequest, faceLandmarksRequest])

        guard let faceObservation = faceRequest.results?.first else {
            throw PersonalAIError.noFaceDetected
        }

        // Create VIP person entry
        let vip = VIPPerson(
            id: UUID(),
            name: name,
            relationship: relationship,
            faceObservation: faceObservation,
            learnedDate: Date(),
            photosTaken: 0,
            lastSeen: nil,
            preferences: VIPPreferences()
        )

        vipFaces.append(vip)
        saveVIPFaces()

        // Store in RAG for context
        await ragEngine.store(
            content: "VIP: \(name), Relationship: \(relationship)",
            metadata: ["type": "vip", "name": name]
        )

        print("✅ Learned \(name)'s face!")
    }

    /// Recognize VIPs in captured image
    private func recognizeVIPs(faces: [VNFaceObservation], in image: UIImage) async -> [RecognizedPerson] {
        var recognized: [RecognizedPerson] = []

        for faceObservation in faces {
            // Try to match with known VIPs
            for vip in vipFaces {
                let similarity = calculateFaceSimilarity(faceObservation, vip.faceObservation)

                if similarity > 0.85 { // High confidence match
                    recognized.append(RecognizedPerson(
                        vip: vip,
                        confidence: similarity,
                        boundingBox: faceObservation.boundingBox
                    ))

                    // Update VIP stats
                    updateVIPStats(vip)
                    break
                }
            }
        }

        if !recognized.isEmpty {
            print("👥 Recognized: \(recognized.map { $0.vip.name }.joined(separator: ", "))")
        }

        return recognized
    }

    private func calculateFaceSimilarity(_ face1: VNFaceObservation, _ face2: VNFaceObservation) -> Double {
        // Simplified similarity - in production, use face embeddings
        let box1 = face1.boundingBox
        let box2 = face2.boundingBox

        let widthDiff = abs(box1.width - box2.width)
        let heightDiff = abs(box1.height - box2.height)

        let similarity = 1.0 - (Double(widthDiff + heightDiff) / 2.0)
        return max(0, min(1, similarity))
    }

    // MARK: - iPhone Integration

    private func getCurrentLocation() async -> CLLocation? {
        // Request location permission
        locationManager.requestWhenInUseAuthorization()

        return locationManager.location
    }

    private func getUpcomingEvents() async -> [EKEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: now)!

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
    }

    private func getCurrentWeather() async -> Weather? {
        // Integrate with weather API using location
        // For now, return placeholder
        return Weather(temperature: 72, condition: "Sunny", location: "Current Location")
    }

    private func getTimeOfDay() async -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    private func detectNearbyVIPs() async -> [String] {
        // Check if any VIPs are in current location context
        // Could integrate with Find My Friends, iMessage, etc.
        return []
    }

    private func detectCurrentActivity() async -> Activity {
        // Use motion sensors, location, calendar to detect activity
        // Running, meeting, relaxing, etc.
        return .general
    }

    // MARK: - RAG/CAG Integration

    /// Store life moment in RAG knowledge base
    public func rememberMoment(_ moment: LifeMoment) async {
        lifeMoments.append(moment)

        // Store in RAG for future context
        await ragEngine.store(
            content: """
            Date: \(moment.date)
            Location: \(moment.location?.description ?? "Unknown")
            People: \(moment.people.joined(separator: ", "))
            Activity: \(moment.activity)
            Notes: \(moment.notes)
            """,
            metadata: [
                "type": "life_moment",
                "date": moment.date.ISO8601Format(),
                "people": moment.people
            ]
        )

        saveLifeMoments()
        print("💾 Remembered moment: \(moment.activity)")
    }

    /// Query your personal knowledge base
    public func queryKnowledge(_ question: String) async -> String {
        print("❓ Querying knowledge: \(question)")

        // Use RAG to retrieve relevant context
        let context = await ragEngine.retrieve(query: question, limit: 5)

        // Use CAG to generate personalized response
        let response = await cagEngine.generate(
            prompt: question,
            context: context,
            style: preferences.responseStyle
        )

        return response
    }

    /// Get personalized suggestions based on context
    private func generatePersonalizedSuggestions(
        image: UIImage,
        context: PersonalContext,
        people: [RecognizedPerson],
        scene: SceneAnalysis
    ) async -> [PersonalSuggestion] {
        var suggestions: [PersonalSuggestion] = []

        // Suggestion 1: Photo with recognized VIPs
        if !people.isEmpty {
            let names = people.map { $0.vip.name }.joined(separator: " and ")
            suggestions.append(PersonalSuggestion(
                type: .capture,
                message: "Great shot with \(names)!",
                action: .autoSave,
                priority: .high
            ))
        }

        // Suggestion 2: Location-based
        if let location = context.location {
            suggestions.append(PersonalSuggestion(
                type: .location,
                message: "Beautiful view at \(location)",
                action: .tagLocation,
                priority: .medium
            ))
        }

        // Suggestion 3: Time-based
        switch context.timeOfDay {
        case .morning:
            if scene.hasGoodLighting {
                suggestions.append(PersonalSuggestion(
                    type: .lighting,
                    message: "Perfect morning light! Great time for photos.",
                    action: .enhanceLighting,
                    priority: .medium
                ))
            }
        case .evening:
            suggestions.append(PersonalSuggestion(
                type: .creative,
                message: "Golden hour! Try portrait mode.",
                action: .switchMode,
                priority: .high
            ))
        default:
            break
        }

        // Suggestion 4: Event-based
        if let event = context.upcomingEvents.first {
            suggestions.append(PersonalSuggestion(
                type: .reminder,
                message: "You have '\(event.title)' coming up. Document it?",
                action: .createAlbum,
                priority: .medium
            ))
        }

        return suggestions
    }

    // MARK: - Moment Scoring

    private func calculateMomentScore(
        context: PersonalContext,
        people: [RecognizedPerson],
        scene: SceneAnalysis
    ) -> Double {
        var score: Double = 0.5 // Base score

        // VIP presence increases score significantly
        score += Double(people.count) * 0.15

        // Special locations
        if scene.isLandmark || scene.isScenic {
            score += 0.1
        }

        // Special times
        if context.timeOfDay == .evening && scene.hasGoodLighting {
            score += 0.1 // Golden hour
        }

        // Special events
        if !context.upcomingEvents.isEmpty {
            score += 0.15
        }

        // Emotional content
        if scene.emotion == .happy || scene.emotion == .exciting {
            score += 0.1
        }

        return min(1.0, score)
    }

    private func calculatePersonalRelevance(_ people: [RecognizedPerson], _ context: PersonalContext) -> Double {
        // How personally relevant is this moment?
        var relevance: Double = 0.5

        // Close relationships increase relevance
        for person in people {
            switch person.vip.relationship.lowercased() {
            case "family", "spouse", "partner":
                relevance += 0.2
            case "close friend":
                relevance += 0.15
            case "friend":
                relevance += 0.1
            default:
                relevance += 0.05
            }
        }

        // Events increase relevance
        relevance += Double(context.upcomingEvents.count) * 0.1

        return min(1.0, relevance)
    }

    // MARK: - Helper Methods

    private func detectFaces(in image: UIImage) async throws -> [VNFaceObservation] {
        guard let cgImage = image.cgImage else {
            throw PersonalAIError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume(returning: request.results ?? [])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func analyzeScene(_ image: UIImage, context: PersonalContext) async throws -> SceneAnalysis {
        // Use Vision + your preferences to analyze
        return SceneAnalysis(
            description: "Scene analysis",
            emotion: .neutral,
            hasGoodLighting: true,
            isLandmark: false,
            isScenic: false
        )
    }

    private func updateVIPStats(_ vip: VIPPerson) {
        vip.photosTaken += 1
        vip.lastSeen = Date()
        saveVIPFaces()
    }

    private func getRecentPhotoContext() -> [String] {
        // Return context from recent photos
        return Array(lifeMoments.suffix(5).map { $0.activity })
    }

    // MARK: - Persistence

    private func loadVIPFaces() {
        // Load from UserDefaults or Core Data
        if let data = UserDefaults.standard.data(forKey: "vipFaces"),
           let decoded = try? JSONDecoder().decode([VIPPerson].self, from: data) {
            self.vipFaces = decoded
            print("✅ Loaded \(vipFaces.count) VIP faces")
        }
    }

    private func saveVIPFaces() {
        if let encoded = try? JSONEncoder().encode(vipFaces) {
            UserDefaults.standard.set(encoded, forKey: "vipFaces")
        }
    }

    private func loadLifeMoments() {
        if let data = UserDefaults.standard.data(forKey: "lifeMoments"),
           let decoded = try? JSONDecoder().decode([LifeMoment].self, from: data) {
            self.lifeMoments = decoded
            print("✅ Loaded \(lifeMoments.count) life moments")
        }
    }

    private func saveLifeMoments() {
        if let encoded = try? JSONEncoder().encode(lifeMoments) {
            UserDefaults.standard.set(encoded, forKey: "lifeMoments")
        }
    }
}

// MARK: - Supporting Types

public struct PersonalContext: Codable {
    let location: CLLocation?
    let upcomingEvents: [EKEvent]
    let weather: Weather?
    let timeOfDay: TimeOfDay
    let nearbyVIPs: [String]
    let currentActivity: Activity
    let mood: Mood?
    let recentPhotos: [String]

    enum CodingKeys: String, CodingKey {
        case timeOfDay, nearbyVIPs, currentActivity, mood, recentPhotos
    }
}

public class VIPPerson: Codable {
    let id: UUID
    let name: String
    let relationship: String
    let faceObservation: VNFaceObservation
    let learnedDate: Date
    var photosTaken: Int
    var lastSeen: Date?
    var preferences: VIPPreferences

    init(id: UUID, name: String, relationship: String, faceObservation: VNFaceObservation,
         learnedDate: Date, photosTaken: Int, lastSeen: Date?, preferences: VIPPreferences) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.faceObservation = faceObservation
        self.learnedDate = learnedDate
        self.photosTaken = photosTaken
        self.lastSeen = lastSeen
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case id, name, relationship, learnedDate, photosTaken, lastSeen, preferences
    }
}

public struct VIPPreferences: Codable {
    var autoCapture: Bool = true
    var notifyWhenSeen: Bool = true
    var favoriteAngles: [String] = []
}

public struct RecognizedPerson {
    let vip: VIPPerson
    let confidence: Double
    let boundingBox: CGRect
}

public struct LifeMoment: Codable {
    let id: UUID
    let date: Date
    let location: CLLocation?
    let people: [String]
    let activity: String
    let notes: String
    let photos: [String]

    enum CodingKeys: String, CodingKey {
        case id, date, people, activity, notes, photos
    }
}

public struct PersonalAnalysis {
    let context: PersonalContext
    let recognizedPeople: [RecognizedPerson]
    let sceneDescription: String
    let emotionalTone: Emotion
    let momentScore: Double
    let suggestions: [PersonalSuggestion]
    let shouldAutoCapture: Bool
    let shouldNotify: Bool
    let personalRelevance: Double
}

public struct PersonalSuggestion {
    let type: SuggestionType
    let message: String
    let action: SuggestedAction
    let priority: Priority

    enum SuggestionType {
        case capture, location, lighting, creative, reminder, social
    }

    enum SuggestedAction {
        case autoSave, tagLocation, enhanceLighting, switchMode, createAlbum, share
    }

    enum Priority {
        case low, medium, high
    }
}

public struct SceneAnalysis {
    let description: String
    let emotion: Emotion
    let hasGoodLighting: Bool
    let isLandmark: Bool
    let isScenic: Bool
}

public struct UserProfile: Codable {
    var name: String
    var favoriteLocations: [String]
    var favoriteActivities: [String]
    var photoStyle: PhotoStyle

    static func `default`() -> UserProfile {
        UserProfile(
            name: "User",
            favoriteLocations: [],
            favoriteActivities: [],
            photoStyle: .balanced
        )
    }

    static func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: "userProfile"),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return profile
    }
}

public struct UserPreferences: Codable {
    var autoCapture: Bool = false
    var notifyOnVIP: Bool = true
    var responseStyle: String = "friendly"
    var currentMood: Mood? = nil

    static func `default`() -> UserPreferences {
        UserPreferences()
    }

    static func load() -> UserPreferences? {
        guard let data = UserDefaults.standard.data(forKey: "userPreferences"),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return nil
        }
        return prefs
    }
}

public struct Weather: Codable {
    let temperature: Int
    let condition: String
    let location: String
}

public enum TimeOfDay: String, Codable {
    case morning, afternoon, evening, night
}

public enum Activity: String, Codable {
    case meeting, workout, relaxing, traveling, dining, general
}

public enum Mood: String, Codable {
    case happy, excited, calm, focused, tired
}

public enum Emotion: String, Codable {
    case happy, sad, exciting, peaceful, neutral
}

public enum PhotoStyle: String, Codable {
    case vibrant, natural, cinematic, balanced
}

public enum PersonalAIError: LocalizedError {
    case invalidImage
    case noFaceDetected
    case contextUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image"
        case .noFaceDetected: return "No face detected"
        case .contextUnavailable: return "Context unavailable"
        }
    }
}
