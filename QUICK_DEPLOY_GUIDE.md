# MetaGlasses - Quick Deploy Guide

## ⚡ FASTEST Way to Install on Your iPhone

### Prerequisites
- ✅ iPhone with iOS 15.0+
- ✅ Mac with Xcode installed
- ✅ Lightning/USB-C cable
- ✅ App already built successfully

---

## 🚀 3-Step Deployment

### Step 1: Connect iPhone
```bash
# Connect your iPhone to Mac with cable
# Unlock iPhone
# Tap "Trust This Computer" if prompted
```

### Step 2: Open in Xcode
```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
open MetaGlassesApp.xcodeproj
```

### Step 3: Build & Run
1. In Xcode, select your iPhone from device dropdown (top toolbar)
2. Press **⌘R** or click ▶️ Play button
3. Wait for build and install (~30 seconds)

---

## 📱 First Launch

### On iPhone:
1. **Trust Developer** (if prompted):
   - Go to: Settings → General → VPN & Device Management
   - Tap: Apple Development: [Your Name]
   - Tap: "Trust"

2. **Grant Permissions**:
   - Camera: Allow
   - Microphone: Allow
   - Bluetooth: Allow
   - Photos: Allow

3. **Use the App**:
   - Home screen appears
   - Tap "Connect to Glasses" (will scan for Bluetooth devices)
   - Tap camera button to open live camera
   - Tap white circle to capture photos

---

## 🛠️ Troubleshooting

### "Untrusted Developer" Error
```
Settings → General → VPN & Device Management → Trust Developer
```

### "App Won't Install"
```bash
# Clean build and try again
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
xcodebuild clean -project MetaGlassesApp.xcodeproj -scheme MetaGlassesApp
# Then repeat Step 2 & 3 above
```

### "iPhone Not Recognized"
1. Unplug and replug cable
2. Unlock iPhone
3. Restart Xcode
4. Try different USB port

---

## ✅ Success Indicators

When working correctly, you'll see:
- Beautiful purple/blue gradient home screen
- "MetaGlasses AI" header with "110+ AI Features"
- "Connect to Glasses" button
- Four quick action cards (Camera, Gallery, Settings, AI Features)
- Featured capabilities list
- Floating white camera button (bottom right)

---

## 🎯 Quick Test

1. Launch app
2. Tap camera button (big white circle, bottom right)
3. See live camera feed
4. Tap white capture button
5. See flash animation
6. Photo saved to Photos app

**If all above works:** ✅ App is fully functional!

---

## 📞 Need Help?

Check these files:
- `COMPLETE_APP_SUMMARY.md` - Full documentation
- `BUILD_COMPLETE_REPORT.md` - Build details
- `READY_TO_USE.md` - Feature guide

Build logs:
```bash
# If build fails, check logs:
xcodebuild -project MetaGlassesApp.xcodeproj \
  -scheme MetaGlassesApp \
  -sdk iphoneos \
  build 2>&1 | tee build.log
```

---

**Last Updated:** January 9, 2026
**Status:** ✅ Build Successful | ✅ Ready for iPhone
