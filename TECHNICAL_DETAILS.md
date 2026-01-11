# Technical Details - Dual Camera Stereoscopic 3D Capture

## System Architecture

### Overview

The MetaGlasses 3D Camera app leverages the dual-camera system in Meta Ray-Ban smart glasses to capture stereoscopic images for true 3D viewing and reconstruction.

### Camera Configuration

| Camera | Purpose | Resolution | Use Case |
|--------|---------|------------|----------|
| Navigation Camera | Spatial tracking, scene understanding | Lower res (TBD) | Left eye / depth reference |
| Imaging Camera | High-quality photography | 12 MP ultra-wide | Right eye / primary image |

## Stereoscopic 3D Principles

### Why Dual Cameras Create 3D

Human depth perception comes from binocular vision—each eye sees a slightly different perspective. The brain fuses these views to perceive depth.

The MetaGlasses dual cameras replicate this:
1. **Navigation camera** = Left eye perspective
2. **Imaging camera** = Right eye perspective
3. **Baseline distance** = Physical separation between cameras

### Parallax and Depth

```
Depth (Z) = (Baseline × Focal Length) / Disparity

Where:
- Baseline = Distance between cameras (fixed)
- Focal Length = Camera's focal length
- Disparity = Horizontal pixel difference between matching points
```

## Capture Synchronization

### Simultaneous Capture

The app uses Swift's structured concurrency to ensure both cameras capture at the exact same moment:

```swift
try await withThrowingTaskGroup(of: (CameraType, Data).self) { group in
    // Both tasks run in parallel
    group.addTask { try await captureNavigation() }
    group.addTask { try await captureImaging() }

    // Results collected as they complete
    for try await (type, data) in group { ... }
}
```

**Critical**: Temporal synchronization prevents motion artifacts in 3D viewing.

### Capture Pipeline

```
1. User taps "Capture"
   ↓
2. DualCameraManager initiates parallel capture
   ↓
3. Task Group spawns two concurrent operations:
   ├─ Navigation camera capture
   └─ Imaging camera capture
   ↓
4. Both Data buffers received
   ↓
5. Convert to UIImage
   ↓
6. Create StereoPair with metadata
   ↓
7. Update UI with preview
```

## Image Processing

### Anaglyph 3D Generation

Anaglyph images encode left/right views using color channels:

```
Red Channel   = Left eye (Navigation camera)
Cyan Channels = Right eye (Imaging camera)
```

**Implementation**:
```swift
// Extract red from left image
leftRed = leftImage.applyFilter("CIColorMatrix",
    inputRVector: [1, 0, 0, 0])

// Extract cyan (green + blue) from right image
rightCyan = rightImage.applyFilter("CIColorMatrix",
    inputGVector: [0, 1, 0, 0],
    inputBVector: [0, 0, 1, 0])

// Composite
anaglyph = leftRed.composited(over: rightCyan)
```

**Viewing**: Requires red/cyan 3D glasses

### Side-by-Side (SBS) Format

Standard for VR headsets and 3D displays:

```
┌─────────────┬─────────────┐
│             │             │
│  Left Eye   │  Right Eye  │
│  (Nav Cam)  │  (Img Cam)  │
│             │             │
└─────────────┴─────────────┘
```

**Compatibility**:
- Google Cardboard
- Meta Quest
- 3D TVs (SBS mode)
- YouTube 3D

## Depth Estimation

### Stereo Vision Pipeline (Future Enhancement)

1. **Rectification**: Align image planes
2. **Correspondence**: Match pixels between views
3. **Disparity Map**: Calculate pixel offsets
4. **Depth Map**: Convert disparity to distance

### Potential Implementation

```swift
import Vision

func generateDepthMap(from stereoPair: StereoPair) -> UIImage? {
    let request = VNGenerateImageFeaturePrintRequest()

    // Extract features from both images
    let leftFeatures = extractFeatures(stereoPair.leftImage, request)
    let rightFeatures = extractFeatures(stereoPair.rightImage, request)

    // Match features
    let matches = matchFeatures(leftFeatures, rightFeatures)

    // Calculate disparity
    let disparityMap = calculateDisparity(matches)

    // Convert to depth
    return disparityToDepth(disparityMap)
}
```

## Camera Calibration

### Intrinsic Parameters

Each camera has intrinsic parameters:
- Focal length (fx, fy)
- Principal point (cx, cy)
- Distortion coefficients (k1, k2, k3, p1, p2)

### Extrinsic Parameters

Relationship between cameras:
- Rotation matrix (R)
- Translation vector (T)
- Baseline distance

### Calibration Data

```swift
struct CameraCalibration {
    // Navigation camera intrinsics
    let navFocalLength: CGPoint
    let navPrincipalPoint: CGPoint
    let navDistortion: [Double]

    // Imaging camera intrinsics
    let imgFocalLength: CGPoint
    let imgPrincipalPoint: CGPoint
    let imgDistortion: [Double]

    // Stereo parameters
    let rotation: simd_double3x3
    let translation: simd_double3
    let baseline: Double
}
```

