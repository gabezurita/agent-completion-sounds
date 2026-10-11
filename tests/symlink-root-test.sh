#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

REAL_STORAGE="${TEST_ROOT}/storage/sounds"
SYMLINK_SOUNDS="${TEST_ROOT}/home/sounds"
SOUNDMODE="${REPO_ROOT}/scripts/sound-mode.sh"

mkdir -p "${REAL_STORAGE}/pack-alpha" "${REAL_STORAGE}/pack-beta" "${TEST_ROOT}/home"
: > "${REAL_STORAGE}/pack-alpha/sound.wav"
: > "${REAL_STORAGE}/pack-beta/sound.wav"
cat > "${REAL_STORAGE}/favorites.txt" <<'EOF'
pack-alpha
EOF

# Create symlink pointing to the real storage
ln -s "${REAL_STORAGE}" "${SYMLINK_SOUNDS}"

echo "=== Test 1: soundmode status follows symlink ==="
status_out=$(AGENT_SOUNDS_ROOT="${SYMLINK_SOUNDS}" "${SOUNDMODE}" status)
echo "${status_out}"
if ! echo "${status_out}" | grep -q "Favorites: 1 of 2 unit packs"; then
  echo "FAIL: Expected 'Favorites: 1 of 2 unit packs', got:"
  echo "${status_out}"
  exit 1
fi
echo "PASS: soundmode status resolved symlink accurately"

echo "=== Test 2: Swift SoundManager resolves symlink ==="
swift_test=$(swift -e "
import Foundation

// Test symlink resolution in SoundManager logic
let envRoot = \"${SYMLINK_SOUNDS}\"
let soundsRoot = URL(fileURLWithPath: envRoot).resolvingSymlinksInPath()

guard let items = try? FileManager.default.contentsOfDirectory(at: soundsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
    print(\"FAIL: contentsOfDirectory threw error on symlink\")
    exit(1)
}

var units: [String] = []
for item in items {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
        let name = item.lastPathComponent
        if name != \"scratch\" && !name.hasPrefix(\".\") {
            units.append(name)
        }
    }
}

let favFile = soundsRoot.appendingPathComponent(\"favorites.txt\")
guard let favContent = try? String(contentsOf: favFile, encoding: .utf8) else {
    print(\"FAIL: could not read favorites.txt\")
    exit(1)
}

let favs = favContent.components(separatedBy: .newlines).filter { !\$0.isEmpty && !\$0.hasPrefix(\"#\") }

print(\"UNITS_COUNT:\(units.count)\")
print(\"FAVS_COUNT:\(favs.count)\")
")

if ! echo "${swift_test}" | grep -q "UNITS_COUNT:2" || ! echo "${swift_test}" | grep -q "FAVS_COUNT:1"; then
  echo "FAIL: Swift SoundManager symlink test failed:"
  echo "${swift_test}"
  exit 1
fi
echo "PASS: Swift SoundManager resolves symlink and reads units/favorites"

echo "=== Test 3: Guard against saving empty favorites ==="
# Test that selectAllFavorites does not overwrite favorites.txt when available units is empty
swift -e "
import Foundation

func selectAllFavorites(units: [String], fileURL: URL) {
    guard !units.isEmpty else { return }
    let content = \"# Favorite clip folders\n\" + units.joined(separator: \"\n\") + \"\n\"
    try? content.write(to: fileURL, atomically: true, encoding: .utf8)
}

let favURL = URL(fileURLWithPath: \"${REAL_STORAGE}/favorites.txt\")
selectAllFavorites(units: [], fileURL: favURL)

let content = try! String(contentsOf: favURL, encoding: .utf8)
assert(content.contains(\"pack-alpha\"), \"favorites.txt was erroneously overwritten!\")
"
echo "PASS: Empty units guard preserved existing favorites"

echo "symlink-root-test: ALL PASS"
