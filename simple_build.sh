#!/bin/bash

echo "🚀 BUILDING FOR iPHONE"
echo "====================="
echo ""

xcodebuild \
  -scheme "MetaGlassesApp" \
  -destination "generic/platform=iOS" \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build 2>&1 | tee build.log | grep -E "(Build|error:|warning:|Compiling|Linking|Succeeded|Failed)" | tail -30

echo ""
echo "Check build.log for full output"
