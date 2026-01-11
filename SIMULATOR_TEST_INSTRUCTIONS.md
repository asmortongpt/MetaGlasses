# 🧪 CLI Simulator Testing - Step by Step

## ✅ Easiest Method: Open in Xcode

Since Swift Package Manager CLI doesn't support UIKit builds, use Xcode:

```bash
# 1. Open project
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
open Package.swift

# 2. Xcode will open automatically
# 3. Wait ~30 seconds for package resolution
# 4. Click the device selector → Choose any iPhone simulator
# 5. Press ⌘R (or click Play button)
# 6. App launches in simulator!
```

## 📱 Using xcodebuild (Advanced)

For fully automated CLI testing:

```bash
# Build and run
xcodebuild \
  -scheme MetaGlassesCamera \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  clean build

# Install on simulator
xcrun simctl install booted ./build/Products/Debug-iphonesimulator/MetaGlassesCamera.app

# Launch
xcrun simctl launch booted com.metaglasses.camera
```

## 🎯 What Will Happen

When the app launches in the simulator:

1. **Orange TEST MODE header** appears
2. Status shows "Not Connected (Simulator)"  
3. Tap **"Connect (Mock)"** → Instant connection
4. Tap **"🤖 Capture with AI Analysis"**
5. Watch AI pipeline execute in real-time
6. Full analysis displayed in ~5-7 seconds

## 🔍 Viewing Console Output

```bash
# Watch simulator logs in real-time
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "MetaGlasses"' --level debug

# Or use Console.app
open -a Console
# Filter: process:MetaGlassesCamera
```

You'll see:
```
🧪 MetaGlasses TEST MODE launched
✅ Test session initialized (Mock mode)
📸 Capturing stereo pair...
🤖 AI: Analyzing scene...
✅ Analysis complete
```

## ⚡ Quick Start (RECOMMENDED)

Just run:
```bash
open Package.swift
```

Then press ⌘R in Xcode. **That's it!**

---

**Why Xcode is needed**: UIKit, Vision, CoreML frameworks require iOS SDK which is only available through Xcode, not standalone Swift Package Manager CLI builds.
