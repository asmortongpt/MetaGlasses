# MetaGlasses AI - Quick Start Guide

## Installation

### 1. Open in Xcode
```bash
cd /Users/andrewmorton/Documents/GitHub/MetaGlasses
open MetaGlassesApp.xcodeproj
```

### 2. Build & Run
1. Connect your iPhone 17 Pro via USB
2. Select device in Xcode toolbar
3. Press ⌘R to build and run
4. Grant permissions when prompted

## Features Overview

### 🤖 AI Assistant
**Tab**: AI (Brain icon)

**What it does**:
- Voice-activated AI assistant powered by ChatGPT-4
- Real-time image analysis with GPT-4 Vision
- Personal knowledge base with memory

**How to use**:
1. Tap microphone icon and speak
2. Or type your question
3. Upload images for AI analysis
4. Everything is remembered in your personal knowledge base

**Example commands**:
- "What do you see?" (analyzes current scene)
- "Remember that I love pizza"
- "What did we talk about yesterday?"
- "Analyze this image"

### 📸 Camera Features
**Tab**: Camera (Camera icon)

**What it does**:
- Professional photo capture (HDR, RAW, ProRAW)
- 4K/8K video recording
- Facial recognition with real-time detection
- Depth mapping

**How to use**:
1. Tap camera button to take photo
2. Hold for video recording
3. Face detection shows automatically
4. Photos auto-save to library

### 👓 Meta Ray-Ban Integration
**Status**: Top bar

**What it does**:
- Connects to your Meta Ray-Ban smart glasses
- Remote camera trigger via Bluetooth
- Battery monitoring
- Command forwarding

**How to use**:
1. Tap "Scan" to find glasses
2. Connect to "RB Meta 00DG"
3. Use "Trigger Meta Glasses Camera" button
4. Photos sync automatically

### 💡 Smart Features
**Tab**: Features (CPU icon)

**What it does**:
- 110+ AI and camera features
- Toggle features on/off
- Feature categories and organization

**Categories**:
- Camera & Capture (15 features)
- AI & Vision (20 features)
- Personal AI (15 features)
- Pro Tools (15 features)
- Smart Features (15 features)
- Location (10 features)
- Social (10 features)
- Accessibility (10 features)

### 🖼️ Gallery
**Tab**: Gallery (Photo stack icon)

**What it does**:
- View all captured photos
- Quick access to recent media
- Swipe to navigate
- Tap for full screen

## Advanced Features

### Voice Assistant

**Starting a conversation**:
1. Tap microphone icon
2. Wait for blue indicator
3. Speak your question
4. Response is shown AND spoken

**Context awareness**:
- Sees what your camera sees
- Knows your location
- Remembers past conversations
- Learns your preferences

**Example conversation**:
```
You: "What can you see?"
AI: "I see a beautiful sunset over the ocean with orange and pink clouds."

You: "Remember this as my favorite sunset spot"
AI: "I've stored this information. I'll remember your favorite sunset spot."

[Later...]
You: "Where was that sunset spot?"
AI: "Your favorite sunset spot is [location]. Would you like directions?"
```

### Image Analysis

**Upload image**:
1. Tap photo icon in AI chat
2. Select from library or take new photo
3. Wait for analysis (~5 seconds)
4. View detailed results

**What you get**:
- AI description of the scene
- Detected objects with confidence scores
- Recognized text (OCR)
- Smart suggestions (e.g., "Use HDR mode")
- Scene classifications

**Example analysis**:
```
Image: Photo of the Eiffel Tower
AI Analysis:
- "This is the iconic Eiffel Tower in Paris, France, photographed during golden hour"
- Detected: Tower (98%), People (87%), Sky (95%)
- Suggestions: "Try portrait mode for better depth"
```

### Knowledge Base

**What gets stored**:
- All conversations
- Analyzed images
- Personal facts you share
- Location context
- Timestamps

**Searching knowledge**:
```
You: "What do you remember about my trip to Paris?"
AI: [Searches knowledge base, finds 5 related items]
    "You visited the Eiffel Tower on Jan 5, took 15 photos,
     and mentioned you loved the French cuisine..."
```

**Export/Import**:
- Settings → Knowledge Base → Export
- Backup to iCloud or share with other devices
- Import to restore memory

### Multi-LLM Orchestration

**Automatic model selection**:
- Vision tasks → GPT-4 Vision or Gemini Pro Vision
- Long context → Claude Opus (200k tokens)
- Quick responses → GPT-3.5 Turbo or Gemini Pro
- Creative tasks → GPT-4
- Analytical → Claude

