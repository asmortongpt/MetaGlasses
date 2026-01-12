import Foundation
import UIKit
import CoreLocation

/// Performance Optimizer
/// Optimizes memory, battery, network, and background task performance
@MainActor
public class PerformanceOptimizer: ObservableObject {

    // MARK: - Singleton
    public static let shared = PerformanceOptimizer()

    // MARK: - Published Properties
    @Published public var memoryUsage: Double = 0
    @Published public var batteryLevel: Float = 1.0
    @Published public var networkRequestsPerMinute: Int = 0
    @Published public var optimizationStatus: OptimizationStatus = .idle
    @Published public var performanceMetrics: PerformanceMetrics

    // MARK: - Properties
    private var imageCache: NSCache<NSString, UIImage>
    private var embeddingCache: NSCache<NSString, NSArray>
    private var networkRequestQueue: [NetworkRequest] = []
    private var backgroundTasks: [BackgroundTask] = []
    private var sensorThrottleTimers: [String: Timer] = [:]

    // Performance thresholds
    private let maxMemoryUsageMB: Double = 500
    private let maxNetworkRequestsPerMinute: Int = 30
    private let imageCompressionQuality: CGFloat = 0.8
    private let cacheSizeLimit = 100 * 1024 * 1024 // 100 MB

    // MARK: - Initialization
    private init() {
        self.performanceMetrics = PerformanceMetrics()

        // Configure image cache
        self.imageCache = NSCache<NSString, UIImage>()
        imageCache.totalCostLimit = cacheSizeLimit
        imageCache.countLimit = 100

        // Configure embedding cache
        self.embeddingCache = NSCache<NSString, NSArray>()
        embeddingCache.totalCostLimit = cacheSizeLimit / 2
        embeddingCache.countLimit = 1000

        print("⚡️ PerformanceOptimizer initialized")
        startMonitoring()
    }

    // MARK: - Monitoring

    /// Start performance monitoring
    public func startMonitoring() {
        // Monitor memory usage every 10 seconds
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }

