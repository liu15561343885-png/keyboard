#!/usr/bin/env bash
# Compile and link Host App / Keyboard Extension against Mac Catalyst UIKit.
# This catches cross-module/linker issues that a typecheck cannot; it is still
# not an iOS device/simulator build.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk macosx --show-sdk-path)
FRAMEWORKS="$SDK/System/iOSSupport/System/Library/Frameworks"
if [[ ! -d "$FRAMEWORKS/UIKit.framework" ]]; then
  echo "Catalyst UIKit is not present in $SDK" >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
TARGET=(-target x86_64-apple-ios17.0-macabi -sdk "$SDK" -F "$FRAMEWORKS")

echo "Building Catalyst static modules..."
swiftc "${TARGET[@]}" -parse-as-library -emit-module -module-name PrivateKeyboardCore \
  -emit-module-path "$WORK/PrivateKeyboardCore.swiftmodule" \
  -emit-library -static -o "$WORK/libPrivateKeyboardCore.a" \
  $(find SharedCore/Sources/PrivateKeyboardCore -name '*.swift')

swiftc "${TARGET[@]}" -I "$WORK" -parse-as-library -emit-module -module-name PrivateKeyboardUpdater \
  -emit-module-path "$WORK/PrivateKeyboardUpdater.swiftmodule" \
  -emit-library -static -o "$WORK/libPrivateKeyboardUpdater.a" \
  $(find SharedCore/Sources/PrivateKeyboardUpdater -name '*.swift')

echo "Linking Host App..."
swiftc "${TARGET[@]}" -I "$WORK" -parse-as-library App/*.swift \
  "$WORK/libPrivateKeyboardCore.a" "$WORK/libPrivateKeyboardUpdater.a" \
  -o "$WORK/PrivateKeyboard"

echo "Linking Keyboard Extension..."
swiftc "${TARGET[@]}" -I "$WORK" -parse-as-library -application-extension -emit-library \
  -o "$WORK/PrivateKeyboardKeyboard.dylib" KeyboardExtension/*.swift \
  "$WORK/libPrivateKeyboardCore.a"

ls -lh "$WORK/PrivateKeyboard" "$WORK/PrivateKeyboardKeyboard.dylib"
echo "Catalyst product link passed (Host App executable + Extension dylib; not an iOS build)."
