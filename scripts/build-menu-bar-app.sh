#!/usr/bin/env bash
# Build the native macOS Menu Bar Status Item for agent-completion-sounds.
# Requires macOS and swiftc (built into macOS Command Line Tools / Xcode).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${REPO_ROOT}/build"
APP_NAME="Agent Sounds"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SWIFT_SOURCE="${REPO_ROOT}/ui/AgentSoundsMenu.swift"
BIN_NAME="AgentSoundsMenu"

usage() {
  cat <<'EOF'
Usage: build-menu-bar-app.sh [OPTIONS]

Options:
  --link            Link the compiled binary to ~/.local/bin/agent-sounds-menu
  --install-launchd Install a launchd agent to start the app automatically on login
  --start           Launch the built app immediately
  -h, --help        Show this help message
EOF
}

do_link=0
do_launchd=0
do_start=0

while (($#)); do
  case "$1" in
    --link) do_link=1 ;;
    --install-launchd) do_launchd=1 ;;
    --start) do_start=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: The menu bar application requires macOS." >&2
  exit 1
fi

SWIFTC=$(command -v swiftc || echo "/usr/bin/swiftc")
if [[ ! -x "${SWIFTC}" ]]; then
  echo "Error: swiftc not found. Please ensure Xcode or Command Line Tools are installed." >&2
  exit 1
fi

echo "==> Building ${APP_NAME}.app from ${SWIFT_SOURCE}..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Compile with optimization
"${SWIFTC}" -O "${SWIFT_SOURCE}" -o "${APP_BUNDLE}/Contents/MacOS/${BIN_NAME}"

# Copy resources and helper scripts into bundle
if [[ -f "${SCRIPT_DIR}/completion-sound-sets.default.txt" ]]; then
  cp -f "${SCRIPT_DIR}/completion-sound-sets.default.txt" "${APP_BUNDLE}/Contents/Resources/"
fi
for s in play-random-completion-sound.sh sound-mode.sh fetch-completion-sounds.sh; do
  if [[ -f "${SCRIPT_DIR}/${s}" ]]; then
    cp -f "${SCRIPT_DIR}/${s}" "${APP_BUNDLE}/Contents/Resources/"
    chmod +x "${APP_BUNDLE}/Contents/Resources/${s}"
  fi
done

# Create Info.plist (LSUIElement = true ensures it runs as a pure menu bar accessory)
cat > "${APP_BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AgentSoundsMenu</string>
    <key>CFBundleIdentifier</key>
    <string>com.gabo.agent-sounds-menu</string>
    <key>CFBundleName</key>
    <string>Agent Sounds</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Built application bundle: ${APP_BUNDLE}"

if [[ "${do_link}" -eq 1 ]]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sf "${APP_BUNDLE}/Contents/MacOS/${BIN_NAME}" "${HOME}/.local/bin/agent-sounds-menu"
  echo "==> Linked binary to ~/.local/bin/agent-sounds-menu"
fi

if [[ "${do_launchd}" -eq 1 ]]; then
  LAUNCHD_DIR="${HOME}/Library/LaunchAgents"
  PLIST_PATH="${LAUNCHD_DIR}/com.gabo.agent-sounds-menu.plist"
  mkdir -p "${LAUNCHD_DIR}"
  cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gabo.agent-sounds-menu</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_BUNDLE}/Contents/MacOS/${BIN_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
  echo "==> Installed launchd agent: ${PLIST_PATH}"
  echo "    To activate now: launchctl load -w \"${PLIST_PATH}\""
fi

if [[ "${do_start}" -eq 1 ]]; then
  echo "==> Launching ${APP_NAME}..."
  open "${APP_BUNDLE}"
fi
