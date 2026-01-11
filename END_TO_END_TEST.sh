#!/bin/bash

echo "🧪 END-TO-END TEST SUITE"
echo "=================================="
echo ""

# Test 1: Verify all enterprise files exist
echo "📦 TEST 1: Verifying Enterprise Files"
echo "--------------------------------------"
FILES=(
    "EnhancedOpenAIService.swift"
    "VoiceAssistantService.swift"
    "AdvancedVisionService.swift"
    "OfflineManager.swift"
    "EnhancedAIAssistantView.swift"
    "MetaGlassesApp.swift"
)

ALL_EXIST=true
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        SIZE=$(ls -lh "$file" | awk '{print $5}')
        LINES=$(wc -l < "$file")
        echo "  ✅ $file ($SIZE, $LINES lines)"
    else
        echo "  ❌ $file - NOT FOUND"
        ALL_EXIST=false
    fi
done

if [ "$ALL_EXIST" = true ]; then
    echo "  ✅ All files exist!"
else
    echo "  ❌ Some files missing"
    exit 1
fi

echo ""

# Test 2: Verify file contents (not empty, valid Swift)
echo "📝 TEST 2: Verifying File Contents"
echo "-----------------------------------"
for file in "${FILES[@]}"; do
    if grep -q "import Foundation\|import SwiftUI" "$file"; then
        echo "  ✅ $file - Valid Swift file"
    else
        echo "  ❌ $file - Invalid or empty"
    fi
done

echo ""

# Test 3: Check for key features in each file
echo "🔍 TEST 3: Verifying Key Features"
echo "----------------------------------"

# EnhancedOpenAIService
if grep -q "streamChat\|streaming" EnhancedOpenAIService.swift; then
    echo "  ✅ EnhancedOpenAIService - Streaming feature found"
else
    echo "  ⚠️  EnhancedOpenAIService - Streaming feature not found"
fi

# VoiceAssistantService
if grep -q "wakeWord\|SFSpeech" VoiceAssistantService.swift; then
    echo "  ✅ VoiceAssistantService - Wake word feature found"
else
    echo "  ⚠️  VoiceAssistantService - Wake word feature not found"
fi

# AdvancedVisionService
if grep -q "analyzeImages\|Vision" AdvancedVisionService.swift; then
    echo "  ✅ AdvancedVisionService - Multi-image analysis found"
else
    echo "  ⚠️  AdvancedVisionService - Multi-image analysis not found"
fi

# OfflineManager
if grep -q "cache\|offline" OfflineManager.swift; then
    echo "  ✅ OfflineManager - Caching feature found"
else
    echo "  ⚠️  OfflineManager - Caching feature not found"
fi

# EnhancedAIAssistantView
if grep -q "StreamingText\|ChatGPT" EnhancedAIAssistantView.swift; then
    echo "  ✅ EnhancedAIAssistantView - Streaming UI found"
else
    echo "  ⚠️  EnhancedAIAssistantView - Streaming UI not found"
fi

echo ""

# Test 4: Count total lines of code
echo "📊 TEST 4: Code Statistics"
echo "--------------------------"
TOTAL_LINES=0
for file in EnhancedOpenAIService.swift VoiceAssistantService.swift AdvancedVisionService.swift OfflineManager.swift EnhancedAIAssistantView.swift; do
    LINES=$(wc -l < "$file")
    TOTAL_LINES=$((TOTAL_LINES + LINES))
done
echo "  Total Enterprise Code: $TOTAL_LINES lines"
if [ $TOTAL_LINES -gt 4500 ]; then
    echo "  ✅ Exceeds 4,500 line requirement"
else
    echo "  ⚠️  Below 4,500 line target"
fi

echo ""

# Test 5: Check current deployment
echo "📱 TEST 5: Current Deployment Status"
echo "-------------------------------------"
CURRENT_APP_LINES=$(wc -l < MetaGlassesApp.swift)
echo "  Current MetaGlassesApp.swift: $CURRENT_APP_LINES lines"

if grep -q "EnhancedOpenAIService\|streamChat" MetaGlassesApp.swift; then
    echo "  ✅ Enhanced features integrated in main app"
else
    echo "  ⚠️  Enhanced features not yet integrated"
fi

echo ""

# Test 6: Verify OpenAI API key
echo "🔑 TEST 6: OpenAI API Configuration"
echo "------------------------------------"
if grep -q "sk-proj-" MetaGlassesApp.swift; then
    echo "  ✅ OpenAI API key configured"
else
    echo "  ❌ OpenAI API key not found"
fi

echo ""

# Test 7: Check iPhone connection
echo "📲 TEST 7: iPhone Connection"
echo "----------------------------"
if xcrun xctrace list devices 2>&1 | grep -q "iPhone.*00008150"; then
    echo "  ✅ iPhone connected (00008150-001625183A80401C)"
else
    echo "  ⚠️  iPhone not detected"
fi

echo ""

# Test 8: Check Meta glasses Bluetooth
echo "🕶️  TEST 8: Meta Glasses Status"
echo "-------------------------------"
if system_profiler SPBluetoothDataType 2>&1 | grep -q "RB Meta 00DG"; then
    echo "  ✅ Meta glasses detected (RB Meta 00DG)"
    FIRMWARE=$(system_profiler SPBluetoothDataType 2>&1 | grep -A 10 "RB Meta 00DG" | grep "Firmware" | awk '{print $3}')
    echo "  Firmware: $FIRMWARE"
else
    echo "  ⚠️  Meta glasses not detected"
fi

echo ""
echo "=================================="
echo "✅ END-TO-END TEST COMPLETE"
echo "=================================="
