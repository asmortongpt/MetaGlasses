#!/bin/bash

# Create an Xcode project for hardware deployment

echo "🔧 Creating Xcode project for iPhone deployment..."

# Open Package.swift in Xcode
open Package.swift

echo ""
echo "✅ Package.swift opened in Xcode!"
echo ""
echo "📋 Next steps in Xcode:"
echo ""
echo "1. Wait for Xcode to open (it should load Package.swift)"
echo "2. Select your iPhone as the build target (top toolbar)"
echo "3. Set the scheme to 'MetaGlassesCamera'"
echo "4. Click Run (▶️) or press Cmd+R"
echo "5. Trust your developer certificate when prompted"
echo ""
echo "The app will build and install to your iPhone automatically!"
echo ""
