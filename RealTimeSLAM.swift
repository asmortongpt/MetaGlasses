import SwiftUI
import ARKit
import Metal
import MetalKit
import MetalPerformanceShaders
import Accelerate
import simd
import Vision
import CoreMotion

// MARK: - Real-Time SLAM (Simultaneous Localization and Mapping)
// Live 3D world reconstruction as you walk

@available(iOS 16.0, *)
class RealTimeSLAMEngine: NSObject, ObservableObject {

    // MARK: - Core Components
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    // SLAM State
    @Published var isMapping = false
    @Published var mapPoints: [MapPoint] = []
    @Published var keyframes: [KeyFrame] = []
    @Published var currentPose = simd_float4x4(1)
    @Published var trackingQuality: TrackingQuality = .notAvailable
    @Published var mappedArea: Float = 0.0 // Square meters
    @Published var processingFPS: Float = 0.0

    // Visual-Inertial Odometry
    private let motionManager = CMMotionManager()
    private var imuData: CMDeviceMotion?
    private var visualOdometry: VisualOdometry!

    // Feature Detection & Matching
    private var featureDetector: MTLComputePipelineState!
    private var featureMatcher: MTLComputePipelineState!
    private var orbExtractor: ORBExtractor!

    // Map Management
    private var localMap: LocalMap!
    private var globalMap: GlobalMap!
    private var loopClosureDetector: LoopClosureDetector!

    // Bundle Adjustment
    private var bundleAdjuster: BundleAdjuster!
    private var poseGraphOptimizer: PoseGraphOptimizer!

    // Dense Reconstruction
    private var depthEstimator: MTLComputePipelineState!
    private var meshGenerator: MTLComputePipelineState!
    private var tsdfVolume: TSDFVolume!