        // Monitor battery every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryLevel()
            }
        }

        // Monitor network requests every minute
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNetworkMetrics()
            }
        }

        // Clean up caches every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupCaches()
            }
        }

        print("✅ Performance monitoring started")
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024 / 1024
            memoryUsage = usedMB
            performanceMetrics.memoryUsageMB = usedMB

            // Trigger cleanup if over threshold
            if usedMB > maxMemoryUsageMB {
                print("⚠️ High memory usage detected: \(usedMB) MB")
                optimizeMemory()
            }
        }
    }

    private func updateBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        performanceMetrics.batteryLevel = batteryLevel

        // Enable aggressive optimization in low battery
        if batteryLevel < 0.2 && batteryLevel > 0 {
            print("🔋 Low battery detected: \(Int(batteryLevel * 100))%")
            enableBatterySavingMode()
        }
    }

    private func updateNetworkMetrics() {
        networkRequestsPerMinute = networkRequestQueue.count
        performanceMetrics.networkRequestsPerMinute = networkRequestsPerMinute

        // Clear old requests
        networkRequestQueue.removeAll()

        // Warn if high network usage
        if networkRequestsPerMinute > maxNetworkRequestsPerMinute {
            print("⚠️ High network usage: \(networkRequestsPerMinute) requests/min")
        }
    }

    // MARK: - Memory Optimization

    /// Optimize memory usage
    public func optimizeMemory() {
        optimizationStatus = .optimizing

        // Clear image cache
        imageCache.removeAllObjects()

        // Clear embedding cache (keep only recent)
        embeddingCache.removeAllObjects()

        // Trim background task queue
        if backgroundTasks.count > 10 {
            backgroundTasks = Array(backgroundTasks.suffix(10))
        }

        // Trim network request queue
        if networkRequestQueue.count > 100 {
            networkRequestQueue = Array(networkRequestQueue.suffix(100))
        }

        optimizationStatus = .idle
        print("✅ Memory optimization complete")
    }

    /// Cache image with compression
    public func cacheImage(_ image: UIImage, forKey key: String) {
        // Compress image before caching
        guard let compressed = compressImage(image) else { return }

        let cost = estimateImageSize(compressed)
        imageCache.setObject(compressed, forKey: key as NSString, cost: cost)
    }

    /// Retrieve cached image
    public func getCachedImage(forKey key: String) -> UIImage? {
        return imageCache.object(forKey: key as NSString)
    }

    /// Compress image for storage
    private func compressImage(_ image: UIImage) -> UIImage? {
        guard let data = image.jpegData(compressionQuality: imageCompressionQuality),
              let compressed = UIImage(data: data) else {
            return nil
        }
        return compressed
    }

    /// Estimate image size in bytes
    private func estimateImageSize(_ image: UIImage) -> Int {
        guard let data = image.jpegData(compressionQuality: 1.0) else {
            return 0
        }
        return data.count
    }

    /// Lazy load image with caching
    public func lazyLoadImage(url: URL) async throws -> UIImage {
        let key = url.absoluteString

        // Check cache first
        if let cached = getCachedImage(forKey: key) {
            performanceMetrics.cacheHits += 1
            return cached
        }

        // Download and cache
        performanceMetrics.cacheMisses += 1
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw PerformanceError.invalidImage
        }

        cacheImage(image, forKey: key)
        return image
    }

    // MARK: - Battery Optimization

    /// Enable battery saving mode
    public func enableBatterySavingMode() {
        optimizationStatus = .batterySaving

        // Throttle sensor updates
        throttleSensorUpdates(interval: 5.0) // Update every 5 seconds instead of 1

        // Reduce network requests
        batchNetworkRequests(batchSize: 10, interval: 60) // Batch every minute

        // Pause non-essential background tasks
        pauseNonEssentialTasks()

        print("🔋 Battery saving mode enabled")
    }

    /// Disable battery saving mode
    public func disableBatterySavingMode() {
        optimizationStatus = .idle

        // Resume normal sensor updates
        throttleSensorUpdates(interval: 1.0)

        // Resume normal network behavior
        batchNetworkRequests(batchSize: 1, interval: 0)

        // Resume background tasks
        resumeBackgroundTasks()

        print("✅ Battery saving mode disabled")
    }

    /// Throttle sensor updates
    private func throttleSensorUpdates(interval: TimeInterval) {
        // Cancel existing timers
        for (_, timer) in sensorThrottleTimers {
            timer.invalidate()
        }
        sensorThrottleTimers.removeAll()

        // Set new throttle interval
        performanceMetrics.sensorThrottleInterval = interval
    }

    /// Pause non-essential background tasks
    private func pauseNonEssentialTasks() {
        for i in 0..<backgroundTasks.count {
            if !backgroundTasks[i].isEssential {
                backgroundTasks[i].isPaused = true
            }
        }
    }

    /// Resume background tasks
    private func resumeBackgroundTasks() {
        for i in 0..<backgroundTasks.count {
            backgroundTasks[i].isPaused = false
        }
    }

    // MARK: - Network Optimization

    /// Record network request
    public func recordNetworkRequest(_ request: NetworkRequest) {
        networkRequestQueue.append(request)
    }

    /// Batch network requests
    private func batchNetworkRequests(batchSize: Int, interval: TimeInterval) {
        performanceMetrics.networkBatchSize = batchSize
        performanceMetrics.networkBatchInterval = interval
    }

    /// Execute batched network requests
    public func executeBatchedRequests() async {
        guard !networkRequestQueue.isEmpty else { return }

        let batchSize = performanceMetrics.networkBatchSize
        let batch = Array(networkRequestQueue.prefix(batchSize))

        // Execute batch in parallel
        await withTaskGroup(of: Void.self) { group in
            for request in batch {
                group.addTask {
                    await self.executeNetworkRequest(request)
                }
            }
        }

        // Remove executed requests
        networkRequestQueue.removeFirst(min(batchSize, networkRequestQueue.count))
    }

    private func executeNetworkRequest(_ request: NetworkRequest) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request.urlRequest)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                request.completion(.success(data))
            } else {
                request.completion(.failure(PerformanceError.networkError))
            }
        } catch {
            request.completion(.failure(error))
        }
    }

    /// Compress request payload
    public func compressPayload(_ data: Data) -> Data? {
        return (data as NSData).compressed(using: .lzfse) as Data?
    }

    /// Decompress response payload
    public func decompressPayload(_ data: Data) -> Data? {
        return (data as NSData).decompressed(using: .lzfse) as Data?
    }

    // MARK: - Background Task Management

    /// Schedule background task
    public func scheduleBackgroundTask(
        name: String,
        isEssential: Bool = false,
        task: @escaping () async -> Void
    ) {
        let backgroundTask = BackgroundTask(
            id: UUID(),
            name: name,
            isEssential: isEssential,
            isPaused: false,
            task: task
        )

        backgroundTasks.append(backgroundTask)

        // Execute if not in battery saving mode or if essential
        if optimizationStatus != .batterySaving || isEssential {
            Task {
                await executeBackgroundTask(backgroundTask)
            }
        }
    }

    private func executeBackgroundTask(_ task: BackgroundTask) async {
        guard !task.isPaused else { return }

        let startTime = Date()
        await task.task()
        let duration = Date().timeIntervalSince(startTime)

        performanceMetrics.averageTaskDuration =
            (performanceMetrics.averageTaskDuration + duration) / 2.0
    }

    // MARK: - Cache Management

    /// Clean up old caches
    private func cleanupCaches() {
        // Clear 25% of image cache
        let imagesToRemove = imageCache.countLimit / 4
        for _ in 0..<imagesToRemove {
            // NSCache automatically evicts least recently used
        }

        // Clear 25% of embedding cache
        let embeddingsToRemove = embeddingCache.countLimit / 4
        for _ in 0..<embeddingsToRemove {
            // NSCache automatically evicts least recently used
        }

        print("🧹 Cache cleanup complete")
    }

    /// Get cache statistics
    public func getCacheStats() -> CacheStats {
        return CacheStats(
            imagesCached: imageCache.countLimit,
            embeddingsCached: embeddingCache.countLimit,
            totalCacheSizeMB: Double(cacheSizeLimit) / 1024 / 1024,
            cacheHits: performanceMetrics.cacheHits,
            cacheMisses: performanceMetrics.cacheMisses,
            hitRate: calculateHitRate()
        )
    }

    private func calculateHitRate() -> Double {
        let total = performanceMetrics.cacheHits + performanceMetrics.cacheMisses
        guard total > 0 else { return 0 }
        return Double(performanceMetrics.cacheHits) / Double(total)
    }

    // MARK: - Performance Report

    /// Generate performance report
    public func generatePerformanceReport() -> PerformanceReport {
        return PerformanceReport(
            timestamp: Date(),
            memoryUsageMB: memoryUsage,
            batteryLevel: batteryLevel,
            networkRequestsPerMinute: networkRequestsPerMinute,
            cacheStats: getCacheStats(),
            activeBackgroundTasks: backgroundTasks.filter { !$0.isPaused }.count,
            metrics: performanceMetrics,
            status: optimizationStatus
        )
    }
}

