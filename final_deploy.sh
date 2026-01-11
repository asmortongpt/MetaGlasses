#!/bin/bash

echo "🚀 FINAL AUTOMATED BUILD & INSTALL"
echo "==================================="
echo ""

DEVICE_ID="00008150-001625183A80401C"

echo "📱 Target: iPhone (26.2)"
echo "   UDID: $DEVICE_ID"
echo ""

# Make sure iPhone is ready
echo "⏳ Waiting for iPhone to be ready..."
sleep 3

# Build with proper signing
echo "🔨 Building for iPhone..."
echo "   This takes 2-3 minutes..."
echo ""

xcodebuild \
  -scheme MetaGlassesApp \
  -sdk iphoneos \
  -destination "id=$DEVICE_ID" \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  clean build \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  2>&1 | grep -E "^(==|Build|Compiling|Linking|CodeSign|Touch|error:|warning:|\*\*)" | head -100

BUILD_EXIT=${PIPESTATUS[0]}

if [ $BUILD_EXIT -eq 0 ]; then
    echo ""
    echo "✅ BUILD SUCCESSFUL!"
    echo ""
    
    # Find app
    APP=$(find DerivedData -name "MetaGlassesApp.app" -type d | head -1)
    
    if [ -n "$APP" ]; then
        echo "📦 App built at: $APP"
        echo ""
        echo "📲 Installing to iPhone..."
        
        # Install
        xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
        
        echo ""
        echo "🎉 APP INSTALLED!"
        echo ""
        echo "📱 Check your iPhone - the app should be there!"
        echo "   Tap it, grant permissions, then connect your glasses!"
        echo ""
    fi
else
    echo ""
    echo "❌ Build failed"
    echo ""
    echo "Let me try with xcode-select and setup..."
    
    # Fix Xcode setup
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    sudo xcodebuild -license accept
    
    echo "Now try running this script again: ./final_deploy.sh"
fi
