#!/bin/bash

# Build and Test Script for MetaGlasses 3D Camera (Simulator)

set -e

echo "🚀 Building MetaGlasses 3D Camera for iOS Simulator..."
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCHEME="MetaGlassesCamera"
WORKSPACE="MetaGlasses.xcworkspace"
PROJECT="MetaGlasses.xcodeproj"
SIMULATOR="iPhone 15 Pro"
BUILD_DIR="./build"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "  Scheme: $SCHEME"
echo "  Simulator: $SIMULATOR"
echo ""

# Get simulator UDID
echo -e "${BLUE}📱 Finding simulator...${NC}"
SIMULATOR_UDID=$(xcrun simctl list devices available | grep "$SIMULATOR" | head -1 | grep -o '[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}')

if [ -z "$SIMULATOR_UDID" ]; then
    echo -e "${YELLOW}⚠️  iPhone 15 Pro not found, using any available iPhone...${NC}"
    SIMULATOR_UDID=$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -o '[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}')
    SIMULATOR=$(xcrun simctl list devices available | grep "$SIMULATOR_UDID" | sed 's/.*(\(.*\)).*/\1/' | xargs)
fi

echo -e "${GREEN}✓${NC} Found simulator: $SIMULATOR"
echo "  UDID: $SIMULATOR_UDID"
echo ""

# Boot simulator if needed
echo -e "${BLUE}🔌 Booting simulator...${NC}"
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || echo -e "${GREEN}✓${NC} Simulator already booted"
sleep 2

# Open Simulator app
open -a Simulator

echo ""
echo -e "${BLUE}🔨 Building project...${NC}"

# Build using xcodebuild
if [ -f "$WORKSPACE" ]; then
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -destination "id=$SIMULATOR_UDID" \
        -derivedDataPath "$BUILD_DIR" \
        build
elif [ -f "$PROJECT" ]; then
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -destination "id=$SIMULATOR_UDID" \
        -derivedDataPath "$BUILD_DIR" \
        build
else
    # Use swift package if no Xcode project
    echo -e "${YELLOW}⚠️  No Xcode project found. Creating temporary project...${NC}"
    swift package generate-xcodeproj
    PROJECT="MetaGlasses.xcodeproj"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Build succeeded!${NC}"
    echo ""

    # Find the built app
    APP_PATH=$(find "$BUILD_DIR" -name "*.app" -type d | head -1)

    if [ -n "$APP_PATH" ]; then
        echo -e "${BLUE}📲 Installing app on simulator...${NC}"
        xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

        echo -e "${GREEN}✓${NC} App installed"
        echo ""

        # Get bundle ID
        BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist" 2>/dev/null || echo "com.metaglasses.camera")

        echo -e "${BLUE}🚀 Launching app...${NC}"
        xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"

        echo ""
        echo -e "${GREEN}🎉 SUCCESS!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "App is now running in the iOS Simulator!"
        echo ""
        echo "What to do next:"
        echo "  1. Look for the orange 'TEST MODE' header"
        echo "  2. Tap 'Connect (Mock)'"
        echo "  3. Tap '🤖 Capture with AI Analysis'"
        echo "  4. Watch the AI magic happen!"
        echo ""
        echo "View logs:"
        echo "  xcrun simctl spawn $SIMULATOR_UDID log stream --predicate 'processImagePath contains \"MetaGlasses\"'"
        echo ""
    else
        echo -e "${YELLOW}⚠️  Could not find built app${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}❌ Build failed${NC}"
    echo "See errors above for details"
    exit 1
fi
