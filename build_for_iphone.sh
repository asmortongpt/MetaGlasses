#!/bin/bash

echo "📱 BUILDING FOR PHYSICAL iPHONE"
echo "================================"
echo ""

# Check if iPhone is connected
echo "🔍 Step 1: Checking for connected iPhone..."
xcrun xctrace list devices 2>&1 | grep -i "iphone" | grep -v "Simulator"

echo ""
echo "🔨 Step 2: Opening Xcode with Package.swift..."
echo "   YOU NEED TO:"
echo "   1. Wait for Xcode to open"
echo "   2. Wait for package dependencies to load (30-60 seconds)"
echo "   3. At the top of Xcode, click the device dropdown"
echo "   4. Select YOUR IPHONE (not 'My Mac' or simulator)"
echo "   5. Click the ▶️ RUN button"
echo "   6. On first build, Xcode may ask for your Apple ID"
echo "   7. Sign in with your Apple ID if prompted"
echo "   8. App will build and install to your iPhone!"
echo ""

# Open in Xcode
open Package.swift

echo ""
echo "✅ Xcode is opening..."
echo "📱 Follow the 8 steps above to deploy to your iPhone!"
echo ""
echo "🎯 Once installed, you'll have the full app with:"
echo "   ✨ 110+ features"
echo "   🎤 Voice commands"
echo "   📡 Live streaming from glasses"
echo "   🤖 AI enhancement"
echo "   👤 VIP face recognition"
echo "   📸 4K video recording"
echo "   🎨 Professional tools"
echo ""
