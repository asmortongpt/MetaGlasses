# Quick Start: Connect to Meta Ray-Ban Glasses

## 🎯 Current Status
✅ Your app is working perfectly in the **iOS Simulator** with mock data
🔄 Now ready to connect to **real Meta Ray-Ban glasses hardware**

---

## 📋 Prerequisites Checklist

Before starting, ensure you have:

- [ ] **Meta Ray-Ban Smart Glasses** (charged >20%)
- [ ] **iPhone** running iOS 15.0 or later
- [ ] **USB cable** to connect iPhone to Mac
- [ ] **Meta View app** installed on iPhone ([Download](https://apps.apple.com/app/meta-view))
- [ ] **Apple Developer Account** (for code signing)

---

## 🚀 Quick Setup (3 Steps)

### Step 1: Pair Your Glasses
```
1. Turn on glasses (hold power button 3 seconds)
2. Open Meta View app on iPhone
3. Follow pairing wizard
4. Grant Bluetooth permissions
5. Confirm "Connected" status in Meta View
```

### Step 2: Configure App for Hardware
```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
./setup_hardware.sh
```

This script will:
- ✅ Enable Meta Wearables DAT SDK
- ✅ Create production AppDelegate
- ✅ Configure Bluetooth permissions
- ✅ Create hardware build script

### Step 3: Build and Deploy
```bash
# Connect your iPhone via cable, then:
./build_for_hardware.sh
```

---

## 🎮 Using the App

### First Launch
1. **Open MetaGlasses app** on your iPhone
2. **Ensure glasses are on** and paired (check Meta View app)
3. **Tap "Connect"** - should show "🟢 CONNECTED" within 5 seconds
4. **Grant permissions** when prompted

### Capture 3D Images
1. **Tap "🎥 CAPTURE 3D IMAGE"**
2. Wait 1-2 seconds for dual capture
3. **View stereoscopic pair** on screen
4. AI analysis runs automatically

### View Results
- **Left panel**: Navigation camera image
- **Right panel**: Imaging camera image
- **Combined**: Creates 3D stereoscopic effect

---

## 🔧 Troubleshooting

### "Connection Failed"
```
✅ Check glasses battery (>20%)
✅ Verify paired in Meta View app
✅ Toggle Bluetooth off/on
✅ Restart both glasses and iPhone
✅ Move within 30 feet of glasses
```

### "Build Failed"
```
✅ Connect iPhone via cable
✅ Unlock iPhone and trust computer
✅ Check Apple Developer account is active
✅ Ensure no other Xcode projects are building
```

### "Permission Denied"
```
iPhone Settings → Privacy & Security → Bluetooth
Enable for MetaGlasses app

iPhone Settings → Privacy & Security → Local Network
Enable for MetaGlasses app
```

---

## 📊 Simulator vs Hardware Comparison

| Feature | Simulator Mode | Hardware Mode |
|---------|---------------|---------------|
| **Camera** | Mock images | Real photos from glasses |
| **Connection** | Instant | Bluetooth pairing required |
| **Latency** | None | ~200-500ms |
| **Image Quality** | Synthetic 800x600 | Real 1280x720 |
| **Testing** | ✅ No hardware needed | ⚠️ Requires physical glasses |
| **Build Target** | iOS Simulator | Physical iPhone |

---

## 🎯 What Changes for Hardware

### Architecture
```
SIMULATOR MODE:
TestAppDelegate → TestDualCameraManager → MockDATSession → RealisticMockImages

HARDWARE MODE:
ProductionAppDelegate → DualCameraManager → Real DATSession → Actual glasses cameras
```

### Key Differences
1. **Real Bluetooth Connection**: Must pair glasses via Meta View app first
2. **Network Latency**: Captures take 200-500ms instead of instant
3. **Error Handling**: Connection drops, low battery, out of range
4. **Permissions**: Must grant Bluetooth, camera, local network access
5. **Build Process**: Must deploy to physical device with code signing

---

## 📱 Meta View App Configuration

### Initial Setup
1. Download Meta View from App Store
2. Create/login to Meta account
3. Turn on glasses
4. Follow pairing flow
5. Update glasses firmware if prompted

### Settings to Check
- **Bluetooth**: Must be "Connected"
- **Battery**: Should show percentage
- **Firmware**: Update to latest version
- **Capture Quality**: Set to "High" for best results

---

## 🔐 Permissions Required

Your iPhone will prompt for these when app launches:

| Permission | Why Needed |
|-----------|------------|
| **Bluetooth** | Connect to glasses wirelessly |
| **Camera** | Access glasses camera feeds |
| **Local Network** | Direct communication with glasses |
| **Photo Library** | Save captured 3D images (optional) |

**Important**: Must grant ALL permissions for app to work!

---

## 🎉 Success Criteria

You'll know it's working when:

✅ App shows "🟢 CONNECTED" status
✅ Battery level displays from glasses
✅ Capture button becomes blue and animated
✅ Tapping capture shows real photos from glasses
✅ Both camera panels show actual scene images
✅ AI analysis detects real objects in photos

---

## 📞 Getting Help

### Documentation
- 📖 Full guide: `HARDWARE_CONNECTION_GUIDE.md`
- 🔧 Setup script: `./setup_hardware.sh`
- 🚀 Build script: `./build_for_hardware.sh`

### Meta Resources
- [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- [Meta View Support](https://www.meta.com/help/quest/articles/ray-ban-stories)
- [Ray-Ban Stories FAQ](https://www.ray-ban.com/usa/ray-ban-stories-support)

### Common Issues
- Glasses not appearing in Meta View: Turn glasses off/on
- Connection timeout: Move closer to glasses
- Low quality images: Clean camera lenses
- Battery drains fast: Update glasses firmware

---

## ⏭️ Next Steps

After successful hardware connection:

1. **Test all AI features** with real images:
   - Face detection
   - Object recognition
   - Text extraction (OCR)
   - RAG-enhanced analysis

2. **Optimize capture settings**:
   - Adjust image resolution
   - Configure compression quality
   - Set capture timeout values

3. **Add advanced features**:
   - Depth estimation from stereo pairs
   - 3D reconstruction
   - Real-time video streaming
   - Batch capture mode

4. **Deploy to production**:
   - TestFlight distribution
   - App Store submission
   - User testing and feedback

---

## 📊 Timeline Estimate

| Task | Time |
|------|------|
| Pair glasses via Meta View | 5 minutes |
| Run setup_hardware.sh | 2 minutes |
| Build and deploy to iPhone | 5 minutes |
| First successful connection | 2 minutes |
| **Total** | **~15 minutes** |

---

**🎬 You're ready to go! Start with:**
```bash
./setup_hardware.sh
```
