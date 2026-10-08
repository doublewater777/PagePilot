#!/usr/bin/env bash
# End-to-end check of Watch -> iPhone -> iPad page turns on simulators.
#
# Taps Next/Previous on the Watch simulator while the iPhone app is
# (1) in the foreground, (2) in the background, and (3) terminated, so the
# Watch must wake it, and checks that the iPad Reader's page changes each time.
# Simulators share the Mac's network, so this covers the relay logic and
# background wake-up, not peer-to-peer Wi-Fi (see scripts/peer-link-soak.sh).
#
# Usage: scripts/watch-relay-sim-e2e.sh <iphone-sim> <ipad-sim> <watch-sim>
#   The Watch simulator must be paired with the iPhone simulator
#   (xcrun simctl pair <watch> <iphone>). Builds Debug into ./build/watch-e2e.
set -euo pipefail

IPHONE=${1:?usage: $0 <iphone-sim> <ipad-sim> <watch-sim>}
IPAD=${2:?usage: $0 <iphone-sim> <ipad-sim> <watch-sim>}
WATCH=${3:?usage: $0 <iphone-sim> <ipad-sim> <watch-sim>}
BUNDLE=com.panyang.PagePilot
WATCH_BUNDLE=com.panyang.PagePilot.WatchRemote
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/watch-e2e"
WORK="$(mktemp -d)"

