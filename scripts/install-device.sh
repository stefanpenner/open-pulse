#!/usr/bin/env bash
# Install Open Pulse Debug to a paired physical iPhone.
# Usage:
#   ./scripts/install-device.sh              # Stefan's iPhone if available
#   ./scripts/install-device.sh stefan       # Stefan's iPhone (17 Pro Max)
#   ./scripts/install-device.sh other        # other paired "iPhone"
#   ./scripts/install-device.sh <device-id>  # UDID or coredevice UUID
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="${OPENPULSE_DERIVED:-/tmp/OpenPulse-device-build}"
SCHEME="${OPENPULSE_SCHEME:-OpenPulse}"
BUNDLE_ID="${OPENPULSE_BUNDLE_ID:-io.github.stefanpenner.OpenPulse}"
TARGET="${1:-stefan}"

pick_device() {
  case "$TARGET" in
    stefan|stefans|Stefan*|STEFAN*)
      # Prefer available Stefan's iPhone 17 Pro Max
      xcrun devicectl list devices 2>/dev/null \
        | awk '/Stefan/ && /available \(paired\)/ { print $NF; exit }' \
        | tr -d '()' || true
      # Fallback: hardware UDID from xctrace (iOS 26.x Stefan's)
      if [[ -z "${DEVICE_ID:-}" ]]; then
        xcrun xctrace list devices 2>/dev/null \
          | awk -F'[()]' '/Stefan.*iPhone \(26\./ { gsub(/ /,"",$2); print $2; exit }' || true
      fi
      ;;
    other|iphone)
      xcrun devicectl list devices 2>/dev/null \
        | awk '/^iPhone / && /available \(paired\)/ { print $(NF-3); exit }' || true
      ;;
    *)
      echo "$TARGET"
      ;;
  esac
}

# Resolve coredevice identifier for install (UUID form preferred)
resolve_coredevice() {
  local want="$1"
  # If already a UUID with dashes of right length, use as-is when listed
  if xcrun devicectl list devices 2>/dev/null | grep -q "$want"; then
    # Prefer the Identifier column match
    xcrun devicectl list devices 2>/dev/null \
      | awk -v w="$want" 'index($0,w) && /available/ {
          for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit }
        }'
    return
  fi
  # Map hardware UDID → coredevice Identifier for Stefan's available phone
  xcrun devicectl list devices 2>/dev/null \
    | awk '/Stefan/ && /available \(paired\)/ {
        for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit }
      }'
}

echo "==> Open Pulse device install"
echo "    target: $TARGET"

# Default known-good pair from last successful install (Stefan's 17 Pro Max)
COREDEVICE="${OPENPULSE_DEVICE:-}"
if [[ -z "$COREDEVICE" ]]; then
  COREDEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/Stefan/ && /available \(paired\)/ {
        for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit }
      }' || true)
fi
if [[ -z "$COREDEVICE" && "$TARGET" == "other" ]]; then
  COREDEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/^iPhone / && /available \(paired\)/ {
        for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit }
      }' || true)
fi
if [[ -z "$COREDEVICE" ]]; then
  COREDEVICE="$TARGET"
fi

# Hardware id for xcodebuild destination when available
HW_ID=$(xcrun xctrace list devices 2>/dev/null \
  | awk -F'[()]' '/Stefan.*iPhone \(26\./ { print $2; exit }' || true)
if [[ -z "$HW_ID" ]]; then
  HW_ID=$(xcrun xctrace list devices 2>/dev/null \
    | awk -F'[()]' '/iPhone \(26\./ { print $2; exit }' || true)
fi

echo "    coredevice: $COREDEVICE"
echo "    hardware:   ${HW_ID:-unknown}"

if [[ -z "$HW_ID" ]]; then
  echo "ERROR: No physical iPhone destination found. Unlock phone, trust Mac, retry." >&2
  exit 1
fi

echo "==> Building $SCHEME (Debug-iphoneos)…"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS,id=$HW_ID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/OpenPulse.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: App not found at $APP" >&2
  exit 1
fi

echo "==> Installing…"
xcrun devicectl device install app --device "$COREDEVICE" "$APP"

echo "==> Launching (phone must be unlocked)…"
if xcrun devicectl device process launch --device "$COREDEVICE" "$BUNDLE_ID"; then
  echo "==> Done — $BUNDLE_ID running."
else
  echo "==> Installed. Unlock the phone and open Open Pulse (launch blocked while locked)."
fi
