#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs/night
brew install facebook/fb/idb-companion > build/logs/night/idb-install.txt 2>&1
python3 -m venv build/idb-env
build/idb-env/bin/pip install 'fb-idb==1.1.7' 'protobuf<4' >> build/logs/night/idb-install.txt 2>&1
build/idb-env/bin/idb ui button --help > build/logs/night/idb-help.txt
SIM_ID="$(cat build/logs/test-simulator-id.txt)"
xcrun simctl boot "$SIM_ID" || true
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl uninstall "$SIM_ID" ua.semmyx.svitanok || true
python3 scripts/lock_driver.py "$SIM_ID" > build/logs/night/lock-driver.txt 2>&1 &
DRIVER=$!
set +e
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath build/test -resultBundlePath build/Night.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO -only-testing:SvitanokUITests/NightProbeTests test-without-building > build/logs/night/xctest.txt 2>&1
TEST_RESULT=$?
wait "$DRIVER"
LOCK_RESULT=$?
set -e
xcrun simctl io "$SIM_ID" screenshot build/logs/night/screen-final.png || true
xcrun xcresulttool export attachments --path build/Night.xcresult --output-path build/logs/night/screenshots || true
python3 scripts/validate_night.py "$SIM_ID"
test "$TEST_RESULT" -eq 0 && test "$LOCK_RESULT" -eq 0