**Cost optimization**:
- Daily budget: $10
- Switches to free tier (Gemini) when limit approached
- Smart fallbacks if primary model fails

**You don't need to do anything** - it picks the best model automatically!

## Settings

### AI Settings
- **Model selection**: Auto (recommended) or Manual
- **Temperature**: Creativity level (0 = factual, 1 = creative)
- **Max tokens**: Response length limit
- **Cost limit**: Daily spending cap

### Camera Settings
- **HDR**: On/Off (default: On)
- **RAW capture**: On/Off (default: Off - uses more storage)
- **Video quality**: 1080p / 4K / 8K
- **Depth data**: On/Off (if supported)

### Voice Settings
- **Language**: English (more languages coming)
- **Speech rate**: Slow / Normal / Fast
- **Voice**: Choose TTS voice
- **Auto-speak**: On/Off (speak AI responses)

### Privacy Settings
- **Store conversations**: On/Off
- **Location tracking**: On/Off
- **Clear knowledge base**: Delete all stored data
- **Export data**: Backup your data

## Troubleshooting

### "AI not responding"
**Cause**: No internet connection
**Solution**:
- Check WiFi/cellular
- Camera features still work offline
- Responses will queue and send when online

### "Meta glasses won't connect"
**Cause**: Bluetooth off or out of range
**Solution**:
- Enable Bluetooth in Settings
- Move closer to glasses
- Restart glasses by power cycling
- Tap "Scan" again

### "Microphone not working"
**Cause**: Permission denied
**Solution**:
- Settings → MetaGlasses → Microphone → Enable
- Restart app
- Grant permission when prompted

### "Photos not saving"
**Cause**: Storage full or permission denied
**Solution**:
- Check iPhone storage
- Settings → MetaGlasses → Photos → Enable
- Free up space by deleting old photos

### "App crashes"
**Cause**: Memory pressure or bug
**Solution**:
- Force quit and restart
- Clear knowledge base if very large (>10k items)
- Check for app updates
- Report crash via feedback

## Tips & Tricks

### 1. Voice Commands
- Use natural language - no special phrases needed
- Say "Hey assistant" to wake (optional)
- Interrupt by tapping microphone again
- Voice commands work hands-free

### 2. Image Analysis
- Upload multiple images in one conversation
- Ask follow-up questions about images
- Images are automatically stored in knowledge base
- Use technical analysis mode for photography tips

### 3. Knowledge Base
- Tag important memories with keywords
- Ask "What do you know about [topic]?"
- Export weekly for backup
- Import previous exports to combine knowledge

### 4. Battery Optimization
- Disable features you don't use
- Turn off auto-speak if not needed
- Use WiFi instead of cellular for AI
- Close app when not in use

### 5. Best Results
- Speak clearly and close to microphone
- Use good lighting for image analysis
- Provide context: "This is my dog Rex"
- Ask specific questions for better answers

## Keyboard Shortcuts (Xcode)

- **⌘R**: Build and run
- **⌘B**: Build only
- **⌘.**: Stop running
- **⌘⇧K**: Clean build folder
- **⌘⇧L**: Show library (UI components)

## Support

### Getting Help
- Check IMPLEMENTATION_REPORT.md for technical details
- Review code comments in source files
- Ask the AI assistant within the app!

### Feedback
- Feature requests: Document in app
- Bug reports: Note reproduction steps
- Performance issues: Monitor memory/CPU in Xcode

### Updates
- Check GitHub for latest version
- Pull latest changes: `git pull origin main`
- Rebuild after updates: ⌘⇧K then ⌘B

## What's Next?

### Coming Soon
- [ ] On-device LLM for offline AI
- [ ] AR overlays in camera view
- [ ] Real-time translation (60+ languages)
- [ ] Social features (share knowledge bases)
- [ ] Custom AI model fine-tuning
- [ ] Integration with other smart devices

### Roadmap
- **Q1 2026**: App Store launch
- **Q2 2026**: AR features, translation
- **Q3 2026**: On-device AI, social features
- **Q4 2026**: Custom models, enterprise features

---

**Version**: 2.0.0
**Last Updated**: January 9, 2026
**Platform**: iOS 17.0+
**Device**: iPhone 17 Pro (optimized)
**Glasses**: Meta Ray-Ban (compatible)

Enjoy your AI-powered smart glasses! 🤖👓
