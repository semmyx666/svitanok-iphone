#!/usr/bin/env bash
# macOS runner only. Does NOT create Apple certificates or take Apple passwords.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo "Этот шаг выполняется на macOS, например в бесплатном GitHub Actions." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Нужен xcodegen." >&2; exit 1; }
SDK_MAJOR="$(xcrun --sdk iphoneos --show-sdk-version | cut -d. -f1)"
[[ "$SDK_MAJOR" -ge 26 ]] || { echo "Нужен Apple iOS SDK 26+." >&2; exit 1; }
xcodegen generate
xcodebuild -project Svitanok.xcodeproj -scheme Svitanok -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
python3 scripts/package_ipa.py \
  build/device/Build/Products/Release-iphoneos/Svitanok.app \
  dist/Svitanok-unsigned.ipa
{
  echo "Unsigned iPhone IPA; requires user-controlled signing before installation."
  echo "Built UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  xcodebuild -version
  echo "No Apple Account, certificate, private key or API token was used by this build."
  echo "Successful packaging does NOT certify physical-device alarm behavior."
} > dist/BUILD_STATUS.txt
