# MetaGlasses 3D Camera - Setup Guide

## Overview

This iOS app enables **stereoscopic 3D image capture** using both cameras on Meta Ray-Ban smart glasses:
- **Navigation Camera**: Lower resolution camera for tracking/navigation
- **Imaging Camera**: High resolution 12 MP camera for photography

By capturing from both cameras simultaneously, the app creates true stereoscopic 3D images.

## Prerequisites

### Hardware Requirements
- **iPhone** running iOS 15.2 or later
- **Meta Ray-Ban Smart Glasses (Gen 2)** with dual cameras
- Both devices paired via Bluetooth

### Software Requirements
- **Xcode 15** or later
- **Swift 6**
- **macOS Sonoma** or later (for development)

### Meta Wearables Setup
1. Install the **Meta View** app from the App Store
2. Pair your Meta Ray-Ban glasses with your iPhone
3. Ensure glasses are fully charged and updated to latest firmware

## Installation

### Step 1: Clone Repository

```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
```

### Step 2: Open in Xcode

```bash
open Package.swift
```

Or open the project in Xcode:
- File → Open → Select `MetaGlasses` folder

### Step 3: Add Meta Wearables SDK

The SDK is already configured in `Package.swift`, but you may need to resolve packages:

1. In Xcode, go to: **File → Add Package Dependencies**
2. Enter: `https://github.com/facebook/meta-wearables-dat-ios`
3. Select version `0.3.0` or later
4. Click **Add Package**

Alternatively, Xcode should automatically resolve dependencies when you open the project.

### Step 4: Configure Signing

1. Select the project in Xcode navigator
2. Under **Signing & Capabilities**:
   - Select your Team
   - Update Bundle Identifier: `com.yourcompany.metaglasses`

### Step 5: Build and Run

1. Connect your iPhone via USB
2. Select your iPhone as the build target
3. Click **Run** (⌘R) or the Play button

**Note**: This app requires a physical iPhone with Bluetooth. It will not work on the iOS Simulator.

## Usage Guide

### 1. Launch App

Open the MetaGlasses 3D Camera app on your iPhone.

### 2. Connect to Glasses

1. Ensure your Meta Ray-Ban glasses are:
   - Powered on
   - Already paired with your iPhone via Meta View app
   - Within Bluetooth range

2. Tap **"Connect to Glasses"** in the app

3. Wait for status to show: **"✅ Connected (Dual Camera)"**

### 3. Capture Stereoscopic 3D Images

#### Single Capture
- Tap **"Capture Stereo 3D Image"**
- The app will simultaneously capture from both cameras
- Progress bar shows capture status (50% per camera)
- Both images appear in the preview panes

#### Multiple Captures (3 Images)
- Tap **"Capture 3 Stereo Pairs"**
- App captures 3 stereo pairs with 2-second intervals
- Useful for 3D reconstruction or photogrammetry

### 4. Export Options

Choose export format using the segmented control:

#### **Side-by-Side**
- Left and right images placed side-by-side
- Compatible with VR headsets and 3D displays
- Standard stereoscopic format

#### **Anaglyph 3D**
- Red/cyan 3D glasses format
- View with traditional 3D glasses
- Single combined image

#### **Separate**
- Saves both images as separate files
- Best for manual processing
- Preserves full image quality

### 5. Save to Photos

1. Select your preferred export format
2. Tap **"Export & Save"**
3. Images saved to your Photos library
4. Access via Photos app

## Architecture

### Core Components

```
MetaGlassesCamera/
├── DualCameraManager.swift      # Dual camera capture logic
├── DualCaptureViewController.swift  # Main UI
├── AppDelegate.swift             # App entry point
└── Supporting Files/
    ├── Info.plist               # App configuration
    └── Package.swift            # Dependencies
```

### DualCameraManager

Manages connection and stereoscopic capture:

```swift
// Connect to glasses
try await cameraManager.connectToGlasses()

// Capture single stereo pair
let stereoPair = try await cameraManager.captureStereoImage()

// Capture multiple pairs
let pairs = try await cameraManager.captureMultipleStereoPairs(count: 3)

// Export formats
cameraManager.exportSideBySide(stereoPair)
cameraManager.exportAnaglyph(stereoPair)
```

