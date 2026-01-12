import Foundation
import ARKit
import RealityKit
import MetalKit
import ModelIO
import SceneKit.ModelIO
import Combine
import simd

// MARK: - Real-time 3D Reconstruction System
/// Advanced 3D reconstruction using LiDAR, photogrammetry, and mesh generation
@MainActor
public class RealTime3DReconstruction: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published public var isRecording = false
    @Published public var reconstructionProgress: Float = 0
    @Published public var currentMesh: ReconstructedMesh?
    @Published public var meshQualityMetrics: MeshQualityMetrics?
    @Published public var availableMeshes: [ReconstructedMesh] = []

    // MARK: - Private Properties
    private var arSession: ARSession
    private var sceneReconstruction: ARSceneReconstruction = .mesh
    private var metalDevice: MTLDevice?
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var capturedFrames: [CapturedFrame] = []
    private var pointCloud: PointCloud?

    // LiDAR support
    private var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // Mesh export
    private var mdlAsset: MDLAsset?

    // MARK: - Data Models

    public struct ReconstructedMesh: Identifiable {
        public let id: UUID
        public let name: String
        public let vertices: [SIMD3<Float>]
        public let normals: [SIMD3<Float>]
        public let triangles: [UInt32]
        public let textureCoordinates: [SIMD2<Float>]?
        public let boundingBox: BoundingBox
        public let creationDate: Date
        public var exportURL: URL?

        public var vertexCount: Int { vertices.count }
        public var triangleCount: Int { triangles.count / 3 }

        public init(
            id: UUID = UUID(),
            name: String,
            vertices: [SIMD3<Float>],
            normals: [SIMD3<Float>],
            triangles: [UInt32],
            textureCoordinates: [SIMD2<Float>]? = nil,
            boundingBox: BoundingBox
        ) {
            self.id = id
            self.name = name
            self.vertices = vertices
            self.normals = normals
            self.triangles = triangles
            self.textureCoordinates = textureCoordinates
            self.boundingBox = boundingBox
            self.creationDate = Date()
            self.exportURL = nil
        }
    }

    public struct BoundingBox {
        public let min: SIMD3<Float>
        public let max: SIMD3<Float>

        public var size: SIMD3<Float> {
            max - min
        }

        public var center: SIMD3<Float> {
            (min + max) / 2
        }

        public var volume: Float {
            let s = size
            return s.x * s.y * s.z
        }
    }

    public struct MeshQualityMetrics {
        public let vertexCount: Int
        public let triangleCount: Int
        public let surfaceArea: Float
        public let volume: Float
        public let meshDensity: Float
        public let averageEdgeLength: Float
        public let hasTexture: Bool
        public let reconstructionMethod: ReconstructionMethod

        public enum ReconstructionMethod: String {
            case lidar = "LiDAR"
            case photogrammetry = "Photogrammetry"
            case hybrid = "Hybrid"
        }
    }

    private struct CapturedFrame {
        let camera: ARCamera
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let timestamp: TimeInterval
        let transform: simd_float4x4
    }

    private struct PointCloud {
        var points: [SIMD3<Float>]
        var colors: [SIMD3<Float>]
        var normals: [SIMD3<Float>]

        mutating func addPoint(_ point: SIMD3<Float>, color: SIMD3<Float>, normal: SIMD3<Float>) {
            points.append(point)
            colors.append(color)
            normals.append(normal)
        }

        func downsample(factor: Int) -> PointCloud {
            var downsampled = PointCloud(points: [], colors: [], normals: [])
            for i in stride(from: 0, to: points.count, by: factor) {
                downsampled.points.append(points[i])
                downsampled.colors.append(colors[i])
                downsampled.normals.append(normals[i])
            }
            return downsampled
        }
    }

    // MARK: - Initialization

    public init(arSession: ARSession) {
        self.arSession = arSession
        self.metalDevice = MTLCreateSystemDefaultDevice()
        super.init()
        configureMeshReconstruction()
    }

    private func configureMeshReconstruction() {
        guard hasLiDAR else {
            print("⚠️ LiDAR not available - using photogrammetry fallback")
            return
        }

        // Enable mesh reconstruction in AR session
        if let config = arSession.configuration as? ARWorldTrackingConfiguration {
            config.sceneReconstruction = .mesh
            arSession.run(config)
            print("✅ LiDAR mesh reconstruction enabled")
        }
    }

    // MARK: - Recording Control

    public func startRecording(name: String = "Reconstruction") {
        isRecording = true
        capturedFrames.removeAll()
        meshAnchors.removeAll()
        pointCloud = PointCloud(points: [], colors: [], normals: [])
        reconstructionProgress = 0

        currentMesh = ReconstructedMesh(
            name: name,
            vertices: [],
            normals: [],
            triangles: [],
            boundingBox: BoundingBox(min: SIMD3<Float>(0, 0, 0), max: SIMD3<Float>(0, 0, 0))
        )

        arSession.delegate = self
        print("🎬 Started 3D reconstruction recording: \(name)")
    }

    public func stopRecording() {
        isRecording = false
        arSession.delegate = nil

        // Process captured data
        Task {
            await processReconstruction()
        }

        print("⏹️ Stopped 3D reconstruction recording")
    }

    // MARK: - LiDAR Mesh Processing

    private func processMeshAnchor(_ meshAnchor: ARMeshAnchor) {
        let geometry = meshAnchor.geometry

        // Extract vertices
        let vertexCount = geometry.vertices.count
        let vertexBuffer = geometry.vertices.buffer
        let vertexPointer = vertexBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
        let vertices = Array(UnsafeBufferPointer(start: vertexPointer, count: vertexCount))

        // Extract normals
        let normalBuffer = geometry.normals.buffer
        let normalPointer = normalBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
        let normals = Array(UnsafeBufferPointer(start: normalPointer, count: vertexCount))

        // Extract triangles
        let faceCount = geometry.faces.count
        let indexBuffer = geometry.faces.buffer
        let indexPointer = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: faceCount * 3)
        let triangles = Array(UnsafeBufferPointer(start: indexPointer, count: faceCount * 3))

        // Transform vertices to world space
        let worldTransform = meshAnchor.transform
        let worldVertices = vertices.map { vertex -> SIMD3<Float> in
            let worldPos = worldTransform * simd_float4(vertex.x, vertex.y, vertex.z, 1.0)
            return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
        }

        // Transform normals
        let normalMatrix = simd_float3x3(worldTransform.columns.0.xyz, worldTransform.columns.1.xyz, worldTransform.columns.2.xyz)
        let worldNormals = normals.map { normal in
            normalize(normalMatrix * normal)
        }

        // Calculate bounding box
        let boundingBox = calculateBoundingBox(vertices: worldVertices)

        // Update current mesh
        if var mesh = currentMesh {
            mesh = ReconstructedMesh(
                id: mesh.id,
                name: mesh.name,
                vertices: worldVertices,
                normals: worldNormals,
                triangles: triangles,
                textureCoordinates: mesh.textureCoordinates,
                boundingBox: boundingBox
            )
            currentMesh = mesh

            // Update quality metrics
            updateQualityMetrics(mesh: mesh, method: .lidar)
        }

        meshAnchors[meshAnchor.identifier] = meshAnchor
    }

    // MARK: - Photogrammetry Processing

    private func processReconstruction() async {
        guard capturedFrames.count > 10 else {
            print("⚠️ Not enough frames for reconstruction (need at least 10)")
            return
        }

        reconstructionProgress = 0.1

        // Build point cloud from depth data
        if let pointCloud = await buildPointCloudFromFrames() {
            self.pointCloud = pointCloud
            reconstructionProgress = 0.4
        }

        // Generate mesh from point cloud
        if let mesh = await generateMeshFromPointCloud() {
            currentMesh = mesh
            availableMeshes.append(mesh)
            reconstructionProgress = 0.8
        }

        // Calculate quality metrics
        if let mesh = currentMesh {
            updateQualityMetrics(mesh: mesh, method: hasLiDAR ? .hybrid : .photogrammetry)
        }

        reconstructionProgress = 1.0
        print("✅ 3D reconstruction complete")
    }

    private func buildPointCloudFromFrames() async -> PointCloud? {
        var cloud = PointCloud(points: [], colors: [], normals: [])

        for frame in capturedFrames {
            guard let depthData = frame.depth else { continue }

            // Process depth map
            let width = CVPixelBufferGetWidth(depthData)
            let height = CVPixelBufferGetHeight(depthData)

            CVPixelBufferLockBaseAddress(depthData, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthData, .readOnly) }

            guard let depthPointer = CVPixelBufferGetBaseAddress(depthData)?.assumingMemoryBound(to: Float32.self) else {
                continue
            }

            // Sample every 10th pixel for performance
            for y in stride(from: 0, to: height, by: 10) {
                for x in stride(from: 0, to: width, by: 10) {
                    let index = y * width + x
                    let depth = depthPointer[index]

                    guard depth > 0 && depth < 10.0 else { continue } // Filter invalid depths

                    // Convert pixel to 3D point
                    let point = unprojectPixel(x: Float(x), y: Float(y), depth: depth, camera: frame.camera)
                    let worldPoint = frame.transform * simd_float4(point.x, point.y, point.z, 1.0)

                    cloud.addPoint(
                        SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
                        color: SIMD3<Float>(0.7, 0.7, 0.7), // Default gray
                        normal: SIMD3<Float>(0, 1, 0) // Default up
                    )
                }
            }
        }

        print("📊 Built point cloud with \(cloud.points.count) points")
        return cloud.points.isEmpty ? nil : cloud
    }

    private func unprojectPixel(x: Float, y: Float, depth: Float, camera: ARCamera) -> SIMD3<Float> {
        let intrinsics = camera.intrinsics
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y

        let pointX = (x - cx) * depth / fx
        let pointY = (y - cy) * depth / fy
        let pointZ = depth

        return SIMD3<Float>(pointX, pointY, pointZ)
    }

    private func generateMeshFromPointCloud() async -> ReconstructedMesh? {
        guard let cloud = pointCloud, cloud.points.count > 100 else {
            return nil
        }

        // Simple mesh generation using convex hull approach
        // In production, use Poisson surface reconstruction or similar
        let (vertices, triangles) = await generateSimpleMesh(from: cloud)

        // Calculate normals
        let normals = calculateVertexNormals(vertices: vertices, triangles: triangles)

        // Calculate bounding box
        let boundingBox = calculateBoundingBox(vertices: vertices)

        let mesh = ReconstructedMesh(
            name: currentMesh?.name ?? "Reconstruction",
            vertices: vertices,
            normals: normals,
            triangles: triangles,
            boundingBox: boundingBox
        )

        print("🔷 Generated mesh: \(mesh.vertexCount) vertices, \(mesh.triangleCount) triangles")
        return mesh
    }

    private func generateSimpleMesh(from cloud: PointCloud) async -> ([SIMD3<Float>], [UInt32]) {
        // Downsample for performance
        let downsampled = cloud.downsample(factor: 5)

        // Use Delaunay triangulation or similar
        // For now, return a simplified mesh
        let vertices = downsampled.points
        var triangles: [UInt32] = []

        // Create simple triangle mesh (placeholder - use proper meshing algorithm in production)
        for i in stride(from: 0, to: vertices.count - 2, by: 3) {
            triangles.append(UInt32(i))
            triangles.append(UInt32(i + 1))
            triangles.append(UInt32(i + 2))
        }

        return (vertices, triangles)
    }

    private func calculateVertexNormals(vertices: [SIMD3<Float>], triangles: [UInt32]) -> [SIMD3<Float>] {
        var normals = Array(repeating: SIMD3<Float>(0, 0, 0), count: vertices.count)
        var counts = Array(repeating: 0, count: vertices.count)

        // Calculate face normals and accumulate
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let i0 = Int(triangles[i])
            let i1 = Int(triangles[i + 1])
            let i2 = Int(triangles[i + 2])

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let faceNormal = normalize(cross(edge1, edge2))

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal

            counts[i0] += 1
            counts[i1] += 1
            counts[i2] += 1
        }

        // Average and normalize
        for i in 0..<normals.count {
            if counts[i] > 0 {
                normals[i] = normalize(normals[i] / Float(counts[i]))
            } else {
                normals[i] = SIMD3<Float>(0, 1, 0) // Default up
            }
        }

        return normals
    }

    private func calculateBoundingBox(vertices: [SIMD3<Float>]) -> BoundingBox {
        guard !vertices.isEmpty else {
            return BoundingBox(min: SIMD3<Float>(0, 0, 0), max: SIMD3<Float>(0, 0, 0))
        }

        var minPoint = vertices[0]
        var maxPoint = vertices[0]

        for vertex in vertices {
            minPoint = simd_min(minPoint, vertex)
            maxPoint = simd_max(maxPoint, vertex)
        }

        return BoundingBox(min: minPoint, max: maxPoint)
    }

    // MARK: - Quality Metrics

    private func updateQualityMetrics(mesh: ReconstructedMesh, method: MeshQualityMetrics.ReconstructionMethod) {
        let surfaceArea = calculateSurfaceArea(vertices: mesh.vertices, triangles: mesh.triangles)
        let volume = mesh.boundingBox.volume
        let meshDensity = Float(mesh.vertexCount) / volume
        let averageEdgeLength = calculateAverageEdgeLength(vertices: mesh.vertices, triangles: mesh.triangles)

        meshQualityMetrics = MeshQualityMetrics(
            vertexCount: mesh.vertexCount,
            triangleCount: mesh.triangleCount,
            surfaceArea: surfaceArea,
            volume: volume,
            meshDensity: meshDensity,
            averageEdgeLength: averageEdgeLength,
            hasTexture: mesh.textureCoordinates != nil,
            reconstructionMethod: method
        )
    }

    private func calculateSurfaceArea(vertices: [SIMD3<Float>], triangles: [UInt32]) -> Float {
        var area: Float = 0

        for i in stride(from: 0, to: triangles.count, by: 3) {
            let v0 = vertices[Int(triangles[i])]
            let v1 = vertices[Int(triangles[i + 1])]
            let v2 = vertices[Int(triangles[i + 2])]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let crossProduct = cross(edge1, edge2)
            area += simd_length(crossProduct) * 0.5
        }

        return area
    }

    private func calculateAverageEdgeLength(vertices: [SIMD3<Float>], triangles: [UInt32]) -> Float {
        var totalLength: Float = 0
        var edgeCount = 0

        for i in stride(from: 0, to: triangles.count, by: 3) {
            let v0 = vertices[Int(triangles[i])]
            let v1 = vertices[Int(triangles[i + 1])]
            let v2 = vertices[Int(triangles[i + 2])]

            totalLength += simd_distance(v0, v1)
            totalLength += simd_distance(v1, v2)
            totalLength += simd_distance(v2, v0)
            edgeCount += 3
        }

        return edgeCount > 0 ? totalLength / Float(edgeCount) : 0
    }

    // MARK: - Export

    public func exportToUSDZ(mesh: ReconstructedMesh, filename: String) async throws -> URL {
        let asset = MDLAsset()

        // Create MDL mesh
        let allocator = MTKMeshBufferAllocator(device: metalDevice!)

        // Create vertex buffer
        let vertexData = Data(bytes: mesh.vertices, count: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.size)
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Create index buffer
        let indexData = Data(bytes: mesh.triangles, count: mesh.triangles.count * MemoryLayout<UInt32>.size)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        // Create MDL submesh
        let mdlSubmesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: mesh.triangles.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Create MDL mesh
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: mesh.vertices.count,
            descriptor: createVertexDescriptor(),
            submeshes: [mdlSubmesh]
        )

        asset.add(mdlMesh)

        // Export to USDZ
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportURL = documentsURL.appendingPathComponent("\(filename).usdz")

        try asset.export(to: exportURL)

        print("📦 Exported mesh to USDZ: \(exportURL.path)")
        return exportURL
    }

    public func exportToGLB(mesh: ReconstructedMesh, filename: String) async throws -> URL {
        // GLB export would use a GLB encoder library
        // For now, export as OBJ format
        return try await exportToOBJ(mesh: mesh, filename: filename)
    }

    private func exportToOBJ(mesh: ReconstructedMesh, filename: String) async throws -> URL {
        var objContent = "# MetaGlasses 3D Reconstruction\n"
        objContent += "# Vertices: \(mesh.vertexCount)\n"
        objContent += "# Triangles: \(mesh.triangleCount)\n\n"

        // Write vertices
        for vertex in mesh.vertices {
            objContent += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }

        // Write normals
        for normal in mesh.normals {
            objContent += "vn \(normal.x) \(normal.y) \(normal.z)\n"
        }

        // Write faces
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let i0 = mesh.triangles[i] + 1
            let i1 = mesh.triangles[i + 1] + 1
            let i2 = mesh.triangles[i + 2] + 1
            objContent += "f \(i0)//\(i0) \(i1)//\(i1) \(i2)//\(i2)\n"
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportURL = documentsURL.appendingPathComponent("\(filename).obj")

        try objContent.write(to: exportURL, atomically: true, encoding: .utf8)

        print("📦 Exported mesh to OBJ: \(exportURL.path)")
        return exportURL
    }

    private func createVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()

        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )

        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)

        return descriptor
    }
}

// MARK: - ARSessionDelegate

extension RealTime3DReconstruction: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording else { return }

        // Capture frame data
        let capturedFrame = CapturedFrame(
            camera: frame.camera,
            image: frame.capturedImage,
            depth: frame.sceneDepth?.depthMap,
            timestamp: frame.timestamp,
            transform: frame.camera.transform
        )

        capturedFrames.append(capturedFrame)

        // Update progress
        reconstructionProgress = min(Float(capturedFrames.count) / 100.0, 0.9)
    }

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }
}

// MARK: - SIMD Extensions

extension simd_float4 {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
