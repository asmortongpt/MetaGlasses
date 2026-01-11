#!/bin/bash
set -e

echo "🎨 COMPILING ENHANCED UI VERSION"
echo "================================="

SIMULATOR_ID="3658687E-BC5E-4575-A652-7D64C8F08D18"
BUNDLE_ID="com.metaglasses.testapp"
APP_NAME="MetaGlassesApp"
BUILD_DIR="./manual_build"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)

echo ""
echo "🧹 Cleaning old build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app"

echo "📝 Creating Info.plist..."
cat > "$BUILD_DIR/$APP_NAME.app/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MetaGlassesApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.metaglasses.testapp</string>
	<key>CFBundleName</key>
	<string>MetaGlasses 3D</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
</dict>
</plist>
PLIST

echo "✅ Info.plist created"

echo ""
echo "🔧 Compiling enhanced UI..."

# Collect all Swift files except old UI
SWIFT_FILES=$(find Sources/MetaGlassesCamera -name "*.swift" \
    | grep -v "CaptureViewController.swift" \
    | grep -v "DualCaptureViewController.swift" \
    | grep -v "TestDualCaptureViewController.swift" \
    | grep -v "AppDelegate.swift" \
    | tr '\n' ' ')

# Add enhanced UI and test app delegate
ENHANCED_FILES="Sources/MetaGlassesCamera/Testing/EnhancedTestDualCaptureViewController.swift Sources/MetaGlassesCamera/Testing/TestAppDelegate.swift"

echo "   Compiling with swiftc..."
swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-ios15.0-simulator \
    -emit-executable \
    -o "$BUILD_DIR/$APP_NAME.app/$APP_NAME" \
    $SWIFT_FILES $ENHANCED_FILES \
    -F "$SDK_PATH/System/Library/Frameworks" \
    -framework UIKit \
    -framework Foundation \
    -framework Vision \
    -framework CoreImage \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks \
    -Xlinker -rpath -Xlinker @loader_path/Frameworks \
    2>&1 | grep -v "warning:" | tail -10

if [ -f "$BUILD_DIR/$APP_NAME.app/$APP_NAME" ]; then
    echo "✅ Enhanced UI compiled!"
    ls -lh "$BUILD_DIR/$APP_NAME.app/$APP_NAME"
else
    echo "❌ Compilation failed"
    exit 1
fi

echo ""
echo "📱 Preparing simulator..."
xcrun simctl boot "$SIMULATOR_ID" 2>&1 || echo "  Simulator already running"
open -a Simulator
sleep 2

echo ""
echo "🗑️  Uninstalling old version..."
xcrun simctl uninstall "$SIMULATOR_ID" "$BUNDLE_ID" 2>&1 || echo "  No old version found"

echo ""
echo "🚀 Installing enhanced version..."
xcrun simctl install "$SIMULATOR_ID" "$BUILD_DIR/$APP_NAME.app"

if [ $? -eq 0 ]; then
    echo "✅ App installed!"
else
    echo "❌ Installation failed"
    exit 1
fi

echo ""
echo "▶️  Launching enhanced app..."
xcrun simctl launch --console "$SIMULATOR_ID" "$BUNDLE_ID" &

sleep 2

echo ""
echo "════════════════════════════════════════"
echo "✅ ENHANCED UI RUNNING!"
echo "════════════════════════════════════════"
echo ""
echo "🎨 New Features:"
echo "  • Modern polished design"
echo "  • Auto-connect on launch"
echo "  • Smooth animations"
echo "  • Better visual feedback"
echo "  • Automatic status updates"
echo ""
echo "Check your Simulator window!"

