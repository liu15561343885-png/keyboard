#!/usr/bin/env bash
# Headless Mac Catalyst smoke test for the UIKit keyboard view.
# This exercises view construction and layout, not an iOS keyboard extension.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk macosx --show-sdk-path)
CATALYST_FRAMEWORKS="$SDK/System/iOSSupport/System/Library/Frameworks"
if [[ ! -d "$CATALYST_FRAMEWORKS/UIKit.framework" ]]; then
  echo "Catalyst UIKit is not present in $SDK" >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
TARGET=(-target x86_64-apple-ios17.0-macabi -sdk "$SDK" -F "$CATALYST_FRAMEWORKS")

swiftc "${TARGET[@]}" -parse-as-library -emit-module -module-name PrivateKeyboardCore \
  -emit-module-path "$WORK/PrivateKeyboardCore.swiftmodule" \
  -emit-library -static -o "$WORK/libPrivateKeyboardCore.a" \
  $(find SharedCore/Sources/PrivateKeyboardCore -name '*.swift')

swiftc "${TARGET[@]}" -I "$WORK" \
  KeyboardExtension/KeyboardTheme.swift \
  KeyboardExtension/KeyButton.swift \
  KeyboardExtension/CandidateBarView.swift \
  KeyboardExtension/KeyboardView.swift \
  KeyboardExtension/KeyboardViewController.swift \
  Tests/UIKitSmoke/main.swift \
  "$WORK/libPrivateKeyboardCore.a" \
  -o "$WORK/keyboard-smoke"

"$WORK/keyboard-smoke"
