# Meta Ray-Ban Glasses Hardware Connection Guide

## Prerequisites

### 1. Hardware Requirements
- Meta Ray-Ban Smart Glasses (Stories or newer model)
- iPhone with iOS 15.0 or later
- Lightning/USB-C cable for device deployment
- Meta View app installed on iPhone

### 2. Software Requirements
- Xcode 15.0 or later
- Apple Developer Account (for device deployment)
- Meta Wearables DAT SDK (will be installed)

## Step 1: Install Meta Wearables DAT SDK

The Meta Wearables Device Access Technology (DAT) SDK enables communication with your glasses.

```bash
# Update Package.swift to include the real SDK
# This will download and integrate the Meta SDK
```

**Current Status**: The app currently uses a mock implementation for simulator testing. To connect to real glasses, we need to:
1. Uncomment the Meta SDK dependency in Package.swift
2. Switch from `TestDualCameraManager` to `DualCameraManager`
3. Build for a physical iOS device

## Step 2: Pair Your Glasses

### Initial Pairing
1. **Install Meta View app** from the App Store
2. **Turn on your glasses** - Hold the power button for 3 seconds
3. **Open Meta View app** and follow the pairing process:
   - Enable Bluetooth on your iPhone
   - The app will detect nearby glasses
   - Confirm pairing on both devices
4. **Grant permissions**:
   - Camera access
   - Bluetooth access
   - Local network access

### Verify Pairing
- Open Meta View app → Settings → Connected Devices
- Your glasses should appear as "Connected"
- Battery level should be visible

## Step 3: Configure App for Hardware

### A. Update Package.swift
```swift
// Uncomment the Meta SDK dependency:
dependencies: [
    .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", from: "0.3.0")
],
```

### B. Update Build Configuration
The app needs to be built for a physical device, not the simulator:

```bash
# Build for physical device
xcodebuild -scheme MetaGlassesCamera \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    build
```

### C. Code Signing
Add to your app's entitlements:
- `com.apple.developer.networking.bluetooth` - For Bluetooth access
- `com.apple.security.application-groups` - For data sharing

## Step 4: Switch to Production Camera Manager

### Update TestAppDelegate.swift
```swift
// Change from TestDualCameraManager to DualCameraManager
let cameraManager = DualCameraManager()  // Production version
let viewController = EnhancedTestDualCaptureViewController()
viewController.cameraManager = cameraManager
```

## Step 5: Deploy to iPhone

### Using Xcode
1. Connect iPhone via cable
2. Select your iPhone as the target device
3. Click "Run" or Cmd+R
4. Trust the developer certificate on iPhone if prompted

### Using CLI
```bash
# Build and install to connected device
xcodebuild -scheme MetaGlassesCamera \
    -destination 'platform=iOS,id=<YOUR_DEVICE_UDID>' \
    -allowProvisioningUpdates \
    install
```

## Step 6: Connect and Test

### First Launch
1. **Open the app** on your iPhone
2. **Ensure glasses are powered on** and paired via Meta View
3. **Tap "Connect"** in the app
4. **Grant permissions** when prompted:
   - Bluetooth access
   - Local network access
5. **Wait for connection** - The status should show "🟢 CONNECTED"

### Capture 3D Images
1. **Tap "CAPTURE 3D IMAGE"** button
2. The app will simultaneously capture from both cameras:
   - Navigation camera (left lens)
   - Imaging camera (right lens)
3. **View results** - Stereoscopic pair will display on screen
4. **AI Analysis** will run automatically (if enabled)

## Troubleshooting

### Glasses Won't Connect
- ✅ Ensure glasses are charged (>20% battery)
- ✅ Verify pairing in Meta View app
- ✅ Restart both glasses and iPhone
- ✅ Check Bluetooth is enabled on iPhone
- ✅ Ensure you're within 30 feet of the glasses

### App Crashes on Launch
- ✅ Check code signing certificate is valid
- ✅ Verify all entitlements are configured
- ✅ Review Xcode console for error messages
- ✅ Ensure Meta SDK version is compatible

### Camera Access Denied
- ✅ Settings → Privacy → Camera → Enable for MetaGlasses app
- ✅ Settings → Privacy → Bluetooth → Enable for MetaGlasses app

### Poor Image Quality
- ✅ Clean the camera lenses on glasses
- ✅ Ensure adequate lighting
- ✅ Update glasses firmware via Meta View app

## Architecture Changes for Hardware

### Simulator vs Hardware
| Feature | Simulator (Mock) | Hardware (Production) |
|---------|------------------|----------------------|
| Camera Manager | `TestDualCameraManager` | `DualCameraManager` |
| Session | `MockDATSession` | Real `DATSession` |
| Images | `RealisticMockImages` | Actual camera captures |
| Connection | Instant (simulated) | Bluetooth pairing required |
| Latency | None | ~100-500ms per capture |

### Key Differences
1. **Async Operations**: Real hardware has network latency
2. **Error Handling**: Connection drops, low battery, out of range
3. **Image Quality**: Real photos are higher resolution
4. **Permissions**: Bluetooth, camera, local network required

## Next Steps

1. **Update Package.swift** to include real Meta SDK
2. **Configure code signing** with your Apple Developer account
3. **Build for physical device** (not simulator)
4. **Deploy to iPhone** and test connection
5. **Capture real stereoscopic images** with your glasses

## Resources

- [Meta Wearables DAT SDK Documentation](https://github.com/facebook/meta-wearables-dat-ios)
- [Meta View App](https://apps.apple.com/app/meta-view/id1234567890)
- [Meta Ray-Ban Support](https://www.ray-ban.com/usa/discover-ray-ban-stories/clp)

## Current Status

✅ App is working in simulator with mock data
✅ UI is enhanced and functional
✅ Realistic mock images are generating
🔄 Ready to connect to physical hardware (follow steps above)
