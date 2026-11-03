#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
check_absent() {
  local path="$1"
  shift
  for pattern in "$@"; do
    if grep -R -n -E "$pattern" "$path" --include='*.swift' >/tmp/privatekeyboard_privacy_hit 2>/dev/null; then
      echo "privacy check failed: '$pattern' in $path" >&2
      cat /tmp/privatekeyboard_privacy_hit >&2
      fail=1
    fi
  done
}

# The keyboard extension must not link or call networking/telemetry APIs.
check_absent KeyboardExtension 'URLSession|URLRequest|NSURLConnection|NWConnection|WebSocket|http://|https://'
check_absent SharedCore/Sources/PrivateKeyboardCore 'URLSession|URLRequest|NSURLConnection|NWConnection|WebSocket|Firebase|AdMob|Amplitude|Sentry'

if grep -q 'com.apple.security.application-groups' KeyboardExtension/KeyboardExtension.entitlements; then
  echo "app group entitlement: present"
else
  echo "app group entitlement: missing" >&2
  fail=1
fi

open_access=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' KeyboardExtension/Info.plist 2>/dev/null || true)
case "$open_access" in
  true) echo "keyboard full access: requested for App Group";;
  false) echo "keyboard full access: not requested";;
  *) echo "keyboard full access: unexpected value" >&2; fail=1;;
esac

# Fail if the generated Xcode project links the updater into the keyboard target.
python3 scripts/check_project_privacy.py

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "privacy checks passed"

# Apple privacy manifest must be present in both the app and the extension.
python3 - <<'PY'
import plistlib
import re
import sys
from pathlib import Path

manifest = plistlib.loads(Path("Resources/PrivacyInfo.xcprivacy").read_bytes())
if manifest.get("NSPrivacyTracking") is not False:
    print("privacy manifest must declare NSPrivacyTracking=false", file=sys.stderr)
    raise SystemExit(1)
if manifest.get("NSPrivacyCollectedDataTypes") != []:
    print("privacy manifest must declare no collected data types", file=sys.stderr)
    raise SystemExit(1)
api_types = manifest.get("NSPrivacyAccessedAPITypes", [])
if not any(item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults" for item in api_types):
    print("privacy manifest is missing the UserDefaults required-reason declaration", file=sys.stderr)
    raise SystemExit(1)
project = Path("PrivateKeyboard.xcodeproj/project.pbxproj").read_text()
if project.count("PrivacyInfo.xcprivacy in Resources") < 2:
    print("privacy manifest is not copied into both app and extension", file=sys.stderr)
    raise SystemExit(1)
print("privacy manifest: valid, included in app and extension")
PY
