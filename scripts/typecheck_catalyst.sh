#!/usr/bin/env bash
# Best-effort UIKit/SwiftUI typecheck when only Command Line Tools are installed.
# Mac Catalyst UIKit is not a substitute for an iOS SDK build; CI must still run
# xcodebuild against an iPhone simulator/device.
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
COMMON=(-target x86_64-apple-ios17.0-macabi -sdk "$SDK" -F "$CATALYST_FRAMEWORKS" -I "$WORK")

echo "Building Catalyst modules for SharedCore..."
swiftc "${COMMON[@]}" -parse-as-library -emit-module -module-name PrivateKeyboardCore \
  -emit-module-path "$WORK/PrivateKeyboardCore.swiftmodule" \
  $(find SharedCore/Sources/PrivateKeyboardCore -name '*.swift')
swiftc "${COMMON[@]}" -parse-as-library -emit-module -module-name PrivateKeyboardUpdater \
  -emit-module-path "$WORK/PrivateKeyboardUpdater.swiftmodule" \
  $(find SharedCore/Sources/PrivateKeyboardUpdater -name '*.swift')

echo "Typechecking Host App..."
swiftc "${COMMON[@]}" -typecheck App/*.swift
echo "Typechecking Keyboard Extension..."
swiftc "${COMMON[@]}" -application-extension -typecheck KeyboardExtension/*.swift
echo "Catalyst typecheck passed (UI compile semantics only; not an iOS device build)."
