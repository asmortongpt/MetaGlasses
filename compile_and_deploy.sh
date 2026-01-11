#!/bin/bash
set -e

echo "🔨 MANUAL COMPILATION & DEPLOYMENT"
echo "===================================="

SIMULATOR_ID="3658687E-BC5E-4575-A652-7D64C8F08D18"
BUNDLE_ID="com.metaglasses.testapp"
APP_NAME="MetaGlassesApp"
BUILD_DIR="./manual_build"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)

echo ""
echo "📦 Step 1: Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app"

echo "✅ Build directory ready"

echo ""
echo "📝 Step 2: Creating Info.plist..."
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
	<string>MetaGlasses</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
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
echo "🔧 Step 3: Compiling all Swift sources..."

# Collect all Swift files
SWIFT_FILES=$(find Sources/MetaGlassesCamera -name "*.swift" | grep -v "CaptureViewController.swift" | grep -v "DualCaptureViewController.swift" | grep -v "AppDelegate.swift" | tr '\n' ' ')

# Add test files
TEST_FILES="Sources/MetaGlassesCamera/Testing/TestAppDelegate.swift Sources/MetaGlassesCamera/Testing/TestDualCaptureViewController.swift"

echo "   Compiling with swiftc..."
swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-ios15.0-simulator \
    -emit-executable \
    -o "$BUILD_DIR/$APP_NAME.app/$APP_NAME" \
    $SWIFT_FILES $TEST_FILES \
    -F "$SDK_PATH/System/Library/Frameworks" \
    -framework UIKit \
    -framework Foundation \
    -framework Vision \
    -framework CoreImage \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks \
    -Xlinker -rpath -Xlinker @loader_path/Frameworks \
    2>&1 | tail -20

if [ -f "$BUILD_DIR/$APP_NAME.app/$APP_NAME" ]; then
    echo "✅ Executable compiled successfully!"
    ls -lh "$BUILD_DIR/$APP_NAME.app/$APP_NAME"
else
    echo "❌ Compilation failed"
    exit 1
fi

echo ""
echo "📱 Step 4: Preparing simulator..."
xcrun simctl boot "$SIMULATOR_ID" 2>&1 || echo "  Simulator already running"
open -a Simulator
sleep 2

echo ""
echo "🚀 Step 5: Installing app..."
xcrun simctl install "$SIMULATOR_ID" "$BUILD_DIR/$APP_NAME.app"

if [ $? -eq 0 ]; then
    echo "✅ App installed successfully!"
else
    echo "⚠️  Installation had issues"
    exit 1
fi

echo ""
echo "▶️  Step 6: Launching app..."
xcrun simctl launch --console "$SIMULATOR_ID" "$BUNDLE_ID"

echo ""
echo "════════════════════════════════════════"
echo "✅ APP RUNNING IN SIMULATOR!"
echo "════════════════════════════════════════"
echo ""
echo "📱 Check your Simulator window"
echo "🎯 App: MetaGlasses 3D Camera Test"
echo "🧪 Features: Mock dual camera + AI analysis"

