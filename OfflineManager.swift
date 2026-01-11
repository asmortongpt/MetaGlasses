import Foundation
import SwiftUI
import CoreData
import Network
import Combine
import SQLite3

// MARK: - Offline Manager with Intelligent Caching & Queuing
@MainActor
class OfflineManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isOnline = true
    @Published var connectionType: ConnectionType = .unknown
    @Published var syncStatus: SyncStatus = .idle
    @Published var cacheSize: Int64 = 0
    @Published var queuedRequests: [QueuedRequest] = []
    @Published var syncProgress: Double = 0.0
    @Published var lastSyncDate: Date?
    @Published var offlineCapabilities: Set<OfflineCapability> = []

    // MARK: - Private Properties
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.metaglasses.network.monitor")
    private var cancellables = Set<AnyCancellable>()

    // Storage
    private let cacheManager: CacheManager
    private let requestQueue: RequestQueue
    private let dataStore: DataStore
    private let syncEngine: SyncEngine

    // Configuration
    private var configuration = Configuration()

    // MARK: - Types
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case offline
        case unknown

        var description: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "Cellular"
            case .ethernet: return "Ethernet"
            case .offline: return "Offline"
            case .unknown: return "Unknown"
            }
        }

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .ethernet: return "cable.connector"
            case .offline: return "wifi.slash"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    enum SyncStatus {
        case idle
        case syncing
        case completed
        case failed(Error)
        case paused

        var description: String {
            switch self {
            case .idle: return "Ready"
            case .syncing: return "Syncing..."
            case .completed: return "Synced"
            case .failed(let error): return "Failed: \(error.localizedDescription)"
            case .paused: return "Paused"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .gray
            case .syncing: return .blue
            case .completed: return .green
            case .failed: return .red
            case .paused: return .orange
            }
        }
    }

    struct Configuration {
        var maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
        var maxQueueSize: Int = 1000
        var syncInterval: TimeInterval = 300 // 5 minutes
        var retryAttempts: Int = 3
        var retryDelay: TimeInterval = 2.0
        var enableAutoSync: Bool = true
        var enableSmartCaching: Bool = true
        var enablePredictiveLoading: Bool = true
        var compressData: Bool = true
        var encryptCache: Bool = true
    }

    struct QueuedRequest: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let type: RequestType
        let endpoint: String
        let method: String
        let headers: [String: String]?
        let body: Data?
        var retryCount: Int = 0
        let priority: Priority
        let requiresAuth: Bool
        let expiresAt: Date?

        enum RequestType: String, Codable {
            case ai
            case vision
            case sync
            case analytics
            case upload
            case download
        }

        enum Priority: Int, Codable, Comparable {
            case low = 0
            case medium = 1
            case high = 2
            case critical = 3

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                return lhs.rawValue < rhs.rawValue
            }
        }
    }

    enum OfflineCapability: String, CaseIterable {
        case textChat = "Text Chat"
        case voiceCommands = "Voice Commands"
        case imageAnalysis = "Basic Image Analysis"
        case faceDetection = "Face Detection"
        case objectRecognition = "Object Recognition"
        case textExtraction = "Text Extraction"
        case navigation = "Offline Maps"
        case translation = "Offline Translation"
        case notes = "Note Taking"
        case reminders = "Reminders"
    }

    // MARK: - Initialization
    init() {
        self.cacheManager = CacheManager()
        self.requestQueue = RequestQueue()
        self.dataStore = DataStore()
        self.syncEngine = SyncEngine()

        setupNetworkMonitoring()
        setupOfflineCapabilities()
        loadQueuedRequests()
        startAutoSync()
    }

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkChange(path)
            }
        }

        networkMonitor.start(queue: monitorQueue)
    }

    private func handleNetworkChange(_ path: NWPath) {
        isOnline = path.status == .satisfied

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else if path.status == .satisfied {
            connectionType = .unknown
        } else {
            connectionType = .offline
        }

        // Trigger sync when coming online
        if isOnline && !queuedRequests.isEmpty {
            Task {
                await processQueuedRequests()
            }
        }

        print("📶 Network status: \(connectionType.description)")
    }

    private func setupOfflineCapabilities() {
        // Determine which features are available offline based on cached models
        offlineCapabilities = [
            .textChat,
            .voiceCommands,
            .imageAnalysis,
            .faceDetection,
            .objectRecognition,
            .textExtraction,
            .notes,
            .reminders
        ]

        // Check for offline models
        if dataStore.hasOfflineTranslationModels() {
            offlineCapabilities.insert(.translation)
        }

        if dataStore.hasOfflineMaps() {
            offlineCapabilities.insert(.navigation)
        }
    }

    // MARK: - Queue Management
    func queueRequest(_ request: QueuedRequest) {
        guard queuedRequests.count < configuration.maxQueueSize else {
            // Remove oldest low-priority request if at capacity
            if let oldestLowPriority = queuedRequests
                .filter({ $0.priority == .low })
                .sorted(by: { $0.timestamp < $1.timestamp })
                .first,
               let index = queuedRequests.firstIndex(where: { $0.id == oldestLowPriority.id }) {
                queuedRequests.remove(at: index)
            } else {
                print("⚠️ Queue is full, cannot add request")
                return
            }
        }

        queuedRequests.append(request)
        queuedRequests.sort { $0.priority > $1.priority }

        // Persist queue
        saveQueuedRequests()

        print("📝 Queued request: \(request.type.rawValue)")
    }

    func processQueuedRequests() async {
        guard isOnline, !queuedRequests.isEmpty else { return }

        syncStatus = .syncing
        syncProgress = 0.0

        let totalRequests = queuedRequests.count
        var processedRequests = 0
        var failedRequests: [QueuedRequest] = []

        for request in queuedRequests {
            // Check if request has expired
            if let expiresAt = request.expiresAt, Date() > expiresAt {
                processedRequests += 1
                continue
            }

            do {
                try await executeRequest(request)
                processedRequests += 1
            } catch {
                print("❌ Failed to execute request: \(error)")

                var failedRequest = request
                failedRequest.retryCount += 1

                if failedRequest.retryCount < configuration.retryAttempts {
                    failedRequests.append(failedRequest)
                }
            }

            syncProgress = Double(processedRequests) / Double(totalRequests)
        }

        // Update queue with failed requests
        queuedRequests = failedRequests

        syncStatus = failedRequests.isEmpty ? .completed : .failed(OfflineError.partialSync)
        lastSyncDate = Date()

        saveQueuedRequests()
    }

    private func executeRequest(_ request: QueuedRequest) async throws {
        guard let url = URL(string: request.endpoint) else {
            throw OfflineError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body

        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (_, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OfflineError.requestFailed
        }
    }

    // MARK: - Cache Management
    func cacheData(_ data: Data, for key: String, type: CacheType = .general) {
        cacheManager.store(data, key: key, type: type)
        updateCacheSize()
    }

    func getCachedData(for key: String, type: CacheType = .general) -> Data? {
        return cacheManager.retrieve(key: key, type: type)
    }

    func cacheResponse<T: Codable>(_ response: T, for request: String) {
        do {
            let data = try JSONEncoder().encode(response)
            cacheData(data, for: request, type: .apiResponse)
        } catch {
            print("❌ Failed to cache response: \(error)")
        }
    }

    func getCachedResponse<T: Codable>(_ type: T.Type, for request: String) -> T? {
        guard let data = getCachedData(for: request, type: .apiResponse) else { return nil }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("❌ Failed to decode cached response: \(error)")
            return nil
        }
    }

    func clearCache(type: CacheType? = nil) {
        if let type = type {
            cacheManager.clear(type: type)
        } else {
            cacheManager.clearAll()
        }
        updateCacheSize()
    }

    private func updateCacheSize() {
        cacheSize = cacheManager.calculateSize()

        // Trigger cleanup if exceeding limit
        if cacheSize > configuration.maxCacheSize {
            Task {
                await performCacheCleanup()
            }
        }
    }

    private func performCacheCleanup() async {
        // Remove least recently used items
        cacheManager.cleanupLRU(targetSize: configuration.maxCacheSize * 80 / 100)
        updateCacheSize()
    }

    // MARK: - Predictive Loading
    func predictiveLoad(for context: PredictionContext) async {
        guard configuration.enablePredictiveLoading else { return }

        let predictions = await generatePredictions(for: context)

        for prediction in predictions {
            if shouldPreload(prediction) {
                await preloadContent(prediction)
            }
        }
    }

    private func generatePredictions(for context: PredictionContext) async -> [ContentPrediction] {
        var predictions: [ContentPrediction] = []

        // Time-based predictions
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 7 && hour <= 9 {
            predictions.append(ContentPrediction(type: .morningBriefing, confidence: 0.9))
        } else if hour >= 17 && hour <= 19 {
            predictions.append(ContentPrediction(type: .eveningSummary, confidence: 0.85))
        }

        // Location-based predictions
        if let location = context.location {
            if location.isNearWork {
                predictions.append(ContentPrediction(type: .workDocuments, confidence: 0.8))
            } else if location.isNearHome {
                predictions.append(ContentPrediction(type: .personalContent, confidence: 0.75))
            }
        }

        // Usage pattern predictions
        if context.recentQueries.contains(where: { $0.contains("weather") }) {
            predictions.append(ContentPrediction(type: .weatherData, confidence: 0.7))
        }

        return predictions
    }

    private func shouldPreload(_ prediction: ContentPrediction) -> Bool {
        // Consider connection type and battery level
        switch connectionType {
        case .wifi:
            return prediction.confidence > 0.5
        case .cellular:
            return prediction.confidence > 0.8
        default:
            return false
        }
    }

    private func preloadContent(_ prediction: ContentPrediction) async {
        // Preload predicted content
        switch prediction.type {
        case .morningBriefing:
            await preloadMorningBriefing()
        case .eveningSummary:
            await preloadEveningSummary()
        case .workDocuments:
            await preloadWorkDocuments()
        case .personalContent:
            await preloadPersonalContent()
        case .weatherData:
            await preloadWeatherData()
        }
    }

    // MARK: - Sync Management
    private func startAutoSync() {
        guard configuration.enableAutoSync else { return }

        Timer.publish(every: configuration.syncInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.performSync()
                }
            }
            .store(in: &cancellables)
    }

    func performSync() async {
        guard isOnline else { return }

        syncStatus = .syncing
        syncProgress = 0.0

        do {
            // Sync conversations
            syncProgress = 0.25
            try await syncEngine.syncConversations()

            // Sync images
            syncProgress = 0.5
            try await syncEngine.syncImages()

            // Sync preferences
            syncProgress = 0.75
            try await syncEngine.syncPreferences()

            // Process queued requests
            syncProgress = 0.9
            await processQueuedRequests()

            syncProgress = 1.0
            syncStatus = .completed
            lastSyncDate = Date()

        } catch {
            syncStatus = .failed(error)
            print("❌ Sync failed: \(error)")
        }
    }

    func pauseSync() {
        syncStatus = .paused
        syncEngine.pause()
    }

    func resumeSync() {
        Task {
            await performSync()
        }
    }

    // MARK: - Persistence
    private func loadQueuedRequests() {
        if let data = UserDefaults.standard.data(forKey: "queuedRequests"),
           let requests = try? JSONDecoder().decode([QueuedRequest].self, from: data) {
            queuedRequests = requests
        }
    }

    private func saveQueuedRequests() {
        if let data = try? JSONEncoder().encode(queuedRequests) {
            UserDefaults.standard.set(data, forKey: "queuedRequests")
        }
    }

    // MARK: - Offline Responses
    func generateOfflineResponse(for query: String) -> String {
        // Generate intelligent offline responses
        let lowercased = query.lowercased()

        if lowercased.contains("weather") {
            return getCachedWeatherResponse() ?? "Weather information is not available offline. Please connect to the internet for current conditions."
        } else if lowercased.contains("news") {
            return getCachedNewsResponse() ?? "News updates require an internet connection. Your last update was \(lastSyncDate?.timeAgoDisplay() ?? "unavailable")."
        } else if lowercased.contains("reminder") || lowercased.contains("note") {
            return "I've saved your \(lowercased.contains("reminder") ? "reminder" : "note") locally. It will sync when you're back online."
        } else if lowercased.contains("photo") || lowercased.contains("picture") {
            return "Photo captured and saved locally. It will be processed when you reconnect."
        }

        return "I'm currently offline but can still help with: \(offlineCapabilities.map { $0.rawValue }.joined(separator: ", "))"
    }

    private func getCachedWeatherResponse() -> String? {
        // Return cached weather if available and recent
        if let weatherData = getCachedData(for: "weather", type: .apiResponse),
           let weather = try? JSONDecoder().decode(WeatherData.self, from: weatherData),
           Date().timeIntervalSince(weather.timestamp) < 3600 {
            return "Cached weather (\(weather.timestamp.timeAgoDisplay())): \(weather.description)"
        }
        return nil
    }

    private func getCachedNewsResponse() -> String? {
        // Return cached news if available
        if let newsData = getCachedData(for: "news", type: .apiResponse),
           let news = try? JSONDecoder().decode(NewsData.self, from: newsData) {
            return "Cached news (\(news.timestamp.timeAgoDisplay())): \(news.headlines.joined(separator: ", "))"
        }
        return nil
    }

    // Preload methods
    private func preloadMorningBriefing() async {
        // Preload morning briefing content
    }

    private func preloadEveningSummary() async {
        // Preload evening summary content
    }

    private func preloadWorkDocuments() async {
        // Preload work-related documents
    }

    private func preloadPersonalContent() async {
        // Preload personal content
    }

    private func preloadWeatherData() async {
        // Preload weather data
    }
}

