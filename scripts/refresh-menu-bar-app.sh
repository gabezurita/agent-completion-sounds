#!/usr/bin/env bash
# Rebuild the local Agent Dashboard from origin/main and reopen it when it is running.
# The user's checkout branch is not changed. Only the side clone under the release root moves.
set -euo pipefail

LABEL="com.gabo.agent-sounds-menu.refresh"
INTERVAL=60

usage() {
  cat <<'EOF'
Usage: refresh-menu-bar-app.sh [OPTIONS]

Fetch origin/main and, when it has moved, rebuild AgentDashboard.app.
If Agent Dashboard is running, quit it and open the new bundle.
If it is not running, replace the bundle and leave it quit.

Options:
  --install       Install the 60-second launch agent
  --no-load       With --install, write the agent but do not bootstrap it
  --installed     Running from the installed copy; update that copy from origin/main
  --repo PATH     Checkout whose build/AgentDashboard.app is replaced
  --release-root PATH
                  Side clone, stamp, and log directory
  --app PATH      Bundle to replace
  --lib-dir PATH  Installed script directory
  --launchd-dir PATH
                  LaunchAgents directory
  -h, --help      Show this help message
EOF
}

ORIG_ARGS=("$@")
do_install=0
no_load=0
installed=0
REPO_ROOT=""
RELEASE_ROOT="${REFRESH_RELEASE_ROOT:-${HOME}/.local/share/agent-completion-sounds}"
APP_BUNDLE=""
LIB_DIR="${HOME}/.local/lib/agent-completion-sounds"
LAUNCHD_DIR="${HOME}/Library/LaunchAgents"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) do_install=1 ;;
    --no-load) no_load=1 ;;
    --installed) installed=1 ;;
    --repo) REPO_ROOT="$2"; shift ;;
    --release-root) RELEASE_ROOT="$2"; shift ;;
    --app) APP_BUNDLE="$2"; shift ;;
    --lib-dir) LIB_DIR="$2"; shift ;;
    --launchd-dir) LAUNCHD_DIR="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

export GIT_TERMINAL_PROMPT=0

discover_repo() {
  local toplevel primary
  toplevel=$(git rev-parse --show-toplevel)
  primary=$(git -C "${toplevel}" worktree list --porcelain | awk '/^worktree / { print $2; exit }')
  if [[ -n "${primary}" ]]; then
    printf '%s\n' "${primary}"
  else
    printf '%s\n' "${toplevel}"
  fi
}

if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT=$(discover_repo)
fi
if [[ -z "${APP_BUNDLE}" ]]; then
  APP_BUNDLE="${REPO_ROOT}/build/AgentDashboard.app"
fi

SRC="${RELEASE_ROOT}/src"
STAMP="${RELEASE_ROOT}/installed-sha"
LOCK="${RELEASE_ROOT}/refresh.lock"
INSTALLED_SCRIPT="${LIB_DIR}/refresh-menu-bar-app.sh"
PLIST_PATH="${LAUNCHD_DIR}/${LABEL}.plist"

install_agent() {
  mkdir -p "${LIB_DIR}" "${LAUNCHD_DIR}" "${RELEASE_ROOT}"
  cp -f "${BASH_SOURCE[0]}" "${INSTALLED_SCRIPT}"
  chmod +x "${INSTALLED_SCRIPT}"
  cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALLED_SCRIPT}</string>
        <string>--installed</string>
        <string>--repo</string>
        <string>${REPO_ROOT}</string>
        <string>--release-root</string>
        <string>${RELEASE_ROOT}</string>
        <string>--app</string>
        <string>${APP_BUNDLE}</string>
        <string>--lib-dir</string>
        <string>${LIB_DIR}</string>
    </array>
    <key>StartInterval</key>
    <integer>${INTERVAL}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${RELEASE_ROOT}/refresh.log</string>
    <key>StandardErrorPath</key>
    <string>${RELEASE_ROOT}/refresh.log</string>