AXE=$(command -v axe || true)
if [ -z "$AXE" ] || ! "$AXE" describe-ui --udid "$IPAD" >/dev/null 2>&1; then
  AXE=$(ls -d "$HOME"/.npm/_npx/*/node_modules/mobilebuildmcp/bundled/axe 2>/dev/null | head -1)
fi
[ -x "$AXE" ] || { echo "AXe not found (brew install cameroncooke/axe/axe)" >&2; exit 1; }

# Prints "x y" for the first element whose identifier or label matches $2.
element_center() {
  "$AXE" describe-ui --udid "$1" | python3 -c '
import json, sys
want = sys.argv[1]
def walk(n):
    if want in (n.get("AXUniqueId"), n.get("AXLabel")):
        f = n["frame"]; print(int(f["x"] + f["width"] / 2), int(f["y"] + f["height"] / 2)); sys.exit()
    for c in n.get("children", []): walk(c)
for n in json.load(sys.stdin): walk(n)' "$2"
}
tap() {
  local point; point=$(element_center "$1" "$2")
  [ -n "$point" ] || { echo "Element '$2' not found on $1" >&2; return 1; }
  set -- "$1" $point
  "$AXE" touch -x "$2" -y "$3" --down --up --delay 0.1 --udid "$1" >/dev/null
}
ipad_page() {
  "$AXE" describe-ui --udid "$IPAD" | python3 -c '
import json, re, sys
def walk(n):
    label = n.get("AXLabel") or ""
    if re.fullmatch(r"\d+ / \d+", label): print(label); sys.exit()
    for c in n.get("children", []): walk(c)
for n in json.load(sys.stdin): walk(n)'
}
prefs() { echo "$(xcrun simctl get_app_container "$1" "$BUNDLE" data)/Library/Preferences/$BUNDLE.plist"; }

echo "Building…"
for scheme_dest in "PagePilot:$IPHONE" "PagePilotWatch:$WATCH"; do
  xcodebuild -project "$ROOT/PagePilot.xcodeproj" -scheme "${scheme_dest%%:*}" -configuration Debug \
    -destination "id=${scheme_dest#*:}" -derivedDataPath "$DERIVED" build -quiet
done
APP="$DERIVED/Build/Products/Debug-iphonesimulator/PagePilot.app"
WATCH_APP="$DERIVED/Build/Products/Debug-watchsimulator/PagePilotWatch.app"

for sim in "$IPHONE" "$IPAD" "$WATCH"; do xcrun simctl boot "$sim" 2>/dev/null || true; done
for sim in "$IPHONE" "$IPAD"; do
  xcrun simctl terminate "$sim" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$sim" "$APP"
done
xcrun simctl install "$WATCH" "$WATCH_APP"
sleep 2

# iPad: launch once so it records its identity, then keep debug Pro on for
# every later launch (opening a book relaunches it without arguments).
xcrun simctl launch "$IPAD" "$BUNDLE" -AutoDismissOnboarding -entitlements_isPro YES -PagePilotDebugPro >/dev/null
sleep 8
xcrun simctl terminate "$IPAD" "$BUNDLE"
for sim in "$IPAD" "$IPHONE"; do
  plist=$(prefs "$sim"); [ -f "$plist" ] || plutil -create xml1 "$plist"
  plutil -replace PagePilotDebugPro -bool YES "$plist"
  plutil -replace entitlements_isPro -bool YES "$plist"
done
IPAD_ID=$(plutil -extract pagepilot_relay_identifier raw "$(prefs "$IPAD")")
SELECTION=$(printf '{"id":"%s","name":"Simulator iPad","bookTitle":""}' "$IPAD_ID" | base64)
plutil -replace pagepilot_nearby_selected_target -data "$SELECTION" "$(prefs "$IPHONE")"

python3 - "$WORK/Relay.epub" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
items = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(1, 6))
spine = "".join(f'<itemref idref="c{i}"/>' for i in range(1, 6))
z.writestr("OEBPS/content.opf", f'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">watch-relay-e2e</dc:identifier><dc:title>Relay Test Book</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>{items}</manifest><spine>{spine}</spine></package>')
z.writestr("OEBPS/nav.xhtml", '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>nav</title></head><body><nav epub:type="toc"><ol>' + "".join(f'<li><a href="c{i}.xhtml">Chapter {i}</a></li>' for i in range(1, 6)) + "</ol></nav></body></html>")
for i in range(1, 6):
    z.writestr(f"OEBPS/c{i}.xhtml", f'<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>c{i}</title></head><body><h1>Chapter {i}</h1>' + "<p>Page turn relay test paragraph. </p>" * 40 + "</body></html>")
z.close()
PY

xcrun simctl launch "$IPAD" "$BUNDLE" -AutoDismissOnboarding >/dev/null
sleep 4
DOCS="$(xcrun simctl get_app_container "$IPAD" "$BUNDLE" data)/Documents"
cp "$WORK/Relay.epub" "$DOCS/Relay.epub"
xcrun simctl openurl "$IPAD" "file://$DOCS/Relay.epub"
sleep 6
xcrun simctl launch --terminate-running-process "$WATCH" "$WATCH_BUNDLE" >/dev/null
sleep 3

failures=0
check() { # $1 scenario. Next must move the page and Previous must bring it back.
  local before after_next after_prev
  before=$(ipad_page)
  tap "$WATCH" watch.pageTurn.next; sleep 6; after_next=$(ipad_page)
  tap "$WATCH" watch.pageTurn.previous; sleep 6; after_prev=$(ipad_page)
  if [ -n "$before" ] && [ "$after_next" != "$before" ] && [ "$after_prev" = "$before" ]; then
    echo "PASS $1: iPad $before -> next $after_next -> previous $after_prev"
  else
    echo "FAIL $1: iPad ${before:-?} -> next ${after_next:-?} -> previous ${after_prev:-?}"
    failures=$((failures + 1))
  fi
}

xcrun simctl launch "$IPHONE" "$BUNDLE" -AutoDismissOnboarding >/dev/null
sleep 8
check "iPhone app in foreground"

"$AXE" button home --udid "$IPHONE" >/dev/null 2>&1
sleep 4
check "iPhone app in background"

xcrun simctl terminate "$IPHONE" "$BUNDLE"
sleep 3
check "iPhone app terminated (Watch wakes it)"

[ "$failures" -eq 0 ] && echo "All Watch relay scenarios passed." || { echo "$failures scenario(s) failed."; exit 1; }
