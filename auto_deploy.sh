#!/bin/bash

echo "🤖 FULLY AUTOMATED DEPLOY TO iPHONE"
echo "===================================="
echo ""

# Get iPhone UDID
DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep "iPhone" | grep -v "Simulator" | head -1 | sed 's/.*(\(.*\))/\1/')

echo "📱 Target Device: iPhone (26.2)"
echo "   UDID: $DEVICE_ID"
echo ""

# Clean
echo "🧹 Cleaning previous builds..."
rm -rf .build
rm -rf build
rm -rf DerivedData

echo ""
echo "🔨 Building for iPhone (this takes 2-3 minutes)..."
echo "   Compiling 36 Swift files..."
echo "   Please wait..."
echo ""

# Build and install in one command
xcodebuild \
  -scheme MetaGlassesApp \
  -sdk iphoneos \
  -destination "id=$DEVICE_ID" \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  -allowProvisioningUpdates \
  clean build install \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="" \
  2>&1 | tee build_log.txt | grep -E "Build succeeded|error:|warning:|Installing|Copying|Touching"

BUILD_EXIT_CODE=${PIPESTATUS[0]}

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ BUILD SUCCEEDED!"
    echo ""

    # Find the built app
    APP_PATH=$(find DerivedData -name "MetaGlassesApp.app" -type d | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "📦 Found app bundle: $APP_PATH"
        echo ""
        echo "📲 Installing to your iPhone..."

        # Install using devicectl (newer method)
        xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1

        INSTALL_EXIT=$?

        if [ $INSTALL_EXIT -eq 0 ]; then
            echo ""
            echo "🎉 SUCCESS! APP IS ON YOUR iPHONE!"
            echo "=================================="
            echo ""
            echo "📱 Look at your iPhone now!"
            echo "   1. You should see the MetaGlasses app icon"
            echo "   2. Tap it to launch"
            echo "   3. Grant ALL permissions (tap Allow)"
            echo "   4. Take your glasses out of the case"
            echo "   5. Say 'Connect' or tap Connect button"
            echo ""
            echo "✨ You now have 110+ features on your glasses!"
            echo ""
        else
            echo ""
            echo "⚠️  Installation needs manual step..."
            echo ""
            echo "On your iPhone:"
            echo "1. Go to Settings → General → VPN & Device Management"
            echo "2. Tap on your developer certificate"
            echo "3. Tap 'Trust'"
            echo "4. The app should now launch!"
            echo ""
        fi
    else
        echo "⚠️  Could not find built app in DerivedData"
        echo "   Checking build log..."
        grep -i "error" build_log.txt | tail -5
    fi
else
    echo ""
    echo "❌ Build failed. Checking errors..."
    echo ""
    grep -i "error" build_log.txt | head -10
    echo ""
    echo "💡 Common fixes:"
    echo "   1. Make sure Xcode Command Line Tools are installed:"
    echo "      xcode-select --install"
    echo "   2. Accept Xcode license:"
    echo "      sudo xcodebuild -license accept"
    echo "   3. Open Xcode and sign in with Apple ID"
    echo "   4. Then run this script again"
    echo ""
fi