</dict>
</plist>
PLIST
  echo "==> Installed refresh agent: ${PLIST_PATH}"
  if [[ "${no_load}" -eq 0 ]]; then
    domain="gui/$(id -u)"
    launchctl bootout "${domain}/${LABEL}" >/dev/null 2>&1 || true
    launchctl bootstrap "${domain}" "${PLIST_PATH}"
    echo "==> Loaded ${LABEL}"
  fi
}

if [[ "${do_install}" -eq 1 ]]; then
  install_agent
  exit 0
fi

ensure_side_clone() {
  if [[ ! -d "${SRC}/.git" ]]; then
    local url
    url=$(git -C "${REPO_ROOT}" remote get-url origin)
    git clone --quiet --branch main "${url}" "${SRC}"
  fi
  if ! git -C "${SRC}" fetch --quiet origin main; then
    echo "refresh: fetch failed; leaving the running app in place" >&2
    exit 0
  fi
  # This clone is disposable. Force it to origin/main without touching the user's checkout.
  git -C "${SRC}" checkout -q -f -B main origin/main
}

maybe_self_update() {
  local upstream="${SRC}/scripts/refresh-menu-bar-app.sh"
  if [[ "${installed}" -ne 1 || ! -f "${upstream}" ]]; then
    return 0
  fi
  if cmp -s "${upstream}" "${INSTALLED_SCRIPT}"; then
    return 0
  fi
  cp -f "${upstream}" "${INSTALLED_SCRIPT}.new"
  mv -f "${INSTALLED_SCRIPT}.new" "${INSTALLED_SCRIPT}"
  chmod +x "${INSTALLED_SCRIPT}"
  exec "${INSTALLED_SCRIPT}" "${ORIG_ARGS[@]}"
}

running_pids() {
  pgrep -x AgentSoundsMenu || true
}

stop_app() {
  local pids="$1"
  local pid
  while IFS= read -r pid; do
    if [[ -z "${pid}" ]]; then
      continue
    fi
    env kill "${pid}" || true
  done <<EOF
${pids}
EOF
  local i=0
  while [[ "${i}" -lt 25 ]]; do
    if [[ -z "$(running_pids)" ]]; then
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  while IFS= read -r pid; do
    if [[ -z "${pid}" ]]; then
      continue
    fi
    env kill -9 "${pid}" || true
  done <<EOF
$(running_pids)
EOF
}

ensure_side_clone
maybe_self_update

mkdir -p "${RELEASE_ROOT}"
if ! mkdir "${LOCK}" 2>/dev/null; then
  echo "refresh: already running" >&2
  exit 0
fi
trap 'rmdir "${LOCK}"' EXIT

SHA=$(git -C "${SRC}" rev-parse HEAD)
APP_BIN="${APP_BUNDLE}/Contents/MacOS/AgentSoundsMenu"
if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${SHA}" && -x "${APP_BIN}" ]]; then
  exit 0
fi

if [[ -n "${REFRESH_BUILD_CMD:-}" ]]; then
  (cd "${SRC}" && "${REFRESH_BUILD_CMD}")
else
  (cd "${SRC}" && bash "${SRC}/scripts/build-menu-bar-app.sh")
fi

BUILT="${SRC}/build/AgentDashboard.app"
BUILT_BIN="${BUILT}/Contents/MacOS/AgentSoundsMenu"
if [[ ! -x "${BUILT_BIN}" ]]; then
  echo "refresh: build did not produce ${BUILT_BIN}" >&2
  exit 1
fi

PIDS="$(running_pids)"
if [[ -n "${PIDS}" ]]; then
  stop_app "${PIDS}"
fi

mkdir -p "$(dirname "${APP_BUNDLE}")"
rm -rf "${APP_BUNDLE}"
cp -R "${BUILT}" "${APP_BUNDLE}"

if [[ -n "${PIDS}" ]]; then
  open "${APP_BUNDLE}"
fi

printf '%s\n' "${SHA}" > "${STAMP}"
echo "refresh: installed ${SHA}"
