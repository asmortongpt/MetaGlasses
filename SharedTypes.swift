import SwiftUI
import simd

// MARK: - Shared Types for 3D Vision Systems
// Common structures used across Photogrammetry, SLAM, and NeRF systems

struct Feature {
    let location: SIMD2<Float>
    let descriptor: [Float]
    let scale: Float
    let orientation: Float
}

struct FeatureMatch {
    let feature1: Feature
    let feature2: Feature
    let confidence: Float
}

struct PointCloud {
    var points: [SIMD3<Float>] = []
    var colors: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var cameras: [Camera] = []
}

struct Camera {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var intrinsics: matrix_float3x3 = matrix_identity_float3x3
    var distortion: SIMD3<Float> = SIMD3<Float>(0, 0, 0)  // Radial distortion (k1, k2, k3)

    var pose: simd_float4x4 {
        // Construct 4x4 transformation matrix from position and rotation
        let rotationMatrix = matrix_float4x4(rotation)
        var transform = rotationMatrix
        transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1.0)
        return transform
    }
}

// Photogrammetry-specific mesh structure
struct PhotogrammetryMesh {
    var vertices: [SIMD3<Float>] = []
    var triangles: [SIMD3<Int32>] = []
    var uvCoordinates: [SIMD2<Float>] = []
    var texture: UIImage?
    var triangleCount: Int { triangles.count }
}

// SLAM-specific mesh structure with vertex colors
struct SLAMMesh {
    struct Vertex {
        let position: simd_float3
        let color: simd_float3
    }

    struct Face {
        let v0, v1, v2: Int
    }

    let vertices: [Vertex]
    let faces: [Face]
}
