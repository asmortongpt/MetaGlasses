import Foundation
import ARKit
import RealityKit
import Combine
import SwiftUI
import CoreLocation
import simd

// MARK: - ARKit Integration System
/// Comprehensive ARKit integration for world tracking, plane detection, and spatial anchoring
@MainActor
public class ARKitIntegration: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published public var isARSessionActive = false
    @Published public var detectedPlanes: [DetectedPlane] = []
    @Published public var spatialAnchors: [SpatialAnchor] = []
    @Published public var trackingState: ARCamera.TrackingState = .notAvailable
    @Published public var sessionError: String?

    // MARK: - Private Properties
    private var arSession: ARSession
    private var arConfiguration: ARWorldTrackingConfiguration
    private var planeAnchors: [UUID: DetectedPlane] = [:]
    private var photoAnchors: [UUID: PhotoSpatialAnchor] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Performance tracking
    private var frameCount: Int = 0
    private var lastFrameTime: TimeInterval = 0

    // MARK: - Data Models

    public struct DetectedPlane: Identifiable {
        public let id: UUID
        public let anchor: ARPlaneAnchor
        public let extent: simd_float3
        public let center: simd_float3
        public let transform: simd_float4x4
        public let classification: ARPlaneAnchor.Classification
        public let alignment: ARPlaneAnchor.Alignment

        public var area: Float {
            extent.x * extent.z
        }

        public var isLargeEnough: Bool {
            area > 0.5 // 0.5 square meters minimum
        }
    }

    public struct SpatialAnchor: Identifiable, Codable {
        public let id: UUID
        public let name: String
        public let transform: CodableTransform
        public let timestamp: Date
        public var metadata: [String: String]

        public init(id: UUID = UUID(), name: String, transform: simd_float4x4, metadata: [String: String] = [:]) {
            self.id = id
            self.name = name
            self.transform = CodableTransform(transform: transform)
            self.timestamp = Date()
            self.metadata = metadata
        }
    }

    public struct PhotoSpatialAnchor: Identifiable {
        public let id: UUID
        public let photoID: String
        public let anchor: ARAnchor
        public let captureLocation: simd_float3
        public let captureTime: Date
        public var thumbnailImage: UIImage?

        public init(photoID: String, anchor: ARAnchor, captureLocation: simd_float3, thumbnailImage: UIImage? = nil) {
            self.id = UUID()
            self.photoID = photoID
            self.anchor = anchor
            self.captureLocation = captureLocation
            self.captureTime = Date()
            self.thumbnailImage = thumbnailImage
        }
    }

    public struct CodableTransform: Codable {
        public let columns: [[Float]]

        public init(transform: simd_float4x4) {
            self.columns = [
                [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w],
                [transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w],
                [transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w],
                [transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
            ]
        }

        public var simdTransform: simd_float4x4 {
            simd_float4x4(
                SIMD4<Float>(columns[0][0], columns[0][1], columns[0][2], columns[0][3]),
                SIMD4<Float>(columns[1][0], columns[1][1], columns[1][2], columns[1][3]),
                SIMD4<Float>(columns[2][0], columns[2][1], columns[2][2], columns[2][3]),
                SIMD4<Float>(columns[3][0], columns[3][1], columns[3][2], columns[3][3])
            )
        }
    }

    // MARK: - Initialization

    public override init() {
        self.arSession = ARSession()
        self.arConfiguration = ARWorldTrackingConfiguration()
        super.init()
        configureARSession()
    }

    // MARK: - AR Session Configuration

    private func configureARSession() {
        // Configure world tracking with optimal settings
        arConfiguration.worldAlignment = .gravityAndHeading
        arConfiguration.planeDetection = [.horizontal, .vertical]

        // Enable scene reconstruction if available (LiDAR devices)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            arConfiguration.sceneReconstruction = .mesh
        }

        // Enable environment texturing for realistic rendering
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            arConfiguration.frameSemantics.insert(.sceneDepth)
        }

        // Enable people occlusion if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            arConfiguration.frameSemantics.insert(.personSegmentationWithDepth)
        }

        // Set AR session delegate
        arSession.delegate = self
    }

    // MARK: - Session Management

    public func startARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            sessionError = "ARKit World Tracking is not supported on this device"
            return
        }

        arSession.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])
        isARSessionActive = true
        sessionError = nil
        print("✅ ARKit session started with world tracking")
    }

    public func pauseARSession() {
        arSession.pause()
        isARSessionActive = false
        print("⏸️ ARKit session paused")
    }

    public func resetARSession() {
        arSession.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])
        planeAnchors.removeAll()
        photoAnchors.removeAll()
        detectedPlanes.removeAll()
        spatialAnchors.removeAll()
        print("🔄 ARKit session reset")
    }

    // MARK: - Plane Detection

    public func getBestPlaneForPlacement() -> DetectedPlane? {
        return detectedPlanes
            .filter { $0.isLargeEnough }
            .max { $0.area < $1.area }
    }

    public func getPlanesNearPoint(_ point: simd_float3, radius: Float = 1.0) -> [DetectedPlane] {
        return detectedPlanes.filter { plane in
            let distance = simd_distance(plane.center, point)
            return distance <= radius
        }
    }

    // MARK: - Object Anchoring

    public func placeObjectAnchor(name: String, at transform: simd_float4x4, metadata: [String: String] = [:]) -> SpatialAnchor? {
        let anchor = ARAnchor(name: name, transform: transform)
        arSession.add(anchor: anchor)

        let spatialAnchor = SpatialAnchor(name: name, transform: transform, metadata: metadata)
        spatialAnchors.append(spatialAnchor)

        print("📍 Placed object anchor: \(name)")
        return spatialAnchor
    }

    public func removeAnchor(id: UUID) {
        guard let index = spatialAnchors.firstIndex(where: { $0.id == id }) else { return }
        spatialAnchors.remove(at: index)

        // Remove from AR session
        if let anchor = arSession.currentFrame?.anchors.first(where: { $0.identifier == id }) {
            arSession.remove(anchor: anchor)
        }

        print("🗑️ Removed anchor: \(id)")
    }

    // MARK: - Photo Placement in AR Space

    public func placePhotoInSpace(photoID: String, at position: simd_float3, thumbnailImage: UIImage? = nil) -> PhotoSpatialAnchor? {
        let cameraTransform = arSession.currentFrame?.camera.transform ?? matrix_identity_float4x4

        // Create transform for photo placement
        var transform = matrix_identity_float4x4
        transform.columns.3 = simd_float4(position.x, position.y, position.z, 1.0)

        // Orient towards camera
        let toCamera = normalize(cameraTransform.columns.3.xyz - position)
        let right = normalize(cross(simd_float3(0, 1, 0), toCamera))
        let up = cross(toCamera, right)

        transform.columns.0 = simd_float4(right, 0)
        transform.columns.1 = simd_float4(up, 0)
        transform.columns.2 = simd_float4(toCamera, 0)

        let anchor = ARAnchor(name: "photo_\(photoID)", transform: transform)
        arSession.add(anchor: anchor)

        let photoAnchor = PhotoSpatialAnchor(
            photoID: photoID,
            anchor: anchor,
            captureLocation: position,
            thumbnailImage: thumbnailImage
        )

        photoAnchors[anchor.identifier] = photoAnchor

        print("📸 Placed photo anchor at \(position)")
        return photoAnchor
    }

    // MARK: - AR Photo Gallery

    public func createPhotoGallery(photos: [(id: String, thumbnail: UIImage)], centerPosition: simd_float3, radius: Float = 2.0) {
        let count = photos.count
        guard count > 0 else { return }

        let angleStep = (2 * Float.pi) / Float(count)

        for (index, photo) in photos.enumerated() {
            let angle = Float(index) * angleStep
            let x = centerPosition.x + radius * cos(angle)
            let z = centerPosition.z + radius * sin(angle)
            let y = centerPosition.y + Float.random(in: -0.5...0.5) // Slight vertical variation

            let position = simd_float3(x, y, z)
            _ = placePhotoInSpace(photoID: photo.id, at: position, thumbnailImage: photo.thumbnail)
        }

        print("🖼️ Created photo gallery with \(count) photos")
    }

    public func getPhotosNearPosition(_ position: simd_float3, radius: Float = 2.0) -> [PhotoSpatialAnchor] {
        return photoAnchors.values.filter { photoAnchor in
            let distance = simd_distance(photoAnchor.captureLocation, position)
            return distance <= radius
        }
    }

    // MARK: - Spatial Queries

    public func raycast(from screenPoint: CGPoint, viewportSize: CGSize) -> ARRaycastResult? {
        guard let frame = arSession.currentFrame else { return nil }

        // Normalize screen coordinates
        let normalizedPoint = CGPoint(
            x: screenPoint.x / viewportSize.width,
            y: screenPoint.y / viewportSize.height
        )

        let raycastQuery = ARRaycastQuery(
            origin: frame.camera.transform.columns.3.xyz,
            direction: frame.camera.transform.columns.2.xyz,
            allowing: .existingPlaneGeometry,
            alignment: .any
        )

        let results = arSession.raycast(raycastQuery)
        return results.first
    }

    public func hitTest(from screenPoint: CGPoint, viewportSize: CGSize) -> [ARHitTestResult] {
        guard let frame = arSession.currentFrame else { return [] }

        return frame.hitTest(screenPoint, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
    }

    // MARK: - Camera Information

    public func getCurrentCameraTransform() -> simd_float4x4? {
        return arSession.currentFrame?.camera.transform
    }

    public func getCurrentCameraPosition() -> simd_float3? {
        return arSession.currentFrame?.camera.transform.columns.3.xyz
    }

    public func getCurrentCameraDirection() -> simd_float3? {
        guard let transform = arSession.currentFrame?.camera.transform else { return nil }
        return -transform.columns.2.xyz // Negative Z is forward
    }

    // MARK: - Performance Metrics

    public func getPerformanceMetrics() -> ARPerformanceMetrics {
        guard let frame = arSession.currentFrame else {
            return ARPerformanceMetrics(fps: 0, trackingQuality: .notAvailable, planeCount: 0, anchorCount: 0)
        }

        let currentTime = frame.timestamp
        let fps = lastFrameTime > 0 ? 1.0 / (currentTime - lastFrameTime) : 0
        lastFrameTime = currentTime

        return ARPerformanceMetrics(
            fps: fps,
            trackingQuality: frame.camera.trackingState,
            planeCount: detectedPlanes.count,
            anchorCount: spatialAnchors.count + photoAnchors.count
        )
    }

    public struct ARPerformanceMetrics {
        public let fps: Double
        public let trackingQuality: ARCamera.TrackingState
        public let planeCount: Int
        public let anchorCount: Int
    }

    // MARK: - Cleanup

    deinit {
        pauseARSession()
        cancellables.forEach { $0.cancel() }
    }
}

