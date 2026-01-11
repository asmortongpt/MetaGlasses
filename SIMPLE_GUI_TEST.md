# ✅ EASIEST WAY: Test in Xcode GUI

The CLI build has dependency complexities. Use Xcode GUI instead:

## 🚀 3-Step Process (Takes 2 minutes)

### Step 1: Open in Xcode
```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
open Package.swift
```

### Step 2: Wait for Resolution
- Xcode opens automatically
- Yellow "Resolving packages..." appears at top
- Wait ~30 seconds until it finishes

### Step 3: Build & Run
1. Click **device selector** (top center, shows "My Mac" or similar)
2. Select **"iPhone 17 Pro"** simulator
3. Press **⌘R** (or click Play ▶️ button)
4. App builds and launches!

## 🎯 What You'll See

```
┌─────────────────────────────┐
│  🧪 TEST MODE - AI Enhanced │
├─────────────────────────────┤
│  [Connect (Mock)]           │
│  [🤖 Capture with AI]       │
│  📊 AI Analysis...          │
└─────────────────────────────┘
```

## ⚡ Why Xcode GUI?

The app uses:
- UIKit (iOS UI framework)
- Vision (AI framework)
- Core Image (image processing)
- Combine (reactive framework)

These require iOS SDK and proper linking, which Xcode GUI handles automatically.

## 🔧 If Build Fails in Xcode

1. **Product → Clean Build Folder** (⇧⌘K)
2. **File → Packages → Reset Package Caches**
3. **File → Packages → Resolve Package Versions**
4. Try **⌘R** again

## 📱 Alternative: Create Simple iOS Project

If Swift Package still has issues:

```bash
# Create new iOS app in Xcode:
# File → New → Project → iOS → App
# Name it "MetaGlassesTest"
# Copy files from Sources/MetaGlassesCamera/Testing/ into it
# Build and run
```

## 🎉 Bottom Line

**Just use: `open Package.swift` and press ⌘R in Xcode!**

That's the standard way iOS developers test apps.
CLI building for iOS is complex and not typically used.
