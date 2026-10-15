#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs/wake
SIM_ID="$(cat build/logs/test-simulator-id.txt)"
xcrun simctl boot "$SIM_ID" || true
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl uninstall "$SIM_ID" ua.semmyx.svitanok || true
python3 scripts/lock_wake_driver.py "$SIM_ID" > build/logs/wake/lock-driver.txt 2>&1 &
DRIVER=$!
set +e
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok -destination "platform=iOS Simulator,id=$SIM_ID" \
 -derivedDataPath build/test -resultBundlePath build/Wake.xcresult -parallel-testing-enabled NO \
 CODE_SIGNING_ALLOWED=NO -only-testing:SvitanokUITests/WakeProbeTests test-without-building > build/logs/wake/xctest.txt 2>&1
TEST_RESULT=$?
wait "$DRIVER"
LOCK_RESULT=$?
set -e
xcrun xcresulttool export attachments --path build/Wake.xcresult --output-path build/logs/wake/screenshots || true
python3 scripts/validate_wake.py "$SIM_ID"
test "$TEST_RESULT" -eq 0 && test "$LOCK_RESULT" -eq 0