// MARK: - Supporting Classes
class CacheManager {
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private var metadata: CacheMetadata

    init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = documentsPath.appendingPathComponent("MetaGlassesCache")

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load metadata
        self.metadata = CacheMetadata.load() ?? CacheMetadata()
    }

    func store(_ data: Data, key: String, type: CacheType) {
        let typeDirectory = cacheDirectory.appendingPathComponent(type.rawValue)
        try? fileManager.createDirectory(at: typeDirectory, withIntermediateDirectories: true)

        let fileURL = typeDirectory.appendingPathComponent(key.md5Hash)

        do {
            try data.write(to: fileURL)
            metadata.updateEntry(key: key, size: Int64(data.count), type: type)
            metadata.save()
        } catch {
            print("❌ Failed to cache data: \(error)")
        }
    }

    func retrieve(key: String, type: CacheType) -> Data? {
        let fileURL = cacheDirectory
            .appendingPathComponent(type.rawValue)
            .appendingPathComponent(key.md5Hash)

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        metadata.recordAccess(key: key)
        metadata.save()

        return try? Data(contentsOf: fileURL)
    }

    func clear(type: CacheType) {
        let typeDirectory = cacheDirectory.appendingPathComponent(type.rawValue)
        try? fileManager.removeItem(at: typeDirectory)
        metadata.clearType(type)
        metadata.save()
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        metadata = CacheMetadata()
        metadata.save()
    }

    func calculateSize() -> Int64 {
        return metadata.totalSize
    }

    func cleanupLRU(targetSize: Int64) {
        let entries = metadata.entries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }

        var currentSize = metadata.totalSize

        for (key, entry) in entries {
            if currentSize <= targetSize { break }

            let fileURL = cacheDirectory
                .appendingPathComponent(entry.type.rawValue)
                .appendingPathComponent(key.md5Hash)

            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
                currentSize -= entry.size
                metadata.removeEntry(key: key)
            }
        }

        metadata.save()
    }
}