**Note**: Actual calibration values should come from Meta SDK or factory calibration.

## 3D Reconstruction Workflow

### Photogrammetry Pipeline

Multiple stereo pairs enable 3D mesh generation:

```
Input: 3+ stereo pairs from different angles
   ↓
1. Feature detection (SIFT/ORB)
   ↓
2. Feature matching across pairs
   ↓
3. Bundle adjustment
   ↓
4. Dense reconstruction
   ↓
5. Mesh generation
   ↓
Output: 3D model (.obj, .usdz)
```

### Reality Capture Integration

Export stereo pairs for professional tools:
- RealityCapture
- Agisoft Metashape
- Meshroom (open source)

## Performance Optimization

### Concurrent Processing

```swift
// Process images in parallel
await withTaskGroup(of: UIImage?.self) { group in
    group.addTask { processImage(navImage) }
    group.addTask { processImage(imgImage) }
}
```

### Memory Management

```swift
// Use autoreleasepool for large image operations
autoreleasepool {
    let anaglyph = generateAnaglyph(stereoPair)
    saveToLibrary(anaglyph)
}
```

### Image Compression

```swift
// Compress for storage
if let jpegData = image.jpegData(compressionQuality: 0.85) {
    try jpegData.write(to: fileURL)
}
```

## Quality Factors

### Optimal Capture Conditions

| Factor | Requirement | Reason |
|--------|-------------|--------|
| Lighting | Bright, even | Reduces noise, improves matching |
| Motion | Minimal | Prevents blur, sync issues |
| Distance | 0.5-10 meters | Within depth perception range |
| Texture | Rich detail | Enables better correspondence |

### Common Issues

1. **Ghosting in Anaglyph**
   - Cause: Camera misalignment or timing offset
   - Fix: Ensure synchronous capture

2. **Poor Depth Perception**
   - Cause: Insufficient baseline or convergence
   - Fix: Use multiple capture angles

3. **Image Distortion**
   - Cause: Lens distortion uncorrected
   - Fix: Apply distortion correction

## File Formats

### Metadata Storage

```swift
// EXIF data for stereo pairs
let metadata: [String: Any] = [
    kCGImagePropertyOrientation: orientation,
    kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: timestamp,
        kCGImagePropertyExifLensModel: "Meta Ray-Ban Dual Camera"
    ],
    "StereoMetadata": [
        "LeftCamera": "Navigation",
        "RightCamera": "Imaging",
        "Baseline": baselineDistance,
        "CaptureMode": "Simultaneous"
    ]
]
```

### Export Formats

| Format | Extension | Use Case |
|--------|-----------|----------|
| Side-by-Side JPEG | `.jpg` | VR headsets, 3D displays |
| Anaglyph PNG | `.png` | Red/cyan glasses viewing |
| Separate JPEG | `.jpg` × 2 | Manual processing |
| MPO (Future) | `.mpo` | 3D photo standard |
| JPS (Future) | `.jps` | JPEG Stereo format |

## Advanced Features (Future)

### Real-Time Depth Preview

```swift
// Live depth visualization during capture
func showLiveDepth() {
    depthFilter.inputImage = navigationCamera.feed
    depthFilter.inputDisparityImage = imagingCamera.feed
    previewLayer.contents = depthFilter.outputImage
}
```

### AR Integration

```swift
import ARKit

// Use depth map for AR occlusion
let arConfig = ARWorldTrackingConfiguration()
arConfig.sceneDepth = .fromStereoPair(stereoPair)
```

### Machine Learning Depth

```swift
import CreateML

// Train custom depth estimation model
let model = try MLDepthEstimator(trainingData: stereoPairs)
```

## Bluetooth Protocol

### Data Transfer

```
Capture Command → Glasses
   ↓
Navigation Camera → 720p JPEG
   ↓ (Bluetooth LE)
iPhone receives navigation image
   ↓
Imaging Camera → 12 MP JPEG
   ↓ (Bluetooth LE)
iPhone receives imaging image
   ↓
StereoPair created
```

### Limitations

- Max resolution: 720p @ 30fps for video streaming
- Photo capture: Full 12 MP supported
- Latency: ~100-500ms depending on image size

## References

### Computer Vision
- Hartley & Zisserman: "Multiple View Geometry"
- Szeliski: "Computer Vision: Algorithms and Applications"

### Stereo Algorithms
- Block Matching
- Semi-Global Matching (SGM)
- Graph Cuts

### Apple Frameworks
- AVFoundation: Camera capture
- Core Image: Image processing
- Vision: Feature detection
- ARKit: Depth integration

## Development Roadmap

### Phase 1 (Current)
- ✅ Dual camera capture
- ✅ Side-by-side export
- ✅ Anaglyph generation

### Phase 2 (Planned)
- Depth map generation
- Stereo rectification
- MPO/JPS export

### Phase 3 (Future)
- 3D mesh reconstruction
- AR integration
- Real-time depth preview

---

**Last Updated**: 2025-01-09
**SDK Version**: Meta Wearables DAT 0.3.0
**iOS Version**: 15.2+
