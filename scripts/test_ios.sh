#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo "Нужен Mac с Xcode 26+." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Установите xcodegen." >&2; exit 1; }
xcodegen generate
SIM_ID="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
r=json.load(sys.stdin)
for runtime,devices in r["devices"].items():
    if "iOS-" not in runtime: continue
    try: version=int(runtime.split("iOS-")[1].split("-")[0])
    except ValueError: continue
    if version < 26: continue
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d["name"]:
            print(d["udid"]);sys.exit(0)
sys.exit("Установите iOS 26+ Simulator в Xcode Settings → Components.")
')"
mkdir -p build/logs
printf '%s\n' "$SIM_ID" > build/logs/test-simulator-id.txt
RESULT_PATH="build/Tests-$(date +%Y%m%d-%H%M%S).xcresult"
# Let Xcode distinguish simulated iOS entitlements (Mach-O section) from
# host macOS code-signing entitlements. No paid identity/certificate is used.
# These settings are limited to this simulator destination; device IPA is unsigned.
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath build/test -resultBundlePath "${RESULT_PATH%.xcresult}-build.xcresult" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build-for-testing
SIM_APP="build/test/Build/Products/Debug-iphonesimulator/Svitanok.app"
test -d "$SIM_APP"
codesign -d --entitlements :- "$SIM_APP" > build/logs/simulator-entitlements.plist 2>/dev/null
# Keep the simulated entitlement section as diagnostic evidence.
xcrun otool -s __TEXT __entitlements "$SIM_APP/Svitanok" > build/logs/simulator-embedded-entitlements.txt
if [[ "${PROBE_ONLY:-false}" == true ]]; then exit 0; fi
set +e
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok \
  -destination "platform=iOS Simulator,id=$SIM_ID" -parallel-testing-enabled NO \
  -derivedDataPath build/test -resultBundlePath "$RESULT_PATH" \
  CODE_SIGNING_ALLOWED=NO -skip-testing:SvitanokUITests/NightProbeTests -skip-testing:SvitanokUITests/WakeProbeTests test-without-building
TEST_RESULT=$?
set -e
mkdir -p build/logs/ui-screenshots
xcrun xcresulttool export attachments --path "$RESULT_PATH" --output-path build/logs/ui-screenshots || true
exit "$TEST_RESULT"
