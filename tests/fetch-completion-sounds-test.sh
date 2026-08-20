#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

# Test 1: Dry-run default manifest listing
printf 'Testing default manifest list...\n'
output=$(COMPLETION_SOUND_MANIFEST="${REPO_ROOT}/scripts/completion-sound-sets.default.txt" "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" --list)
if ! printf '%s\n' "$output" | grep -q "kenney-ui"; then
  printf 'FAIL: Default manifest list output: %s\n' "$output" >&2
  exit 1
fi

# Test 2: Dry-run with specific set listing
printf 'Testing default manifest list with specific set...\n'
output=$(COMPLETION_SOUND_MANIFEST="${REPO_ROOT}/scripts/completion-sound-sets.default.txt" "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" --list kenney-ui)
if ! printf '%s\n' "$output" | grep -q "click1.wav"; then
  printf 'FAIL: Default manifest specific list output: %s\n' "$output" >&2
  exit 1
fi

# Test 3: JSON manifest listing
printf 'Testing JSON manifest list...\n'
cat > "${TEST_ROOT}/test.json" <<'JSON'
[
  {
    "folder": "test-json-set",
    "name": "test_sound.wav",
    "url": "https://example.com/test_sound.wav",
    "description": "Test JSON Sound"
  }
]
JSON

output=$(COMPLETION_SOUND_MANIFEST="${TEST_ROOT}/test.json" "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" --list)
if ! printf '%s\n' "$output" | grep -q "test-json-set"; then
  printf 'FAIL: JSON manifest list output: %s\n' "$output" >&2
  exit 1
fi

output_specific=$(COMPLETION_SOUND_MANIFEST="${TEST_ROOT}/test.json" "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" --list test-json-set)
if ! printf '%s\n' "$output_specific" | grep -q "test_sound.wav"; then
  printf 'FAIL: JSON manifest specific list output: %s\n' "$output_specific" >&2
  exit 1
fi

# Test 4: Dry-run fetch default manifest
printf 'Testing dry-run fetch of default manifest...\n'
output_dry=$(COMPLETION_SOUND_MANIFEST="${REPO_ROOT}/scripts/completion-sound-sets.default.txt" "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" --dry-run)
if ! printf '%s\n' "$output_dry" | grep -q "would fetch kenney-ui/click1.wav"; then
  printf 'FAIL: Dry-run fetch output: %s\n' "$output_dry" >&2
  exit 1
fi

# Test 5: Fallback behavior test (when completion-sound-sets.txt doesn't exist)
printf 'Testing fallback to default manifest when custom manifest is absent...\n'
# Create a fake repo root without completion-sound-sets.txt
FAKE_REPO_DIR="${TEST_ROOT}/fake_repo/scripts"
mkdir -p "$FAKE_REPO_DIR"
cp "${REPO_ROOT}/scripts/fetch-completion-sounds.sh" "${FAKE_REPO_DIR}/"
cp "${REPO_ROOT}/scripts/completion-sound-sets.default.txt" "${FAKE_REPO_DIR}/"
chmod +x "${FAKE_REPO_DIR}/fetch-completion-sounds.sh"

# Run it from the fake directory without COMPLETION_SOUND_MANIFEST set
output_fallback=$(cd "${TEST_ROOT}" && "${FAKE_REPO_DIR}/fetch-completion-sounds.sh" --list)
if ! printf '%s\n' "$output_fallback" | grep -q "kenney-ui"; then
  printf 'FAIL: Fallback to default manifest output: %s\n' "$output_fallback" >&2
  exit 1
fi

printf 'fetch-completion-sounds-test: PASS\n'