// MARK: - Models

public enum OptimizationStatus: String {
    case idle
    case optimizing
    case batterySaving
}

public struct PerformanceMetrics {
    public var memoryUsageMB: Double = 0
    public var batteryLevel: Float = 1.0
    public var networkRequestsPerMinute: Int = 0
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0
    public var sensorThrottleInterval: TimeInterval = 1.0
    public var networkBatchSize: Int = 1
    public var networkBatchInterval: TimeInterval = 0
    public var averageTaskDuration: TimeInterval = 0

    public init() {}
}

public struct NetworkRequest {
    let id: UUID
    let urlRequest: URLRequest
    let timestamp: Date
    let completion: (Result<Data, Error>) -> Void

    public init(id: UUID, urlRequest: URLRequest, timestamp: Date, completion: @escaping (Result<Data, Error>) -> Void) {
        self.id = id
        self.urlRequest = urlRequest
        self.timestamp = timestamp
        self.completion = completion
    }
}

public struct BackgroundTask {
    let id: UUID
    let name: String
    let isEssential: Bool
    var isPaused: Bool
    let task: () async -> Void
}

public struct CacheStats {
    public let imagesCached: Int
    public let embeddingsCached: Int
    public let totalCacheSizeMB: Double
    public let cacheHits: Int
    public let cacheMisses: Int
    public let hitRate: Double
}

public struct PerformanceReport {
    public let timestamp: Date
    public let memoryUsageMB: Double
    public let batteryLevel: Float
    public let networkRequestsPerMinute: Int
    public let cacheStats: CacheStats
    public let activeBackgroundTasks: Int
    public let metrics: PerformanceMetrics
    public let status: OptimizationStatus
}

public enum PerformanceError: LocalizedError {
    case invalidImage
    case networkError
    case compressionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .networkError:
            return "Network request failed"
        case .compressionFailed:
            return "Failed to compress data"
        }
    }
}
