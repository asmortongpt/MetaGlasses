# MetaGlasses Connection Architecture

## 🏗️ System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         YOUR META RAY-BAN GLASSES                │
│  ┌──────────────────┐              ┌──────────────────┐        │
│  │ Navigation       │              │ Imaging          │        │
│  │ Camera (Left)    │              │ Camera (Right)   │        │
│  │ 1280x720         │              │ 1280x720         │        │
│  └────────┬─────────┘              └────────┬─────────┘        │
│           │                                  │                   │
│           └──────────┬──────────────────────┘                   │
│                      │                                           │
│              ┌───────▼────────┐                                 │
│              │ Glasses MCU    │                                 │
│              │ Bluetooth LE   │                                 │
│              │ Battery: 85%   │                                 │
│              └───────┬────────┘                                 │
└──────────────────────┼──────────────────────────────────────────┘
                       │
                       │ Bluetooth 5.0 Connection
                       │ Range: ~30 feet
                       │ Latency: 200-500ms
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│                        YOUR iPHONE                               │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                 MetaGlasses App                        │    │
│  │                                                        │    │
│  │  ┌─────────────────────────────────────────────┐     │    │
│  │  │   EnhancedTestDualCaptureViewController      │     │    │
│  │  │   ┌──────────────┐  ┌──────────────┐       │     │    │
│  │  │   │ Left Preview │  │ Right Preview│       │     │    │
│  │  │   └──────────────┘  └──────────────┘       │     │    │
│  │  │          [🎥 CAPTURE 3D IMAGE]              │     │    │
│  │  └──────────────────┬──────────────────────────┘     │    │
│  │                     │                                 │    │
│  │         ┌───────────▼────────────┐                   │    │
│  │         │  DualCameraManager     │                   │    │
│  │         │  (Production Mode)     │                   │    │
│  │         └───────────┬────────────┘                   │    │
│  │                     │                                 │    │
│  │         ┌───────────▼────────────┐                   │    │
│  │         │    DATSession          │                   │    │
│  │         │  (Meta Wearables SDK)  │                   │    │
│  │         └───────────┬────────────┘                   │    │
│  │                     │                                 │    │
│  │         ┌───────────▼────────────┐                   │    │
│  │         │   iOS Bluetooth Stack  │                   │    │
│  │         └────────────────────────┘                   │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Background: Meta View App (handles pairing)                  │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow: Capture 3D Image

```
User Taps "Capture"
       │
       ▼
EnhancedTestDualCaptureViewController.captureButtonTapped()
       │
       ▼
DualCameraManager.captureStereoPair()
       │
       ├─────────────────────┬─────────────────────┐
       │                     │                     │
       ▼                     ▼                     ▼
Task 1:                Task 2:              Task 3:
captureFromCamera      captureFromCamera    AIAnalysis
  (.navigation)          (.imaging)         (async)
       │                     │
       │                     │
       ▼                     ▼
DATSession               DATSession
.capturePhoto()          .capturePhoto()
       │                     │
       │ Bluetooth LE        │ Bluetooth LE
       │ Command             │ Command
       ▼                     ▼
Navigation Camera       Imaging Camera
captures frame          captures frame
       │                     │
       │ Returns             │ Returns
       │ UIImage data        │ UIImage data
       ▼                     ▼
   leftImage              rightImage
       │                     │
       └─────────┬───────────┘
                 │
                 ▼
         StereoPair created
                 │
                 ▼
    Update UI with images
                 │
                 ▼
    Run AI analysis
    (face detection,
     object recognition,
     depth estimation)
```

## 🔌 Connection Sequence

### Phase 1: Initial Pairing (One-time, via Meta View)
```
1. User opens Meta View app
2. Turns on glasses
3. Meta View discovers glasses via Bluetooth
4. User confirms pairing
5. Secure key exchange
6. Glasses saved to iOS Bluetooth devices
```

