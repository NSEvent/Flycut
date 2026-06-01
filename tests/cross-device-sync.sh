#!/bin/bash
#
# Cross-device sync test harness for Flycut's image clipping support.
#
# Orchestrates two Macs:
#   - LOCAL: the Mac running this script
#   - REMOTE: an SSH-reachable Mac (Tailscale hostname by default: kmacstudio)
#
# Both Macs must already be running the same signed Flycut.app build with
# CloudKit container iCloud.com.NSEvent.flycut, sync enabled, and signed
# into the same iCloud account. Build + deploy is NOT the responsibility
# of this harness — use deploy-test-builds.sh for that.
#
# Each test:
#   1. Sets up a deterministic source artifact (PNG, text, file path).
#   2. Puts it on the LOCAL pasteboard.
#   3. Waits up to TIMEOUT seconds polling the REMOTE Flycut store.
#   4. Asserts the expected entry shape (image with NSData, or text with
#      matching contents) is at position 0 of the REMOTE jcList.
#   5. Logs PASS/FAIL.
#
# Run: tests/cross-device-sync.sh [test-name]
#   Without args: runs all tests.
#   With name:    runs only that test.

set -uo pipefail

REMOTE="${REMOTE:-kmacstudio}"
TIMEOUT="${TIMEOUT:-90}"        # seconds to wait for sync
POLL_INTERVAL=5
APP_BUNDLE_ID="com.NSEvent.flycut"
PASS=0
FAIL=0

