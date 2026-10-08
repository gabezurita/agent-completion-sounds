#!/usr/bin/env bash
# Package Alfred 5 workflow into a distributable .alfredworkflow file.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ALFRED_DIR="${REPO_ROOT}/integrations/alfred"
BUILD_DIR="${REPO_ROOT}/build"
OUTPUT_FILE="${BUILD_DIR}/Agent-Completion-Sounds.alfredworkflow"

mkdir -p "${BUILD_DIR}"
rm -f "${OUTPUT_FILE}"

echo "==> Packaging Alfred workflow into ${OUTPUT_FILE}..."

# An .alfredworkflow file is a zip archive containing info.plist and workflow assets at its root
(
  cd "${ALFRED_DIR}"
  chmod +x ./*.sh
  zip -q -r "${OUTPUT_FILE}" info.plist ./*.sh
)

echo "==> Successfully created ${OUTPUT_FILE}"
echo "    Double-click the file to install into Alfred, or run: open \"${OUTPUT_FILE}\""
