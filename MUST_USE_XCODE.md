# ⚠️ MUST USE XCODE GUI - Command Line Won't Work

## Why Command Line Failed:
```
Error: "MetaGlassesApp" requires signing with a development certificate.
Enable development signing in the Signing & Capabilities editor.
```

**This MUST be done in Xcode's GUI** - there's no command-line way to set up signing for the first time.

---

## 🎯 WHAT YOU MUST DO (3 Minutes):

### 1. Open Xcode
- Look at your dock at the bottom of the screen
- Find the Xcode icon (blue hammer icon)
- **Click it once** to bring Xcode to the front

### 2. If Xcode Opens to Welcome Screen:
- Click "Open a project or file"
- Navigate to: `/Users/andrewmorton/Documents/GitHub/MetaGlasses`
- Select `Package.swift`
- Click "Open"

### 3. Wait for Project to Load
- You'll see "Indexing..." at the top
- Wait 30-60 seconds for it to finish
- When done, you'll see the project files on the left

### 4. Set Up Signing (THIS IS THE KEY STEP!)

**In Xcode's left sidebar:**
- Click on "MetaGlassesApp" (the blue icon at the very top)
- In the main panel, you'll see tabs: General, Signing & Capabilities, etc.
- **Click "Signing & Capabilities"** tab

**You'll see:**
- [ ] "Automatically manage signing" checkbox ← CHECK THIS!
- Team: None ← Click dropdown

**Select a team:**
- If you see your name/Apple ID → Select it
- If you see "None" → Click "Add Account..."
  - Sign in with your Apple ID (the one you use for App Store)
  - Xcode will create a free developer certificate
  - Select your name as the Team

**Once you select a team:**
- ✅ "Signing certificate: Apple Development"
- ✅ "Provisioning profile: Xcode Managed Profile"

### 5. Select Your iPhone
- Top of Xcode: Click where it says device name
- Under "iOS Devices" select **"iPhone (26.2)"**

### 6. Build!
- Click **▶️ Play button** at top left
- Wait 2-3 minutes
- App installs to your iPhone automatically!

---

## 📱 YOU'LL KNOW IT WORKED WHEN:

- Xcode shows "Running MetaGlassesApp on iPhone"
- Your iPhone shows the app icon
- App launches automatically
- You see the blue/purple gradient interface!

---

## 💡 THIS IS THE ONLY WAY

Apple requires code signing for iOS apps.
The command line can't create certificates.
**You MUST use Xcode GUI for first-time setup.**

After this first time, you can use command line!

---

**Go to your dock, click Xcode, follow the 6 steps above!** 🚀
