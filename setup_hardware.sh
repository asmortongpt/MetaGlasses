#!/bin/bash

# MetaGlasses Hardware Setup Script
# This script configures the app to work with actual Meta Ray-Ban glasses

set -e

echo "🔧 MetaGlasses Hardware Setup"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Xcode is not installed. Please install Xcode from the App Store.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Xcode is installed${NC}"

# Check for connected iOS device
DEVICE_COUNT=$(xcrun xctrace list devices 2>&1 | grep -c "iPhone" || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No iOS devices detected. Please connect your iPhone via cable.${NC}"
    echo ""
    echo "After connecting your iPhone:"
    echo "1. Unlock your device"
    echo "2. Trust this computer when prompted"
    echo "3. Run this script again"
    exit 1
fi
echo -e "${GREEN}✅ iOS device connected${NC}"

# Step 2: Update Package.swift to use real Meta SDK
echo ""
echo -e "${BLUE}Step 2: Enabling Meta Wearables DAT SDK...${NC}"

PACKAGE_FILE="Package.swift"
if [ -f "$PACKAGE_FILE" ]; then
    # Check if SDK is already enabled
    if grep -q "^[[:space:]]*\.package.*meta-wearables-dat-ios" "$PACKAGE_FILE"; then
        echo -e "${GREEN}✅ Meta SDK already enabled${NC}"
    else
        # Uncomment the Meta SDK dependency
        sed -i '' 's|//[[:space:]]*\.package(url: "https://github.com/facebook/meta-wearables-dat-ios.git"|.package(url: "https://github.com/facebook/meta-wearables-dat-ios.git"|g' "$PACKAGE_FILE"
        echo -e "${GREEN}✅ Meta SDK enabled in Package.swift${NC}"
    fi
else
    echo -e "${RED}❌ Package.swift not found${NC}"
    exit 1
fi

# Step 3: Create production AppDelegate
echo ""
echo -e "${BLUE}Step 3: Creating production AppDelegate...${NC}"

PRODUCTION_DELEGATE="Sources/MetaGlassesCamera/Production/ProductionAppDelegate.swift"
mkdir -p "Sources/MetaGlassesCamera/Production"

cat > "$PRODUCTION_DELEGATE" << 'EOF'
import UIKit

/// Production version of AppDelegate that uses real Meta glasses hardware
@main
class ProductionAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)

        // Create enhanced view controller with PRODUCTION camera manager
        let cameraManager = DualCameraManager()
        let viewController = EnhancedTestDualCaptureViewController()
        viewController.cameraManager = cameraManager

        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        print("🚀 MetaGlasses PRODUCTION MODE launched")
        print("📱 Using REAL Meta Ray-Ban glasses hardware")
        print("⚠️  Ensure glasses are paired via Meta View app")

        return true
    }
}
EOF

echo -e "${GREEN}✅ Production AppDelegate created${NC}"

# Step 4: Create Info.plist with required permissions
echo ""
echo -e "${BLUE}Step 4: Creating Info.plist with hardware permissions...${NC}"

INFO_PLIST="Sources/MetaGlassesCamera/Production/Info.plist"

cat > "$INFO_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MetaGlassesApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.capitaltechalliance.metaglasses</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
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
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>

    <!-- Hardware Permissions -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MetaGlasses needs Bluetooth to connect to your Ray-Ban smart glasses and capture photos.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>MetaGlasses needs Bluetooth to communicate with your Ray-Ban smart glasses.</string>
    <key>NSCameraUsageDescription</key>
    <string>MetaGlasses accesses the cameras on your Ray-Ban smart glasses to capture 3D stereoscopic images.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>MetaGlasses uses local network to communicate with your Ray-Ban smart glasses.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>MetaGlasses needs access to save captured 3D images to your photo library.</string>

    <!-- Bluetooth Background Modes -->
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
        <string>bluetooth-peripheral</string>
    </array>
</dict>
</plist>
EOF

echo -e "${GREEN}✅ Info.plist created with hardware permissions${NC}"

# Step 5: Create build script for hardware
echo ""
echo -e "${BLUE}Step 5: Creating hardware build script...${NC}"

BUILD_SCRIPT="build_for_hardware.sh"

cat > "$BUILD_SCRIPT" << 'EOF'
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
EOF

chmod +x "$BUILD_SCRIPT"
echo -e "${GREEN}✅ Build script created: $BUILD_SCRIPT${NC}"

# Step 6: Summary
echo ""
echo -e "${GREEN}=============================="
echo "✅ Hardware setup complete!"
echo "==============================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1️⃣  Pair your Meta Ray-Ban glasses:"
echo "   - Install 'Meta View' app from App Store"
echo "   - Turn on your glasses"
echo "   - Follow pairing process in Meta View app"
echo ""
echo "2️⃣  Build and install to your iPhone:"
echo "   ${BLUE}./build_for_hardware.sh${NC}"
echo ""
echo "3️⃣  Launch the app and connect to glasses!"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo "   See HARDWARE_CONNECTION_GUIDE.md for detailed instructions"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "   - Ensure glasses are charged (>20%)"
echo "   - Keep iPhone within 30 feet of glasses"
echo "   - Grant all permissions when prompted"
echo ""
