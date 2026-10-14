#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo "Нужен Mac." >&2; exit 1; }
: "${TEAM_ID:?Задайте TEAM_ID вашей Apple Team}"
DEVICE_UDID="${1:?Передайте UDID вашего iPhone из Xcode/xctrace}"
BUNDLE_ID="${BUNDLE_ID:-ua.semmyx.svitanok}"
command -v xcodegen >/dev/null || { echo "Установите xcodegen." >&2; exit 1; }
xcodegen generate
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok -configuration Debug \
  -destination "id=$DEVICE_UDID" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build
APP="build/Build/Products/Debug-iphoneos/Svitanok.app"
[[ -d "$APP" ]] || { echo "Сборка .app не найдена." >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID"