color() { local c=$1; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
pass()  { color "32" "  PASS: $*"; PASS=$((PASS+1)); }
fail()  { color "31" "  FAIL: $*"; FAIL=$((FAIL+1)); }
info()  { color "36" "  $*"; }

# --- helpers ---

# Read REMOTE Flycut store as a JSON-ish plutil dump, return the contents
# of position 0 entry.
remote_position_0() {
  ssh "$REMOTE" "plutil -p ~/Library/Containers/$APP_BUNDLE_ID/Data/Library/Preferences/$APP_BUNDLE_ID.plist 2>/dev/null | awk '/jcList/,0' | awk 'flag && /^      1 => /{exit} flag; /^      0 =>/{flag=1}'"
}

# Read REMOTE Flycut store and return how many `Type = ...` lines appear in jcList.
remote_entry_count() {
  ssh "$REMOTE" "plutil -p ~/Library/Containers/$APP_BUNDLE_ID/Data/Library/Preferences/$APP_BUNDLE_ID.plist 2>/dev/null | awk '/jcList/,/^    \"[a-z]/' | grep -c '\"Type\" =>' "
}

# Put PNG on LOCAL pasteboard.
local_put_png() {
  local path=$1
  swift - <<EOF
import AppKit
let d = try! Data(contentsOf: URL(fileURLWithPath: "$path"))
let pb = NSPasteboard.general
pb.declareTypes([.png], owner: nil)
_ = pb.setData(d, forType: .png)
EOF
}

# Put a file URL on LOCAL pasteboard (simulates Finder Cmd+C).
local_put_file_url() {
  local path=$1
  swift - <<EOF
import AppKit
let url = URL(fileURLWithPath: "$path")
let pb = NSPasteboard.general
pb.clearContents()
_ = pb.writeObjects([url as NSURL])
EOF
}

# Put a text string on LOCAL pasteboard.
local_put_text() {
  printf '%s' "$1" | pbcopy
}

# Wait up to TIMEOUT seconds for the predicate to return true on REMOTE.
# Predicate is a function name; called every POLL_INTERVAL seconds.
wait_for_remote() {
  local predicate=$1
  local label=$2
  local elapsed=0
  while [ $elapsed -lt $TIMEOUT ]; do
    if $predicate; then
      info "Matched after ${elapsed}s ($label)"
      return 0
    fi
    sleep $POLL_INTERVAL
    elapsed=$((elapsed+POLL_INTERVAL))
  done
  info "Timed out after ${TIMEOUT}s ($label)"
  return 1
}

# Generate a unique test PNG. Different bytes each run so dedupe doesn't
# hide a stale match.
make_test_png() {
  local out=$1
  local size=$2
  /usr/bin/sips -s format png --resampleHeightWidth "$size" "$size" \
    /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns \
    --out "$out" >/dev/null 2>&1
  # tag it with random metadata so each run differs
  /usr/bin/sips -s description "test-$(date +%s%N)-$RANDOM" "$out" >/dev/null 2>&1 || true
}

# --- tests ---

test_image_data_sync() {
  echo
  color "36" "TEST: image data on pasteboard syncs as image (not text)"
  local tmp=/tmp/flycut-test-$$.png
  make_test_png "$tmp" 128

  local size_bytes=$(stat -f%z "$tmp")
  info "Test image: $tmp ($size_bytes bytes)"

  local_put_png "$tmp"

  # Wait for REMOTE position 0 to be an image with non-empty ImageData
  _predicate_image() {
    remote_position_0 | grep -qE '"Type" => "public\.(png|tiff|jpeg)"'
  }
  if wait_for_remote _predicate_image "image at position 0"; then
    local entry; entry=$(remote_position_0)
    if echo "$entry" | grep -q '"ImageData" =>'; then
      pass "image clipping with ImageData NSData propagated"
    else
      fail "image type matched but no ImageData field"
      echo "$entry"
    fi
  else
    fail "remote never received an image clipping"
    echo "REMOTE pos 0:"
    remote_position_0
  fi
  rm -f "$tmp"
}

test_file_url_sync_no_text_dup() {
  echo
  color "36" "TEST: Finder Cmd+C (file URL on pb) syncs image only, no filename text duplicate"
  local tmp=/tmp/flycut-test-fileurl-$$.png
  make_test_png "$tmp" 96
  local filename; filename=$(basename "$tmp")

  local before_count; before_count=$(remote_entry_count)
  local_put_file_url "$tmp"

  _predicate_filename_image() {
    remote_position_0 | grep -qE '"Type" => "public\.(png|tiff|jpeg)"'
  }
  if wait_for_remote _predicate_filename_image "image at position 0"; then
    local entry; entry=$(remote_position_0)
    if echo "$entry" | grep -q '"ImageData" =>'; then
      pass "image clipping propagated"
    else
      fail "image type matched but no ImageData field"
    fi

    # Check positions 0 and 1 for a filename-text duplicate
    local top_two; top_two=$(ssh "$REMOTE" "plutil -p ~/Library/Containers/$APP_BUNDLE_ID/Data/Library/Preferences/$APP_BUNDLE_ID.plist 2>/dev/null | awk '/jcList/,/^      2 => /'")
    if echo "$top_two" | grep -F "\"$filename\"" | grep -q "NSStringPboardType"; then
      fail "filename text duplicate '$filename' present alongside image"
      echo "$top_two" | head -20
    else
      pass "no filename text duplicate"
    fi
  else
    fail "remote never received an image clipping from file URL"
  fi
  rm -f "$tmp"
}

test_text_sync() {
  echo
  color "36" "TEST: plain text on pasteboard syncs as text"
  local marker="text-sync-test-$(date +%s)"
  local_put_text "$marker"

  _predicate_text() {
    remote_position_0 | grep -q "\"Contents\" => \"$marker\""
  }
  if wait_for_remote _predicate_text "text '$marker' at position 0"; then
    pass "text clipping propagated"
  else
    fail "remote never received text clipping"
    echo "REMOTE pos 0:"
    remote_position_0
  fi
}

# --- runner ---

cd "$(dirname "$0")/.." || exit 1

# Sanity: REMOTE alive + Flycut running + sync enabled
ssh -o ConnectTimeout=5 "$REMOTE" 'pgrep -lf Flycut.app | head -1' >/dev/null 2>&1 \
  || { color "31" "REMOTE $REMOTE not reachable or Flycut not running"; exit 1; }

# Sanity: LOCAL Flycut running
pgrep -lf Flycut.app | head -1 >/dev/null \
  || { color "31" "LOCAL Flycut not running"; exit 1; }

ALL_TESTS=(test_image_data_sync test_file_url_sync_no_text_dup test_text_sync)
SELECTED="${1:-all}"

for t in "${ALL_TESTS[@]}"; do
  if [ "$SELECTED" = "all" ] || [ "$SELECTED" = "$t" ]; then
    "$t"
  fi
done

echo
color "36" "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