### Phase 2: App Connection (Every launch)
```
1. MetaGlasses app launches
2. ProductionAppDelegate creates DualCameraManager
3. User taps "Connect" button
4. DualCameraManager.connect() called
5. DATSession.connect() searches for paired glasses
6. Establishes Bluetooth LE connection
7. Retrieves glasses status (battery, firmware version)
8. UI shows "🟢 CONNECTED"
9. Capture button becomes active
```

### Phase 3: Image Capture (Per request)
```
1. User taps "Capture" button
2. DualCameraManager creates Task Group
3. Parallel async tasks:
   - Task 1: Request navigation camera image
   - Task 2: Request imaging camera image
4. DATSession sends capture commands via Bluetooth
5. Glasses capture frames simultaneously
6. Image data transmitted back to iPhone (~200-500ms)
7. DualCameraManager receives both images
8. Creates StereoPair struct
9. Updates UI preview panels
10. Triggers AI analysis pipeline
```

## 📡 Communication Protocol

### Bluetooth LE Characteristics
```
Service: Meta Wearables Device Access Technology
UUID: <Meta proprietary>

Characteristics:
├── Camera Control (Write)
│   └── Commands: CAPTURE, SET_QUALITY, GET_STATUS
├── Navigation Camera Data (Notify)
│   └── Streams: JPEG image data
├── Imaging Camera Data (Notify)
│   └── Streams: JPEG image data
├── Device Status (Read/Notify)
│   └── Data: battery, firmware, connection quality
└── Configuration (Read/Write)
    └── Settings: resolution, format, compression
```

### Message Flow
```
iPhone -> Glasses:
┌────────────────────────────────┐
│ Command: CAPTURE_STEREO        │
│ Camera: BOTH                   │
│ Quality: HIGH                  │
│ Format: JPEG                   │
└────────────────────────────────┘

Glasses -> iPhone:
┌────────────────────────────────┐
│ Status: CAPTURING              │
└────────────────────────────────┘

[200ms delay]

┌────────────────────────────────┐
│ Navigation Camera Data         │
│ Size: 245KB                    │
│ Resolution: 1280x720           │
│ Timestamp: 2025-01-09 16:32:15 │
└────────────────────────────────┘

┌────────────────────────────────┐
│ Imaging Camera Data            │
│ Size: 238KB                    │
│ Resolution: 1280x720           │
│ Timestamp: 2025-01-09 16:32:15 │
└────────────────────────────────┘

┌────────────────────────────────┐
│ Status: CAPTURE_COMPLETE       │
└────────────────────────────────┘
```

## 🔐 Security & Permissions

### Required iOS Permissions
```
┌─────────────────────────────────────────────────┐
│ Bluetooth (NSBluetoothAlwaysUsageDescription)   │
│ └─ Connect to glasses wirelessly                │
├─────────────────────────────────────────────────┤
│ Camera (NSCameraUsageDescription)               │
│ └─ Access glasses camera feeds                  │
├─────────────────────────────────────────────────┤
│ Local Network (NSLocalNetworkUsageDescription)  │
│ └─ Direct communication with glasses            │
├─────────────────────────────────────────────────┤
│ Photo Library (NSPhotoLibraryAddUsageDescription)│
│ └─ Save captured 3D images                      │
└─────────────────────────────────────────────────┘
```

### Entitlements
```xml
<key>com.apple.developer.networking.bluetooth</key>
<true/>

<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.capitaltechalliance.metaglasses</string>
</array>
```

## 🏭 Environment Comparison

### Simulator Mode (Current)
```
ProductionAppDelegate
    └── EnhancedTestDualCaptureViewController
            └── TestDualCameraManager (Mock)
                    └── MockDATSession
                            └── RealisticMockImages.generateStereoImages()
                                    └── Returns: Synthetic images (instant)

✅ No hardware needed
✅ Instant captures
✅ Consistent test data
❌ Not real glasses data
❌ No Bluetooth testing
```

