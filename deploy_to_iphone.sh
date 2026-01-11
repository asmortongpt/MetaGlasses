#!/bin/bash

echo "🚀 DEPLOYING TO YOUR iPHONE"
echo "==========================="
echo ""

# Get the iPhone UDID
DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep "iPhone" | grep -v "Simulator" | head -1 | sed 's/.*(\(.*\))/\1/')

echo "📱 Found iPhone: $DEVICE_ID"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf .build
rm -rf build

echo ""
echo "🔨 Building for iPhone (iphoneos)..."
echo "   This may take 1-2 minutes..."
echo ""

# Build using xcodebuild
xcodebuild \
  -scheme MetaGlassesCamera \
  -sdk iphoneos \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -50

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ BUILD SUCCESSFUL!"
    echo ""
    echo "📱 Installing to iPhone..."

    # Find the built app
    APP_PATH=$(find build -name "*.app" -type d | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "   Found app at: $APP_PATH"

        # Install to device
        xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1

        echo ""
        echo "🎉 APP INSTALLED ON YOUR iPHONE!"
        echo ""
        echo "📲 Next steps:"
        echo "   1. Look at your iPhone - you should see the MetaGlasses app icon"
        echo "   2. Tap it to launch"
        echo "   3. Grant all permissions (Bluetooth, Camera, Microphone, etc.)"
        echo "   4. Take your glasses out of the case"
        echo "   5. Say 'Connect' or tap the Connect button"
        echo ""
    else
        echo "⚠️  Could not find built app"
        echo "   Try opening Xcode and building manually"
    fi
else
    echo ""
    echo "⚠️  Build had issues - trying alternative approach..."
    echo ""
    echo "📝 MANUAL APPROACH:"
    echo "   1. Xcode should already be open"
    echo "   2. At the top, click where it says 'My Mac' or device name"
    echo "   3. Select 'iPhone (26.2)'"
    echo "   4. Click the ▶️ Play button"
    echo "   5. Xcode will build and install automatically"
    echo ""
fi
