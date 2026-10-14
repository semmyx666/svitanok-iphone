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
RESULT_PATH="build/Tests-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath build/test -resultBundlePath "$RESULT_PATH" \
  CODE_SIGNING_ALLOWED=NO test

mkdir -p build/logs/ui-screenshots
xcrun xcresulttool export attachments --path "$RESULT_PATH" --output-path build/logs/ui-screenshots
