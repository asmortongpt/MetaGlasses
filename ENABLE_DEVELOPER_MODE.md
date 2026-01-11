# 🔧 ENABLE DEVELOPER MODE (One-Time Setup)

## The Issue:
```
Developer Mode disabled
To use iPhone for development, enable Developer Mode in Settings → Privacy & Security.
```

---

## 📱 FIX IT IN 2 MINUTES:

### On Your iPhone:

1. **Open Settings** app

2. **Go to:** Settings → **Privacy & Security**

3. **Scroll down** to the bottom

4. **Tap:** "Developer Mode"

5. **Toggle ON** (it will be OFF/gray)

6. **iPhone will prompt to restart** → Tap "Restart"

7. **Wait for iPhone to restart** (~30 seconds)

8. **After restart:** Settings will ask you to confirm
   - Tap "Turn On" to confirm Developer Mode
   - Enter your passcode if asked

---

## ✅ THEN RUN THIS:

Once Developer Mode is enabled, run:

```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
./auto_deploy.sh
```

The app will build and install automatically to your iPhone!

---

## 🎯 WHY THIS IS NEEDED:

- iOS 16+ requires Developer Mode for installing apps from Xcode
- It's a security feature Apple added
- **One-time setup** - you never have to do this again
- All future app updates will work without this step

---

## ⏱️ TIMELINE:

1. Enable Developer Mode on iPhone (1 minute)
2. iPhone restarts (30 seconds)
3. Confirm Developer Mode (10 seconds)
4. Run ./auto_deploy.sh (2 minutes)
5. **APP IS ON YOUR iPHONE!** 🎉

---

**Total time: ~4 minutes from now!**

Go to your iPhone Settings → Privacy & Security → Developer Mode → Turn ON!