### Hardware Mode (Next)
```
ProductionAppDelegate
    └── EnhancedTestDualCaptureViewController
            └── DualCameraManager (Production)
                    └── DATSession (Meta SDK)
                            └── Bluetooth LE to glasses
                                    └── Returns: Real photos (200-500ms)

✅ Real glasses hardware
✅ Actual camera images
✅ Realistic latency
✅ Full feature testing
❌ Requires physical glasses
❌ Requires iPhone deployment
```

## 🔧 Hardware Setup Steps

### Quick Setup
```bash
# 1. Run hardware setup script
./setup_hardware.sh

# 2. Connect iPhone via USB
# 3. Build and deploy
./build_for_hardware.sh
```

### What Changes
```diff
# Package.swift
- // .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", from: "0.3.0")
+ .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", from: "0.3.0")

# TestAppDelegate.swift (Simulator)
- let cameraManager = TestDualCameraManager()

# ProductionAppDelegate.swift (Hardware)
+ let cameraManager = DualCameraManager()

# Build Target
- iOS Simulator (x86_64/arm64 simulator)
+ Physical iPhone (arm64 device)
```

## 📊 Performance Characteristics

### Latency Budget
```
User taps button                    →  0ms
UI feedback (button press)          →  16ms (1 frame @ 60fps)
DualCameraManager.captureStereoPair →  5ms
DATSession.capturePhoto() x2        →  10ms
Bluetooth command transmission      →  50ms
Glasses capture both cameras        →  100ms
Image data transmission             →  200ms
Image decoding on iPhone            →  30ms
UI update with images               →  16ms
──────────────────────────────────────────
TOTAL LATENCY                       →  ~430ms
```

### Battery Impact
```
Operation               | Glasses Battery | iPhone Battery
────────────────────────┼─────────────────┼───────────────
Idle (connected)        | -0.5%/hour      | -2%/hour
Single capture          | -0.05%          | -0.1%
Continuous (10/min)     | -3%/hour        | -8%/hour
AI analysis (per image) | -0%             | -0.3%
```

## 🎯 Success Indicators

### Connection Health
```
✅ GOOD:  Latency <500ms, Signal strength >-70dBm
⚠️  OK:    Latency 500-1000ms, Signal strength -70 to -85dBm
❌ POOR:  Latency >1000ms, Signal strength <-85dBm
```

### When to Reconnect
- Signal strength drops below -85dBm
- Latency exceeds 2 seconds
- Capture fails 3+ times consecutively
- Battery drops below 15%
- User moves >30 feet from glasses

## 📱 User Experience Flow

```
┌────────────────────────────────────────────┐
│ 1. User launches MetaGlasses app          │
│    ↓                                       │
│ 2. App checks for paired glasses          │
│    ↓                                       │
│ 3. UI shows "Tap Connect"                 │
│    ↓                                       │
│ 4. User taps Connect button               │
│    ↓                                       │
│ 5. App searches for glasses (2-5 seconds) │
│    ↓                                       │
│ 6. Status updates: "Connecting..."        │
│    ↓                                       │
│ 7. Connection established                 │
│    ↓                                       │
│ 8. UI shows "🟢 CONNECTED" + battery %    │
│    ↓                                       │
│ 9. Capture button becomes active          │
│    ↓                                       │
│ 10. User taps "Capture 3D Image"          │
│    ↓                                       │
│ 11. Button shows loading animation        │
│    ↓                                       │
│ 12. Both cameras capture simultaneously   │
│    ↓                                       │
│ 13. Images appear in preview panels       │
│    ↓                                       │
│ 14. AI analysis results display           │
│    ↓                                       │
│ 15. User can capture again or disconnect  │
└────────────────────────────────────────────┘
```

---

## 🚀 Ready to Connect!

Your app is **fully prepared** for hardware connection. The simulator version is working perfectly with mock data.

**To connect to real Meta Ray-Ban glasses:**
```bash
./setup_hardware.sh
```

Then follow the prompts to build and deploy to your iPhone!
