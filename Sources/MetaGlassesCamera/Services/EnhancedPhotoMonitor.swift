import Foundation
import Photos
import UIKit

/// Enhanced Photo Library Monitoring System
/// Detects new photos from Meta Ray-Ban glasses and triggers automatic AI analysis
@MainActor
public class EnhancedPhotoMonitor: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = EnhancedPhotoMonitor()

    // MARK: - Published Properties
    @Published public var latestGlassesPhoto: UIImage?
    @Published public var photoMetadata: PhotoMetadata?
    @Published public var isMonitoring = false
    @Published public var detectedPhotosCount = 0

    // MARK: - Properties
    private var photoLibraryObserverToken: NSObjectProtocol?
    private var lastProcessedAssetIdentifier: String?
    private let photoQueue = DispatchQueue(label: "com.metaglasses.photomonitor", qos: .userInitiated)

    // Callbacks
    public var onNewPhoto: ((UIImage, PhotoMetadata) -> Void)?
    public var onAnalysisComplete: ((String) -> Void)?

    // MARK: - Initialization
    override init() {
        super.init()
        print("📸 EnhancedPhotoMonitor initialized")
    }

    // MARK: - Public Methods

    /// Start monitoring photo library for new glasses photos
    public func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ Photo monitoring already active")
            return
        }

        // Register for photo library changes
        PHPhotoLibrary.shared().register(self)
        isMonitoring = true

        print("✅ Photo monitoring started")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isMonitoring = false

        print("⏹ Photo monitoring stopped")
    }

    /// Manually check for new photos
    public func checkForNewPhotos() async {
        print("🔍 Checking for new photos from glasses...")

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 5

        // Look for recent photos (last 30 seconds)
        let recentDate = Date().addingTimeInterval(-30)
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", recentDate as NSDate)

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        for i in 0..<assets.count {
            let asset = assets.object(at: i)

            // Skip if already processed
            if lastProcessedAssetIdentifier == asset.localIdentifier {
                continue
            }

            // Check if photo is from Meta View app
            if await isPhotoFromMetaGlasses(asset) {
                await processGlassesPhoto(asset)
                break // Process one at a time
            }
        }
    }

    /// Check if asset is from Meta Ray-Ban glasses
    private func isPhotoFromMetaGlasses(_ asset: PHAsset) async -> Bool {
        // Check 1: Creation source
        if let sourceType = asset.sourceType, sourceType == .typeUserLibrary {
            // Could be from Meta View app import
        }

        // Check 2: Check for Meta-specific metadata
        if let metadata = await extractMetadata(from: asset) {
            // Check if camera model or software contains "Meta" or "Ray-Ban"
            if let cameraModel = metadata.cameraModel?.lowercased() {
                if cameraModel.contains("meta") || cameraModel.contains("ray-ban") {
                    return true
                }
            }

            if let software = metadata.software?.lowercased() {
                if software.contains("meta") || software.contains("view") {
                    return true
                }
            }
        }

        // Check 3: Aspect ratio (Meta glasses have specific aspect ratio)
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        let aspectRatio = Double(width) / Double(height)

        // Meta Ray-Ban photos are typically 16:9 or similar
        if abs(aspectRatio - 1.777) < 0.1 { // 16:9 ≈ 1.777
            return true
        }

        // Check 4: File size patterns (Meta photos have characteristic sizes)
        // Meta glasses typically produce ~3-5MB photos
        // This would require fetching resource info

        return false
    }

    /// Process a photo from Meta glasses
    private func processGlassesPhoto(_ asset: PHAsset) async {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            manager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard let self = self, let image = image else {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    // Extract metadata
                    let metadata = await self.extractMetadata(from: asset)

                    // Update state
                    self.latestGlassesPhoto = image
                    self.photoMetadata = metadata
                    self.lastProcessedAssetIdentifier = asset.localIdentifier
                    self.detectedPhotosCount += 1

                    print("✅ New glasses photo detected: \(asset.localIdentifier)")

                    // Trigger callback
                    if let metadata = metadata {
                        self.onNewPhoto?(image, metadata)
                    }

                    // Trigger automatic AI analysis
                    await self.performAutomaticAnalysis(image, metadata: metadata)

                    continuation.resume()
                }
            }
        }
    }

    /// Extract comprehensive metadata from photo asset
    private func extractMetadata(from asset: PHAsset) async -> PhotoMetadata? {
        let resources = PHAssetResource.assetResources(for: asset)
        var metadata = PhotoMetadata()

        metadata.creationDate = asset.creationDate
        metadata.location = asset.location
        metadata.pixelWidth = asset.pixelWidth
        metadata.pixelHeight = asset.pixelHeight
        metadata.isFavorite = asset.isFavorite

        // Get EXIF data from image resource
        if let resource = resources.first {
            metadata.filename = resource.originalFilename

            // Request image data to get EXIF
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat

            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in
                    if let data = data,
                       let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {

                        // Extract EXIF
                        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                            metadata.iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int]
                            metadata.exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double
                            metadata.fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double
                            metadata.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
                        }

                        // Extract TIFF
                        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                            metadata.cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
                            metadata.software = tiff[kCGImagePropertyTIFFSoftware as String] as? String
                        }

                        // Extract GPS
                        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
                               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
                                metadata.gpsLatitude = lat
                                metadata.gpsLongitude = lon
                            }
                        }
                    }

                    continuation.resume(returning: metadata)
                }
            }
        }

        return metadata
    }

    /// Perform automatic AI analysis on new photo
    private func performAutomaticAnalysis(_ image: UIImage, metadata: PhotoMetadata?) async {
        print("🤖 Starting automatic AI analysis...")

        // Use OpenAI Vision for analysis
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        let base64String = imageData.base64EncodedString()

        do {
            // Build analysis prompt with context
            var prompt = "Analyze this photo taken with Meta Ray-Ban smart glasses. Describe:"
            prompt += "\n- Main subjects and objects"
            prompt += "\n- Scene context and setting"
            prompt += "\n- Any text visible"
            prompt += "\n- Notable details"

            if let metadata = metadata, let location = metadata.location {
                prompt += "\n- This photo was taken at coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)"
            }

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer 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", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "model": "gpt-4-vision-preview",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]]
                        ]
                    ]
                ],
                "max_tokens": 500
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {

                print("✅ AI Analysis complete:")
                print(content)

                // Trigger callback
                onAnalysisComplete?(content)
            }
        } catch {
            print("❌ AI analysis failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension EnhancedPhotoMonitor: PHPhotoLibraryChangeObserver {
    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            print("📸 Photo library changed - checking for new glasses photos...")
            await checkForNewPhotos()
        }
    }
}

// MARK: - PhotoMetadata
public struct PhotoMetadata {
    public var creationDate: Date?
    public var location: CLLocation?
    public var pixelWidth: Int = 0
    public var pixelHeight: Int = 0
    public var isFavorite: Bool = false
    public var filename: String?

    // EXIF data
    public var cameraModel: String?
    public var software: String?
    public var iso: [Int]?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var focalLength: Double?

    // GPS data
    public var gpsLatitude: Double?
    public var gpsLongitude: Double?

    public init() {}
}
