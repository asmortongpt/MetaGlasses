#!/bin/bash

# Build MetaGlasses app for physical iOS device

set -e

echo "🔨 Building MetaGlasses for iPhone..."

# Get connected device UDID
DEVICE_UDID=$(xcrun xctrace list devices 2>&1 | grep "iPhone" | head -1 | sed -n 's/.*(\(.*\)).*/\1/p' | tr -d '[:space:]')

if [ -z "$DEVICE_UDID" ]; then
    echo "❌ No iPhone detected. Please connect your device."
    exit 1
fi

echo "📱 Found device: $DEVICE_UDID"

# Build for device
echo "⚙️  Building for physical device..."
xcodebuild -scheme MetaGlassesCamera \
    -sdk iphoneos \
    -destination "id=$DEVICE_UDID" \
    -configuration Release \
    -allowProvisioningUpdates \
    build

echo "✅ Build complete!"
echo ""
echo "📲 Installing to device..."
xcodebuild -scheme MetaGlassesCamera \
    -sdk iphoneos \
    -destination "id=$DEVICE_UDID" \
    -configuration Release \
    -allowProvisioningUpdates \
    install

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Next steps:"
echo "1. Open Meta View app and ensure glasses are paired"
echo "2. Launch MetaGlasses app on your iPhone"
echo "3. Tap 'Connect' to connect to your glasses"
echo "4. Capture 3D images!"
