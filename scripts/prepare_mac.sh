#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo "Нужен Mac с Xcode 26+." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Установите XcodeGen: brew install xcodegen" >&2; exit 1; }
xcodebuild -version
xcodegen generate
open Svitanok.xcodeproj
