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

if /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' KeyboardExtension/Info.plist 2>/dev/null | grep -qx 'false'; then
  echo "keyboard full access: not requested"
else
  echo "keyboard full access: unexpected value" >&2
  fail=1
fi

# Fail if the generated Xcode project links the updater into the keyboard target.
python3 scripts/check_project_privacy.py

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "privacy checks passed"
