#!/bin/bash
# Build Popote (app + share extension) and (re)launch it in the booted simulator.
set -o pipefail
cd "$(dirname "$0")"
DEVICE="${DEVICE:-iPhone 17 Pro}"
if ! xcodebuild build -project Popote.xcodeproj -scheme Popote -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath .build > .build-log.txt 2>&1; then
    echo "BUILD FAILED"; grep -E "error:" .build-log.txt | sort -u | head -40; exit 1
fi
echo "Built"
[ "$1" = "build" ] && exit 0
APP=.build/Build/Products/Debug-iphonesimulator/Popote.app
xcrun simctl terminate booted com.leobrunet.popote 2>/dev/null
xcrun simctl install booted "$APP" && xcrun simctl launch booted com.leobrunet.popote > /dev/null && echo "Launched"
