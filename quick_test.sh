#!/bin/bash

# Quick Test Script - Simple approach using Xcode command line

echo "🧪 MetaGlasses Quick Test"
echo "=========================="
echo ""

# Check if xcodebuild exists
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode command line tools not found"
    echo "Install with: xcode-select --install"
    exit 1
fi

# Check if project exists
if [ ! -f "Package.swift" ]; then
    echo "❌ Package.swift not found"
    echo "Run this script from the MetaGlasses directory"
    exit 1
fi

echo "📦 Generating Xcode project from Swift Package..."
swift package generate-xcodeproj 2>&1 | grep -v "warning:"

if [ ! -f "MetaGlasses.xcodeproj/project.pbxproj" ]; then
    echo "❌ Failed to generate Xcode project"
    exit 1
fi

echo "✅ Xcode project generated"
echo ""

# Get simulator
SIMULATOR_ID=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | head -1 | grep -o '[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}')

if [ -z "$SIMULATOR_ID" ]; then
    echo "❌ No iPhone simulator found"
    echo "Create one in Xcode: Window → Devices and Simulators"
    exit 1
fi

SIMULATOR_NAME=$(xcrun simctl list devices available 2>/dev/null | grep "$SIMULATOR_ID" | sed 's/.*(\(.*\)).*/\1/' | awk '{print $1, $2, $3}')
echo "📱 Using simulator: $SIMULATOR_NAME"
echo ""

# Boot simulator
echo "🔌 Booting simulator..."
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || echo "   Already booted"
sleep 2

# Open Simulator.app
open -a Simulator --background
sleep 1

echo ""
echo "🔨 Building for simulator..."
echo "   (This may take 30-60 seconds...)"
echo ""

# Build
xcodebuild \
    -project MetaGlasses.xcodeproj \
    -scheme MetaGlassesCamera \
    -sdk iphonesimulator \
    -destination "id=$SIMULATOR_ID" \
    -derivedDataPath ./build \
    clean build \
    2>&1 | grep -E "error:|warning:|Build succeeded|Testing"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    echo "📲 Installing on simulator..."

    # Find the app
    APP_PATH=$(find ./build -name "*.app" -type d | head -1)

    if [ -n "$APP_PATH" ]; then
        xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

        # Launch
        BUNDLE_ID="MetaGlassesCamera"  # Default
        echo "🚀 Launching app..."
        xcrun simctl launch --console "$SIMULATOR_ID" "$BUNDLE_ID" &

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎉 SUCCESS! App is running!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Look for:"
        echo "  • Orange 'TEST MODE' header"
        echo "  • 'Connect (Mock)' button"
        echo "  • Dual camera preview panes"
        echo ""
        echo "Try:"
        echo "  1. Tap 'Connect (Mock)'"
        echo "  2. Tap '🤖 Capture with AI Analysis'"
        echo "  3. Watch AI analysis happen!"
        echo ""
    else
        echo "⚠️  Could not find built app"
    fi
else
    echo ""
    echo "❌ Build failed - see errors above"
    echo ""
    echo "Common fixes:"
    echo "  1. Open Package.swift in Xcode"
    echo "  2. Let it resolve dependencies"
    echo "  3. Try again"
fi