class DataStore {
    private let database: OpaquePointer?

    init() {
        self.database = DataStore.openDatabase()
        createTables()
    }

    static func openDatabase() -> OpaquePointer? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("metaglasses.sqlite").path

        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            return db
        } else {
            print("❌ Failed to open database")
            return nil
        }
    }

    private func createTables() {
        // Create necessary tables for offline storage
        let createSQL = """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                content TEXT,
                timestamp REAL,
                synced INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS images (
                id TEXT PRIMARY KEY,
                data BLOB,
                metadata TEXT,
                timestamp REAL,
                synced INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS preferences (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at REAL
            );
        """

        if sqlite3_exec(database, createSQL, nil, nil, nil) != SQLITE_OK {
            print("❌ Failed to create tables")
        }
    }

    func hasOfflineTranslationModels() -> Bool {
        // Check if offline translation models are downloaded
        let modelPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TranslationModels")

        if let path = modelPath, FileManager.default.fileExists(atPath: path.path) {
            // Check for at least one .mlmodel or .mlmodelc file
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
                return contents.contains { $0.pathExtension == "mlmodelc" || $0.pathExtension == "mlmodel" }
            } catch {
                return false
            }
        }
        return false
    }

    func hasOfflineMaps() -> Bool {
        // Check if offline maps are available
        let mapsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OfflineMaps")

        if let path = mapsPath, FileManager.default.fileExists(atPath: path.path) {
            // Check for map tile data
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
                return !contents.isEmpty
            } catch {
                return false
            }
        }
        return false
    }
}

