#!/usr/bin/env bash
# Hands-free check of the iPhone -> iPad page-turn link.
#
# Launches the Debug build on an iPhone with -PagePilotPeerSoak: the iPhone
# turns the selected iPad's page every ~3s and logs each attempt with its
# latency and whether Wi-Fi had a network. When the run ends, the log is copied
# back and summarised; the script exits non-zero if any turn failed.
#
# Prerequisites:
#   - Debug build installed on both devices.
#   - An iPad already chosen on the iPhone (Me → Apple Watch → Choose Nearby iPad).
#   - A book open on the iPad. Without an App Store purchase, launch the iPad app
#     with -entitlements_isPro YES -PagePilotDebugPro, e.g.
#       xcrun devicectl device process launch --device <ipad-udid> --terminate-existing \
#         com.panyang.PagePilot -- -entitlements_isPro YES -PagePilotDebugPro
#
# Usage: scripts/peer-link-soak.sh <iphone-udid> [turns]
#   Works with a physical iPhone (devicectl; use a cable so Wi-Fi changes do
#   not cut the debug connection) or a booted simulator (simctl).
#   Toggle Wi-Fi in Control Center during the run to test network changes.
set -euo pipefail

UDID=${1:?usage: $0 <iphone-udid> [turns]}
TURNS=${2:-40}
BUNDLE=com.panyang.PagePilot
ARGS=(-AutoDismissOnboarding -entitlements_isPro YES -PagePilotDebugPro
      -PagePilotPeerSoak -PagePilotPeerSoakCount "$TURNS")
OUT="$(mktemp -d)/peer-soak.log"

if xcrun simctl list devices | grep -q "$UDID"; then
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${ARGS[@]}" >/dev/null
  fetch() {
    cp "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents/peer-soak.log" "$OUT" 2>/dev/null
  }
else
  xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" -- "${ARGS[@]}" >/dev/null
  fetch() {
    xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source Documents/peer-soak.log --destination "$OUT" >/dev/null 2>&1
  }
fi

echo "Soak running: $TURNS turns, about $((TURNS * 3 / 60 + 1)) min."
# The app clears the previous log when the run starts; give it time to do so.
sleep 15
deadline=$((SECONDS + TURNS * 9 + 60))
until fetch && grep -q "soak done" "$OUT"; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Timed out waiting for the soak to finish." >&2
    break
  fi
  sleep 10
done

cat "$OUT"
ok=$(grep -c " ok=true" "$OUT" || true)
failed=$(grep -c " ok=false" "$OUT" || true)
echo "Summary: $ok succeeded, $failed failed"
[ "$failed" -eq 0 ] && [ "$ok" -gt 0 ]