### Stereo Pair Structure

```swift
struct StereoPair {
    let leftImage: UIImage      // Navigation camera
    let rightImage: UIImage     // Imaging camera
    let timestamp: Date
    let metadata: StereoPairMetadata
}
```

## Technical Details

### Dual Camera Capture

The app uses Swift's structured concurrency to capture from both cameras simultaneously:

```swift
try await withThrowingTaskGroup(of: (CameraType, Data).self) { group in
    // Capture from navigation camera
    group.addTask {
        try await session.captureFromCamera(.navigation)
    }

    // Capture from imaging camera
    group.addTask {
        try await session.captureFromCamera(.imaging)
    }

    // Collect results
    for try await (cameraType, imageData) in group {
        // Process images
    }
}
```

### Image Processing

#### Anaglyph Generation
- Extracts red channel from left (navigation) image
- Extracts cyan channels from right (imaging) image
- Combines using Core Image filters

#### Side-by-Side Generation
- Combines images horizontally
- Maintains aspect ratios
- Standard VR/3D viewing format

## Permissions

The app requires these permissions (configured in `Info.plist`):

| Permission | Purpose |
|------------|---------|
| Bluetooth | Connect to Meta glasses |
| Photo Library | Save captured images |
| Camera | Access glasses cameras |

## Troubleshooting

### Connection Issues

**Problem**: "Failed to connect to glasses"

**Solutions**:
1. Verify glasses are paired in Meta View app first
2. Restart Bluetooth on iPhone
3. Restart Meta glasses (press and hold button)
4. Move glasses closer to iPhone

### Capture Failures

**Problem**: "Incomplete stereo capture"

**Solutions**:
1. Check Bluetooth connection strength
2. Ensure glasses have sufficient battery
3. Try single camera capture first
4. Restart app and reconnect

### Image Quality

**Problem**: Images look misaligned

**Solutions**:
1. Hold glasses steady during capture
2. Use "Capture 3 Stereo Pairs" for better results
3. Ensure proper lighting conditions
4. Clean camera lenses on glasses

## Advanced Usage

### Custom Delay Between Captures

```swift
// Capture with custom timing
let pairs = try await cameraManager.captureMultipleStereoPairs(
    count: 5,
    delay: 3.0  // 3 seconds between captures
)
```

### Programmatic Export

```swift
// Export all formats
for pair in cameraManager.capturedStereoPairs {
    try cameraManager.saveStereoPair(pair, format: .sideBySide)
    try cameraManager.saveStereoPair(pair, format: .anaglyph)
    try cameraManager.saveStereoPair(pair, format: .separate)
}
```

## API Integration Notes

### Important: SDK Method Replacement Needed

The current implementation includes placeholder code for dual camera access. You'll need to update these methods based on the actual Meta Wearables SDK documentation:

In `DualCameraManager.swift`, replace:

```swift
// CURRENT PLACEHOLDER:
func captureFromCamera(_ cameraType: DualCameraManager.CameraType) async throws -> Data {
    fatalError("Replace with actual Meta SDK camera selection API")
}

// REPLACE WITH ACTUAL SDK METHOD:
func captureFromCamera(_ cameraType: DualCameraManager.CameraType) async throws -> Data {
    // Use actual Meta SDK API, for example:
    switch cameraType {
    case .navigation:
        return try await self.capturePhoto(from: .navigationCamera)
    case .imaging:
        return try await self.capturePhoto(from: .imagingCamera)
    }
}
```

Check the [official Meta Wearables documentation](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.3) for the exact API methods.

## Next Steps

1. **Test on Device**: Build and test on physical iPhone with glasses
2. **Customize UI**: Modify colors, layout in `DualCaptureViewController.swift`
3. **Add Features**: Implement gallery view, depth map generation, etc.
4. **Integrate SDK**: Update placeholder methods with actual Meta SDK calls

## Resources

- [Meta Wearables Developer Portal](https://developers.meta.com/wearables/)
- [iOS SDK Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.3)
- [Meta Ray-Ban Glasses](https://www.meta.com/ai-glasses/)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review Meta Wearables SDK documentation
3. Verify glasses firmware is up to date
4. Check Meta developer forums

## License

MIT License - See LICENSE file for details