class SyncEngine {
    private var isPaused = false

    func syncConversations() async throws {
        guard !isPaused else { throw OfflineError.syncPaused }
        // Sync conversation data
    }

    func syncImages() async throws {
        guard !isPaused else { throw OfflineError.syncPaused }
        // Sync image data
    }

    func syncPreferences() async throws {
        guard !isPaused else { throw OfflineError.syncPaused }
        // Sync user preferences
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }
}

// MARK: - Supporting Types
enum CacheType: String {
    case general = "general"
    case apiResponse = "api"
    case images = "images"
    case conversations = "conversations"
    case models = "models"
    case temporary = "temp"
}

struct CacheMetadata: Codable {
    var entries: [String: CacheEntry] = [:]
    var totalSize: Int64 = 0

    struct CacheEntry: Codable {
        let size: Int64
        let type: CacheType
        var lastAccessed: Date
        let created: Date
    }

    static func load() -> CacheMetadata? {
        guard let data = UserDefaults.standard.data(forKey: "cacheMetadata"),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "cacheMetadata")
        }
    }

    mutating func updateEntry(key: String, size: Int64, type: CacheType) {
        if let existing = entries[key] {
            totalSize -= existing.size
        }

        entries[key] = CacheEntry(
            size: size,
            type: type,
            lastAccessed: Date(),
            created: Date()
        )
        totalSize += size
    }

    mutating func recordAccess(key: String) {
        entries[key]?.lastAccessed = Date()
    }

    mutating func removeEntry(key: String) {
        if let entry = entries[key] {
            totalSize -= entry.size
            entries.removeValue(forKey: key)
        }
    }

    mutating func clearType(_ type: CacheType) {
        let keysToRemove = entries.compactMap { $0.value.type == type ? $0.key : nil }
        for key in keysToRemove {
            removeEntry(key: key)
        }
    }
}

struct PredictionContext {
    let location: LocationContext?
    let recentQueries: [String]
    let timeOfDay: Date
    let batteryLevel: Float
    let connectionType: OfflineManager.ConnectionType

    struct LocationContext {
        let isNearWork: Bool
        let isNearHome: Bool
        let isCommuting: Bool
    }
}

struct ContentPrediction {
    let type: ContentType
    let confidence: Double

    enum ContentType {
        case morningBriefing
        case eveningSummary
        case workDocuments
        case personalContent
        case weatherData
    }
}

struct WeatherData: Codable {
    let timestamp: Date
    let description: String
    let temperature: Double
    let conditions: String
}

struct NewsData: Codable {
    let timestamp: Date
    let headlines: [String]
}

enum OfflineError: LocalizedError {
    case invalidURL
    case requestFailed
    case partialSync
    case syncPaused

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed:
            return "Request failed"
        case .partialSync:
            return "Some requests failed during sync"
        case .syncPaused:
            return "Sync is paused"
        }
    }
}

// MARK: - Extensions
extension String {
    var md5Hash: String {
        // Simple hash for file naming
        return String(self.hashValue)
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}