// MARK: - ARSessionDelegate

extension ARKitIntegration: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        trackingState = frame.camera.trackingState

        // Update tracking quality every 30 frames
        if frameCount % 30 == 0 {
            switch frame.camera.trackingState {
            case .normal:
                sessionError = nil
            case .limited(let reason):
                sessionError = "Limited tracking: \(reason)"
            case .notAvailable:
                sessionError = "Tracking not available"
            }
        }
    }

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let detectedPlane = DetectedPlane(
                    id: planeAnchor.identifier,
                    anchor: planeAnchor,
                    extent: planeAnchor.planeExtent.width > 0 ? simd_float3(planeAnchor.planeExtent.width, 0, planeAnchor.planeExtent.height) : simd_float3(0.5, 0, 0.5),
                    center: planeAnchor.center,
                    transform: planeAnchor.transform,
                    classification: planeAnchor.classification,
                    alignment: planeAnchor.alignment
                )

                planeAnchors[planeAnchor.identifier] = detectedPlane
                detectedPlanes = Array(planeAnchors.values)
            }
        }
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let detectedPlane = DetectedPlane(
                    id: planeAnchor.identifier,
                    anchor: planeAnchor,
                    extent: planeAnchor.planeExtent.width > 0 ? simd_float3(planeAnchor.planeExtent.width, 0, planeAnchor.planeExtent.height) : simd_float3(0.5, 0, 0.5),
                    center: planeAnchor.center,
                    transform: planeAnchor.transform,
                    classification: planeAnchor.classification,
                    alignment: planeAnchor.alignment
                )

                planeAnchors[planeAnchor.identifier] = detectedPlane
                detectedPlanes = Array(planeAnchors.values)
            }
        }
    }

    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            planeAnchors.removeValue(forKey: anchor.identifier)
            photoAnchors.removeValue(forKey: anchor.identifier)
        }
        detectedPlanes = Array(planeAnchors.values)
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        sessionError = "AR Session error: \(error.localizedDescription)"
        print("❌ AR Session error: \(error)")
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        isARSessionActive = false
        sessionError = "AR session was interrupted"
        print("⚠️ AR session interrupted")
    }

    public func sessionInterruptionEnded(_ session: ARSession) {
        isARSessionActive = true
        sessionError = nil
        print("✅ AR session interruption ended")
        resetARSession()
    }
}

// MARK: - SIMD Extensions

extension simd_float4 {
    var xyz: simd_float3 {
        simd_float3(x, y, z)
    }
}

extension simd_float4x4 {
    var position: simd_float3 {
        columns.3.xyz
    }
}