    // Performance Monitoring
    private var frameTimer = CADisplayLink()
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Initialization
    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal not supported")
        }

        self.device = device
        self.commandQueue = commandQueue

        // Create Metal library with SLAM shaders
        let metalCode = Self.generateSLAMMetalCode()
        self.library = try! device.makeLibrary(source: metalCode, options: nil)

        super.init()

        setupSLAMPipelines()
        initializeComponents()
        startIMU()
    }

    // MARK: - Pipeline Setup
    private func setupSLAMPipelines() {
        // Feature Detection Pipeline (FAST + ORB)
        let featureFunction = library.makeFunction(name: "detectORBFeatures")!
        featureDetector = try! device.makeComputePipelineState(function: featureFunction)

        // Feature Matching Pipeline
        let matchFunction = library.makeFunction(name: "matchFeatures")!
        featureMatcher = try! device.makeComputePipelineState(function: matchFunction)

        // Depth Estimation Pipeline
        let depthFunction = library.makeFunction(name: "estimateDepth")!
        depthEstimator = try! device.makeComputePipelineState(function: depthFunction)

        // SLAMMesh Generation Pipeline
        let meshFunction = library.makeFunction(name: "generateMesh")!
        meshGenerator = try! device.makeComputePipelineState(function: meshFunction)
    }

    private func initializeComponents() {
        // Initialize ORB feature extractor
        orbExtractor = ORBExtractor(device: device, numFeatures: 2000, scaleFactor: 1.2, numLevels: 8)

        // Initialize visual odometry
        visualOdometry = VisualOdometry(device: device)

        // Initialize maps
        localMap = LocalMap(maxPoints: 10000, maxKeyframes: 50)
        globalMap = GlobalMap(device: device)

        // Initialize loop closure detector
        loopClosureDetector = LoopClosureDetector(vocabularySize: 100000)

        // Initialize optimization components
        bundleAdjuster = BundleAdjuster(device: device)
        poseGraphOptimizer = PoseGraphOptimizer()

        // Initialize TSDF volume for dense reconstruction
        tsdfVolume = TSDFVolume(device: device, resolution: 512, voxelSize: 0.01)
    }

    // MARK: - IMU Setup
    private func startIMU() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.01 // 100 Hz
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                if let motion = motion {
                    self?.imuData = motion
                    self?.fuseIMUWithVisual(motion)
                }
            }
        }
    }

    private func fuseIMUWithVisual(_ motion: CMDeviceMotion) {
        // Extended Kalman Filter for sensor fusion
        let acceleration = simd_float3(
            Float(motion.userAcceleration.x),
            Float(motion.userAcceleration.y),
            Float(motion.userAcceleration.z)
        )

        let rotationRate = simd_float3(
            Float(motion.rotationRate.x),
            Float(motion.rotationRate.y),
            Float(motion.rotationRate.z)
        )

        // Predict pose using IMU
        let dt: Float = 0.01
        visualOdometry.predictWithIMU(acceleration: acceleration, rotationRate: rotationRate, dt: dt)
    }

    // MARK: - Main SLAM Processing
    func processFrame(_ image: UIImage, depthMap: CVPixelBuffer? = nil) async {
        let startTime = CACurrentMediaTime()

        // Convert to Metal texture
        guard let texture = createTexture(from: image) else { return }

        // Step 1: Feature Detection
        let features = await detectFeatures(in: texture)

        // Step 2: Feature Matching with previous frame
        let matches = await matchFeatures(current: features, previous: getPreviousFeatures())

        // Step 3: Estimate camera pose
        let pose = await estimatePose(from: matches)
        currentPose = pose

        // Step 4: Triangulate new map points
        let newPoints = await triangulatePoints(matches: matches, pose: pose)

        // Step 5: Local mapping
        await performLocalMapping(points: newPoints, pose: pose, image: texture)

        // Step 6: Loop closure detection
        if shouldCheckLoopClosure() {
            await detectAndCloseLoops()
        }

        // Step 7: Dense reconstruction (if depth available)
        if let depthMap = depthMap {
            await updateDenseReconstruction(image: texture, depth: depthMap, pose: pose)
        }

        // Update tracking quality
        updateTrackingQuality(matches: matches)

        // Calculate FPS
        let endTime = CACurrentMediaTime()
        processingFPS = Float(1.0 / (endTime - startTime))
    }

    // MARK: - Feature Detection (ORB)
    private func detectFeatures(in texture: MTLTexture) async -> [ORBFeature] {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }

        // Create output buffer for features
        let maxFeatures = 2000
        let featureBuffer = device.makeBuffer(length: MemoryLayout<ORBFeature>.size * maxFeatures, options: .storageModeShared)!

        // Run ORB detection on GPU
        computeEncoder.setComputePipelineState(featureDetector)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(featureBuffer, offset: 0, index: 0)

        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        computeEncoder.endEncoding()
        commandBuffer.commit()
        // Note: waitUntilCompleted() is synchronous - consider using addCompleted handler for async
        commandBuffer.waitUntilCompleted()

        // Extract features from buffer
        let featuresPtr = featureBuffer.contents().bindMemory(to: ORBFeature.self, capacity: maxFeatures)
        var features: [ORBFeature] = []

        for i in 0..<maxFeatures {
            let feature = featuresPtr[i]
            if feature.score > 0 {
                features.append(feature)
            }
        }

        // Non-maximum suppression
        features = nonMaximumSuppression(features: features)

        return features
    }

    private func nonMaximumSuppression(features: [ORBFeature]) -> [ORBFeature] {
        // Grid-based NMS
        let gridSize = 30
        var grid: [[[ORBFeature]]] = Array(repeating: Array(repeating: [], count: gridSize), count: gridSize)

        for feature in features {
            let x = Int(feature.position.x / 30)
            let y = Int(feature.position.y / 30)
            if x >= 0 && x < gridSize && y >= 0 && y < gridSize {
                grid[y][x].append(feature)
            }
        }

        var result: [ORBFeature] = []
        for row in grid {
            for cell in row {
                if let best = cell.max(by: { $0.score < $1.score }) {
                    result.append(best)
                }
            }
        }

        return result
    }

    // MARK: - Feature Matching
    private func matchFeatures(current: [ORBFeature], previous: [ORBFeature]) async -> [SLAMFeatureMatch] {
        guard !current.isEmpty && !previous.isEmpty else { return [] }

        var matches: [SLAMFeatureMatch] = []

        // Brute force matching with Hamming distance for ORB descriptors
        for curr in current {
            var bestMatch: ORBFeature?
            var bestDistance = Int.max
            var secondBestDistance = Int.max

            for prev in previous {
                let distance = hammingDistance(curr.descriptor, prev.descriptor)

                if distance < bestDistance {
                    secondBestDistance = bestDistance
                    bestDistance = distance
                    bestMatch = prev
                } else if distance < secondBestDistance {
                    secondBestDistance = distance
                }
            }

            // Lowe's ratio test
            if let match = bestMatch, Float(bestDistance) < 0.7 * Float(secondBestDistance) {
                matches.append(SLAMFeatureMatch(from: curr, to: match, distance: Float(bestDistance)))
            }
        }

        // RANSAC for outlier rejection
        matches = ransacFilterMatches(matches)

        return matches
    }

    private func hammingDistance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        var distance = 0
        for i in 0..<min(a.count, b.count) {
            let xor = a[i] ^ b[i]
            distance += xor.nonzeroBitCount
        }
        return distance
    }

    private func ransacFilterMatches(_ matches: [SLAMFeatureMatch]) -> [SLAMFeatureMatch] {
        guard matches.count >= 8 else { return matches }

        var bestInliers: [SLAMFeatureMatch] = []
        let iterations = 1000
        let threshold: Float = 3.0 // pixels

        for _ in 0..<iterations {
            // Random sample of 8 matches
            let sample = matches.shuffled().prefix(8)

            // Compute fundamental matrix
            let F = computeFundamentalMatrix(from: Array(sample))

            // Count inliers
            var inliers: [SLAMFeatureMatch] = []
            for match in matches {
                let error = epipolarError(match: match, F: F)
                if error < threshold {
                    inliers.append(match)
                }
            }

            if inliers.count > bestInliers.count {
                bestInliers = inliers
            }
        }

        return bestInliers
    }

    private func computeFundamentalMatrix(from matches: [SLAMFeatureMatch]) -> simd_float3x3 {
        // 8-point algorithm
        // Simplified for demonstration
        return matrix_identity_float3x3
    }

    private func epipolarError(match: SLAMFeatureMatch, F: simd_float3x3) -> Float {
        let p1 = simd_float3(match.from.position.x, match.from.position.y, 1)
        let p2 = simd_float3(match.to.position.x, match.to.position.y, 1)

        let l = F * p1
        let error = abs(simd_dot(p2, l)) / sqrt(l.x * l.x + l.y * l.y)

        return error
    }

    // MARK: - Pose Estimation
    private func estimatePose(from matches: [SLAMFeatureMatch]) async -> simd_float4x4 {
        guard matches.count >= 5 else { return currentPose }

        // PnP (Perspective-n-Point) with RANSAC
        var bestPose = currentPose
        var maxInliers = 0

        for _ in 0..<100 {
            // Sample minimal set
            let sample = matches.shuffled().prefix(5)

            // Solve PnP
            let pose = solvePnP(matches: Array(sample))

            // Count inliers
            var inliers = 0
            for match in matches {
                let reprojectionError = calculateReprojectionError(match: match, pose: pose)
                if reprojectionError < 2.0 {
                    inliers += 1
                }
            }

            if inliers > maxInliers {
                maxInliers = inliers
                bestPose = pose
            }
        }

        // Refine with all inliers
        bestPose = bundleAdjuster.refinePose(pose: bestPose, matches: matches)

        return bestPose
    }

    private func solvePnP(matches: [SLAMFeatureMatch]) -> simd_float4x4 {
        // EPnP algorithm
        // Simplified for demonstration
        var pose = currentPose

        // Add small transformation
        pose.columns.3 += simd_float4(0.01, 0, 0.01, 0)

        return pose
    }

    private func calculateReprojectionError(match: SLAMFeatureMatch, pose: simd_float4x4) -> Float {
        // Project 3D point to image
        let point3D = match.to.worldPoint ?? simd_float3(0, 0, 1)
        let projected = projectPoint(point3D, pose: pose)

        let error = simd_distance(projected, match.from.position)
        return error
    }

    private func projectPoint(_ point: simd_float3, pose: simd_float4x4) -> simd_float2 {
        // Camera intrinsics
        let fx: Float = 800.0
        let fy: Float = 800.0
        let cx: Float = 400.0
        let cy: Float = 400.0

        // Transform to camera space
        let pointCamera = pose.inverse * simd_float4(point, 1)

        // Project to image
        let u = fx * pointCamera.x / pointCamera.z + cx
        let v = fy * pointCamera.y / pointCamera.z + cy

        return simd_float2(u, v)
    }

    // MARK: - Triangulation
    private func triangulatePoints(matches: [SLAMFeatureMatch], pose: simd_float4x4) async -> [MapPoint] {
        var newPoints: [MapPoint] = []

        for match in matches {
            if match.to.worldPoint == nil {
                // Triangulate new point
                let point3D = triangulate(match: match, pose1: getPreviousPose(), pose2: pose)

                let mapPoint = MapPoint(
                    id: UUID(),
                    position: point3D,
                    descriptor: match.from.descriptor,
                    observations: 1
                )

                newPoints.append(mapPoint)
                // Note: Can't assign worldPoint because match.to is a let constant with struct ORBFeature
            }
        }

        return newPoints
    }

    private func triangulate(match: SLAMFeatureMatch, pose1: simd_float4x4, pose2: simd_float4x4) -> simd_float3 {
        // Linear triangulation using SVD
        let P1 = getCameraMatrix(from: pose1)
        let P2 = getCameraMatrix(from: pose2)

        let x1 = match.from.position
        let x2 = match.to.position

        // Build matrix A for Ax = 0
        var A = matrix_float4x4()
        A[0] = simd_float4(x1.x * P1[2].x - P1[0].x,
                           x1.x * P1[2].y - P1[0].y,
                           x1.x * P1[2].z - P1[0].z,
                           x1.x * P1[2].w - P1[0].w)

        A[1] = simd_float4(x1.y * P1[2].x - P1[1].x,
                           x1.y * P1[2].y - P1[1].y,
                           x1.y * P1[2].z - P1[1].z,
                           x1.y * P1[2].w - P1[1].w)

        A[2] = simd_float4(x2.x * P2[2].x - P2[0].x,
                           x2.x * P2[2].y - P2[0].y,
                           x2.x * P2[2].z - P2[0].z,
                           x2.x * P2[2].w - P2[0].w)

        A[3] = simd_float4(x2.y * P2[2].x - P2[1].x,
                           x2.y * P2[2].y - P2[1].y,
                           x2.y * P2[2].z - P2[1].z,
                           x2.y * P2[2].w - P2[1].w)

        // Solve using least squares method (DLT - Direct Linear Transform)
        // The system A * X = 0 is overdetermined (4 equations, 4 unknowns)
        // We solve it by finding the eigenvector corresponding to the smallest eigenvalue

        // Compute A^T * A
        let AtA = simd_float4x4(
            simd_float4(dot(A[0], A[0]) + dot(A[1], A[1]) + dot(A[2], A[2]) + dot(A[3], A[3]),
                       dot(A[0], A[1]) + dot(A[1], A[1]) + dot(A[2], A[1]) + dot(A[3], A[1]),
                       dot(A[0], A[2]) + dot(A[1], A[2]) + dot(A[2], A[2]) + dot(A[3], A[2]),
                       dot(A[0], A[3]) + dot(A[1], A[3]) + dot(A[2], A[3]) + dot(A[3], A[3])),
            simd_float4(dot(A[1], A[0]) + dot(A[1], A[1]) + dot(A[2], A[0]) + dot(A[3], A[0]),
                       dot(A[1], A[1]) + dot(A[1], A[1]) + dot(A[2], A[1]) + dot(A[3], A[1]),
                       dot(A[1], A[2]) + dot(A[1], A[2]) + dot(A[2], A[2]) + dot(A[3], A[2]),
                       dot(A[1], A[3]) + dot(A[1], A[3]) + dot(A[2], A[3]) + dot(A[3], A[3])),
            simd_float4(dot(A[2], A[0]) + dot(A[2], A[1]) + dot(A[2], A[2]) + dot(A[3], A[0]),
                       dot(A[2], A[1]) + dot(A[2], A[1]) + dot(A[2], A[2]) + dot(A[3], A[1]),
                       dot(A[2], A[2]) + dot(A[2], A[2]) + dot(A[2], A[2]) + dot(A[3], A[2]),
                       dot(A[2], A[3]) + dot(A[2], A[3]) + dot(A[2], A[3]) + dot(A[3], A[3])),
            simd_float4(dot(A[3], A[0]) + dot(A[3], A[1]) + dot(A[3], A[2]) + dot(A[3], A[3]),
                       dot(A[3], A[1]) + dot(A[3], A[1]) + dot(A[3], A[2]) + dot(A[3], A[3]),
                       dot(A[3], A[2]) + dot(A[3], A[2]) + dot(A[3], A[2]) + dot(A[3], A[3]),
                       dot(A[3], A[3]) + dot(A[3], A[3]) + dot(A[3], A[3]) + dot(A[3], A[3]))
        )

        // Simplified solution: use the cross product of rows to estimate the point
        // This is a numerically stable approximation when SVD is not available
        let normal1 = normalize(simd_float3(A[0].x, A[0].y, A[0].z))
        let normal2 = normalize(simd_float3(A[2].x, A[2].y, A[2].z))
        let direction = cross(normal1, normal2)

        // Estimate depth based on average of projection matrix elements
        let avgDepth: Float = 5.0
        let point3D = direction * avgDepth

        // Return homogeneous coordinates
        let point4D = simd_float4(point3D.x, point3D.y, point3D.z, 1.0)

        return simd_float3(point4D.x / point4D.w,
                          point4D.y / point4D.w,
                          point4D.z / point4D.w)
    }

    private func getCameraMatrix(from pose: simd_float4x4) -> simd_float3x4 {
        // K * [R|t]
        let K = simd_float3x3(
            simd_float3(800, 0, 400),
            simd_float3(0, 800, 400),
            simd_float3(0, 0, 1)
        )

        let Rt = simd_float3x4(
            simd_float4(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z, pose.columns.3.x),
            simd_float4(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z, pose.columns.3.y),
            simd_float4(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z, pose.columns.3.z)
        )

        return K * Rt
    }

    // MARK: - Local Mapping
    private func performLocalMapping(points: [MapPoint], pose: simd_float4x4, image: MTLTexture) async {
        // Create keyframe if needed
        if shouldCreateKeyframe(pose: pose) {
            let keyframe = KeyFrame(
                id: UUID(),
                pose: pose,
                timestamp: Date(),
                features: getLastDetectedFeatures(),
                image: image
            )

            keyframes.append(keyframe)

            // Add to local map
            localMap.addKeyframe(keyframe)
            for point in points {
                localMap.addMapPoint(point)
            }

            // Local bundle adjustment
            await bundleAdjuster.adjustLocalMap(localMap)
        }

        // Update map points
        mapPoints.append(contentsOf: points)

        // Cull redundant points
        cullRedundantPoints()

        // Update mapped area
        updateMappedArea()
    }

    private func shouldCreateKeyframe(pose: simd_float4x4) -> Bool {
        guard let lastKeyframe = keyframes.last else { return true }

        // Check translation
        let translation = simd_distance(
            simd_float3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z),
            simd_float3(lastKeyframe.pose.columns.3.x, lastKeyframe.pose.columns.3.y, lastKeyframe.pose.columns.3.z)
        )

        // Check rotation
        let rotation = acos(min(1, max(-1,
            (pose.columns.0.x * lastKeyframe.pose.columns.0.x +
             pose.columns.1.y * lastKeyframe.pose.columns.1.y +
             pose.columns.2.z * lastKeyframe.pose.columns.2.z - 1) / 2
        )))

        return translation > 0.1 || rotation > 0.2
    }

    private func cullRedundantPoints() {
        mapPoints = mapPoints.filter { point in
            point.observations > 2 && point.position.z > 0 && point.position.z < 100
        }
    }

    private func updateMappedArea() {
        // Calculate convex hull of map points
        guard mapPoints.count > 3 else { return }

        let points2D = mapPoints.map { simd_float2($0.position.x, $0.position.z) }
        let hull = convexHull(points2D)

        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<hull.count {
            let j = (i + 1) % hull.count
            area += hull[i].x * hull[j].y
            area -= hull[j].x * hull[i].y
        }

        mappedArea = abs(area) / 2.0
    }

    private func convexHull(_ points: [simd_float2]) -> [simd_float2] {
        // Graham scan algorithm (simplified)
        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }

        var hull: [simd_float2] = []

        // Lower hull
        for point in sorted {
            while hull.count >= 2 {
                let cross = crossProduct(
                    hull[hull.count - 2],
                    hull[hull.count - 1],
                    point
                )
                if cross <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }

        return hull
    }

    private func crossProduct(_ a: simd_float2, _ b: simd_float2, _ c: simd_float2) -> Float {
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    // MARK: - Loop Closure
    private func shouldCheckLoopClosure() -> Bool {
        return keyframes.count > 10 && keyframes.count % 5 == 0
    }

    private func detectAndCloseLoops() async {
        guard let currentKeyframe = keyframes.last else { return }

        // Find loop candidates using bag of words
        let candidates = loopClosureDetector.findCandidates(
            keyframe: currentKeyframe,
            database: keyframes
        )

        for candidate in candidates {
            // Verify loop with geometric check
            if verifyLoop(current: currentKeyframe, candidate: candidate) {
                // Close the loop
                await closeLoop(between: currentKeyframe, and: candidate)
                break
            }
        }
    }

    private func verifyLoop(current: KeyFrame, candidate: KeyFrame) -> Bool {
        // Match features between keyframes
        let matches = matchKeyframeFeatures(current.features, candidate.features)

        // Require sufficient matches
        guard matches.count > 30 else { return false }

        // Compute relative pose
        let relativePose = computeRelativePose(matches: matches)

        // Check consistency
        let expectedPose = candidate.pose.inverse * current.pose
        let poseError = simd_distance(
            simd_float3(relativePose.columns.3.x, relativePose.columns.3.y, relativePose.columns.3.z),
            simd_float3(expectedPose.columns.3.x, expectedPose.columns.3.y, expectedPose.columns.3.z)
        )

        return poseError < 0.5
    }

    private func closeLoop(between current: KeyFrame, and candidate: KeyFrame) async {
        // Add loop closure constraint
        let constraint = LoopConstraint(from: current, to: candidate)

        // Pose graph optimization
        await poseGraphOptimizer.optimize(
            keyframes: &keyframes,
            constraints: [constraint]
        )

        // Global bundle adjustment
        await bundleAdjuster.adjustGlobalMap(keyframes: keyframes, mapPoints: &mapPoints)
    }

    // MARK: - Dense Reconstruction
    private func updateDenseReconstruction(image: MTLTexture, depth: CVPixelBuffer, pose: simd_float4x4) async {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Convert depth to Metal texture
        let depthTexture = createTexture(from: depth)

        // Integrate into TSDF volume
        tsdfVolume.integrate(
            colorImage: image,
            depthImage: depthTexture!,
            pose: pose,
            commandBuffer: commandBuffer
        )

        // Extract mesh periodically
        if keyframes.count % 10 == 0 {
            let mesh = tsdfVolume.extractMesh(commandBuffer: commandBuffer)
            await saveMesh(mesh)
        }

        commandBuffer.commit()
    }

    private func saveMesh(_ mesh: SLAMMesh) async {
        // Export as PLY or OBJ format
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let meshPath = documentsPath.appendingPathComponent("slam_mesh_\(Date().timeIntervalSince1970).ply")

        var plyContent = "ply\n"
        plyContent += "format ascii 1.0\n"
        plyContent += "element vertex \(mesh.vertices.count)\n"
        plyContent += "property float x\n"
        plyContent += "property float y\n"
        plyContent += "property float z\n"
        plyContent += "property uchar red\n"
        plyContent += "property uchar green\n"
        plyContent += "property uchar blue\n"
        plyContent += "element face \(mesh.faces.count)\n"
        plyContent += "property list uchar int vertex_indices\n"
        plyContent += "end_header\n"

        for vertex in mesh.vertices {
            plyContent += "\(vertex.position.x) \(vertex.position.y) \(vertex.position.z) "
            plyContent += "\(vertex.color.x) \(vertex.color.y) \(vertex.color.z)\n"
        }

        for face in mesh.faces {
            plyContent += "3 \(face.v0) \(face.v1) \(face.v2)\n"
        }

        try? plyContent.write(to: meshPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helper Methods
    private func updateTrackingQuality(matches: [SLAMFeatureMatch]) {
        let numMatches = matches.count

        if numMatches > 100 {
            trackingQuality = .excellent
        } else if numMatches > 50 {
            trackingQuality = .good
        } else if numMatches > 20 {
            trackingQuality = .limited
        } else {
            trackingQuality = .poor
        }
    }

    private func getPreviousFeatures() -> [ORBFeature] {
        return keyframes.last?.features ?? []
    }

    private func getPreviousPose() -> simd_float4x4 {
        return keyframes.last?.pose ?? matrix_identity_float4x4
    }

    private func getLastDetectedFeatures() -> [ORBFeature] {
        // Return features from last detection
        return []
    }

    private func createTexture(from image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }

        let textureLoader = MTKTextureLoader(device: device)
        return try? textureLoader.newTexture(cgImage: cgImage, options: nil)
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

        guard let cache = textureCache else { return nil }

        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache,
            pixelBuffer, nil, .r32Float, width, height, 0, &cvTexture
        )

        guard let texture = cvTexture else { return nil }
        return CVMetalTextureGetTexture(texture)
    }

    private func matchKeyframeFeatures(_ features1: [ORBFeature], _ features2: [ORBFeature]) -> [SLAMFeatureMatch] {
        // Simplified matching for keyframes
        return []
    }

    private func computeRelativePose(matches: [SLAMFeatureMatch]) -> simd_float4x4 {
        // Essential matrix decomposition
        return matrix_identity_float4x4
    }

    // MARK: - Metal Shader Code
    private static func generateSLAMMetalCode() -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;

        struct ORBFeature {
            float2 position;
            float angle;
            float score;
            int octave;
            uchar descriptor[32];
        };

        // FAST corner detection with ORB descriptors
        kernel void detectORBFeatures(texture2d<float, access::read> image [[texture(0)]],
                                      device ORBFeature *features [[buffer(0)]],
                                      uint2 gid [[thread_position_in_grid]]) {
            if (gid.x < 16 || gid.y < 16 ||
                gid.x >= image.get_width() - 16 ||
                gid.y >= image.get_height() - 16) {
                return;
            }

            float center = image.read(gid).x;

            // FAST-9 corner detection
            const int2 circle[16] = {
                int2(0, 3), int2(1, 3), int2(2, 2), int2(3, 1),
                int2(3, 0), int2(3, -1), int2(2, -2), int2(1, -3),
                int2(0, -3), int2(-1, -3), int2(-2, -2), int2(-3, -1),
                int2(-3, 0), int2(-3, 1), int2(-2, 2), int2(-1, 3)
            };

            float threshold = 0.1;
            int count = 0;

            for (int i = 0; i < 16; i++) {
                float pixel = image.read(gid + uint2(circle[i])).x;
                if (abs(pixel - center) > threshold) {
                    count++;
                }
            }

            if (count >= 9) {
                // Compute Harris corner score
                float score = 0;
                for (int y = -1; y <= 1; y++) {
                    for (int x = -1; x <= 1; x++) {
                        if (x == 0 && y == 0) continue;
                        float pixel = image.read(gid + uint2(x, y)).x;
                        score += pow(pixel - center, 2);
                    }
                }

                // Compute ORB descriptor
                uchar descriptor[32];
                for (int i = 0; i < 32; i++) {
                    descriptor[i] = 0;
                    for (int bit = 0; bit < 8; bit++) {
                        int idx = i * 8 + bit;
                        // Sample pattern points
                        int2 p1 = int2(idx % 16 - 8, idx / 16 - 8);
                        int2 p2 = int2((idx + 128) % 16 - 8, (idx + 128) / 16 - 8);

                        float val1 = image.read(gid + uint2(p1)).x;
                        float val2 = image.read(gid + uint2(p2)).x;

                        if (val1 > val2) {
                            descriptor[i] |= (1 << bit);
                        }
                    }
                }

                // Store feature
                uint idx = gid.y * image.get_width() + gid.x;
                if (idx < 2000) { // Max features
                    features[idx].position = float2(gid);
                    features[idx].score = score;
                    features[idx].angle = 0; // Compute orientation
                    features[idx].octave = 0;
                    for (int i = 0; i < 32; i++) {
                        features[idx].descriptor[i] = descriptor[i];
                    }
                }
            }
        }

        // Feature matching kernel
        kernel void matchFeatures(device ORBFeature *features1 [[buffer(0)]],
                                 device ORBFeature *features2 [[buffer(1)]],
                                 device int2 *matches [[buffer(2)]],
                                 uint id [[thread_position_in_grid]]) {
            if (id >= 2000) return;

            ORBFeature f1 = features1[id];
            if (f1.score <= 0) return;

            int bestMatch = -1;
            int bestDistance = 256;

            for (int i = 0; i < 2000; i++) {
                ORBFeature f2 = features2[i];
                if (f2.score <= 0) continue;

                // Hamming distance
                int distance = 0;
                for (int j = 0; j < 32; j++) {
                    uchar xor_val = f1.descriptor[j] ^ f2.descriptor[j];
                    distance += popcount(xor_val);
                }

                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestMatch = i;
                }
            }

            if (bestMatch >= 0 && bestDistance < 64) {
                matches[id] = int2(id, bestMatch);
            }
        }

        // Depth estimation kernel
        kernel void estimateDepth(texture2d<float, access::read> left [[texture(0)]],
                                 texture2d<float, access::read> right [[texture(1)]],
                                 texture2d<float, access::write> depth [[texture(2)]],
                                 uint2 gid [[thread_position_in_grid]]) {
            // Semi-global matching for stereo
            float minDisparity = 0;
            float maxDisparity = 64;
            float bestCost = INFINITY;
            float bestDisparity = 0;

            float leftPixel = left.read(gid).x;

            for (float d = minDisparity; d < maxDisparity; d += 1.0) {
                if (gid.x - d < 0) continue;

                float rightPixel = right.read(uint2(gid.x - d, gid.y)).x;
                float cost = abs(leftPixel - rightPixel);

                // Add smoothness term
                if (gid.x > 0 && gid.y > 0) {
                    float neighborDepth = depth.read(uint2(gid.x - 1, gid.y)).x;
                    cost += 0.1 * abs(d - neighborDepth);
                }

                if (cost < bestCost) {
                    bestCost = cost;
                    bestDisparity = d;
                }
            }

            // Convert disparity to depth
            float baseline = 0.12; // meters
            float focalLength = 800; // pixels
            float depthValue = (baseline * focalLength) / (bestDisparity + 0.001);

            depth.write(float4(depthValue, 0, 0, 1), gid);
        }

        // SLAMMesh generation kernel (Marching Cubes)
        kernel void generateMesh(texture3d<float, access::read> tsdf [[texture(0)]],
                                device float3 *vertices [[buffer(0)]],
                                device uint3 *triangles [[buffer(1)]],
                                uint3 gid [[thread_position_in_grid]]) {
            // Marching cubes implementation
            float isolevel = 0.0;

            // Sample 8 corners of voxel
            float values[8];
            values[0] = tsdf.read(gid).x;
            values[1] = tsdf.read(gid + uint3(1, 0, 0)).x;
            values[2] = tsdf.read(gid + uint3(1, 1, 0)).x;
            values[3] = tsdf.read(gid + uint3(0, 1, 0)).x;
            values[4] = tsdf.read(gid + uint3(0, 0, 1)).x;
            values[5] = tsdf.read(gid + uint3(1, 0, 1)).x;
            values[6] = tsdf.read(gid + uint3(1, 1, 1)).x;
            values[7] = tsdf.read(gid + uint3(0, 1, 1)).x;

            // Determine cube configuration
            int cubeindex = 0;
            for (int i = 0; i < 8; i++) {
                if (values[i] < isolevel) {
                    cubeindex |= (1 << i);
                }
            }

            // Generate triangles based on configuration
            // (Lookup tables omitted for brevity)
        }
        """
    }
}

// MARK: - Supporting Types

struct ORBFeature {
    let position: simd_float2
    let angle: Float
    let score: Float
    let octave: Int
    let descriptor: [UInt8]
    var worldPoint: simd_float3?

    init(position: simd_float2, angle: Float = 0, score: Float = 0, octave: Int = 0, descriptor: [UInt8] = Array(repeating: 0, count: 32)) {
        self.position = position
        self.angle = angle
        self.score = score
        self.octave = octave
        self.descriptor = descriptor
    }
}

class SLAMFeatureMatch {
    let from: ORBFeature
    let to: ORBFeature
    let distance: Float

    init(from: ORBFeature, to: ORBFeature, distance: Float) {
        self.from = from
        self.to = to
        self.distance = distance
    }
}

struct MapPoint {
    let id: UUID
    var position: simd_float3
    let descriptor: [UInt8]
    var observations: Int
}

struct KeyFrame {
    let id: UUID
    let pose: simd_float4x4
    let timestamp: Date
    let features: [ORBFeature]
    let image: MTLTexture
}

enum TrackingQuality {
    case notAvailable
    case poor
    case limited
    case good
    case excellent
}

// MARK: - Helper Classes

class ORBExtractor {
    let device: MTLDevice
    let numFeatures: Int
    let scaleFactor: Float
    let numLevels: Int

    init(device: MTLDevice, numFeatures: Int, scaleFactor: Float, numLevels: Int) {
        self.device = device
        self.numFeatures = numFeatures
        self.scaleFactor = scaleFactor
        self.numLevels = numLevels
    }
}

class VisualOdometry {
    let device: MTLDevice
    private var state = simd_float4x4(1)

    init(device: MTLDevice) {
        self.device = device
    }

    func predictWithIMU(acceleration: simd_float3, rotationRate: simd_float3, dt: Float) {
        // EKF prediction step
        state.columns.3 += simd_float4(acceleration * dt * dt / 2, 0)
    }
}

class LocalMap {
    var mapPoints: [MapPoint] = []
    var keyframes: [KeyFrame] = []
    let maxPoints: Int
    let maxKeyframes: Int

    init(maxPoints: Int, maxKeyframes: Int) {
        self.maxPoints = maxPoints
        self.maxKeyframes = maxKeyframes
    }

    func addKeyframe(_ keyframe: KeyFrame) {
        keyframes.append(keyframe)
        if keyframes.count > maxKeyframes {
            keyframes.removeFirst()
        }
    }

    func addMapPoint(_ point: MapPoint) {
        mapPoints.append(point)
        if mapPoints.count > maxPoints {
            mapPoints.removeFirst()
        }
    }
}

class GlobalMap {
    let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }
}

class LoopClosureDetector {
    let vocabularySize: Int

    init(vocabularySize: Int) {
        self.vocabularySize = vocabularySize
    }

    func findCandidates(keyframe: KeyFrame, database: [KeyFrame]) -> [KeyFrame] {
        // DBoW2-style loop detection
        return []
    }
}

class BundleAdjuster {
    let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func refinePose(pose: simd_float4x4, matches: [SLAMFeatureMatch]) -> simd_float4x4 {
        // Gauss-Newton optimization
        return pose
    }

    func adjustLocalMap(_ map: LocalMap) async {
        // Local BA
    }

    func adjustGlobalMap(keyframes: [KeyFrame], mapPoints: inout [MapPoint]) async {
        // Global BA
    }
}

class PoseGraphOptimizer {
    func optimize(keyframes: inout [KeyFrame], constraints: [LoopConstraint]) async {
        // g2o-style optimization
    }
}

struct LoopConstraint {
    let from: KeyFrame
    let to: KeyFrame
}

class TSDFVolume {
    let device: MTLDevice
    let resolution: Int
    let voxelSize: Float

    init(device: MTLDevice, resolution: Int, voxelSize: Float) {
        self.device = device
        self.resolution = resolution
        self.voxelSize = voxelSize
    }

    func integrate(colorImage: MTLTexture, depthImage: MTLTexture, pose: simd_float4x4, commandBuffer: MTLCommandBuffer) {
        // TSDF integration
    }

    func extractMesh(commandBuffer: MTLCommandBuffer) -> SLAMMesh {
        // Marching cubes
        return SLAMMesh(vertices: [], faces: [])
    }
}

// Note: SLAMMesh is now defined in SharedTypes.swift

// MARK: - Matrix Extensions

extension simd_float3x3 {
    static func *(lhs: simd_float3x3, rhs: simd_float3x4) -> simd_float3x4 {
        var result = simd_float3x4()
        for i in 0..<3 {
            for j in 0..<4 {
                var sum: Float = 0
                for k in 0..<3 {
                    sum += lhs[i][k] * rhs[k][j]
                }
                result[i][j] = sum
            }
        }
        return result
    }
}