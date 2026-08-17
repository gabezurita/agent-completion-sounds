#!/usr/bin/env bash
# Download curated game voice clips into ~/sounds/<set>/ for the agent
# completion-sound hook. Sets are declared in completion-sound-sets.txt.
# Played by play-random-completion-sound.sh.
# Documented in GETTING_STARTED.md and README.md.
#
# Clips are fetched to a local, untracked tree. Only this script, the manifest,
# and the docs are committed; the audio is never added to git.

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

MANIFEST="${COMPLETION_SOUND_MANIFEST:-${SCRIPT_DIR}/completion-sound-sets.txt}"
SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
STATIC_HOST="https://static.wikia.nocookie.net"
DEFAULT_WIKI="starcraft"
UA="agent-completion-sounds-fetch/1.0"

usage() {
  cat <<'EOF'
Usage: fetch-completion-sounds.sh [--list] [--dry-run] [set ...]

  (no args)   Fetch every set in the manifest.
  set ...     Fetch only the named sets (folder names, e.g. sc1-tassadar).
  --list      List sets with clip counts. With set names, list their clips.
  --dry-run   Report what would be downloaded without writing anything.

Existing files are left alone, so re-running only fills in what is missing.
EOF
}

# MediaWiki derives a file's path from the MD5 of its normalized title: spaces
# become underscores and the first character is upper-cased. Deriving it here
# avoids an API round trip and a JSON dependency.
md5_hex() {
  if command -v md5 >/dev/null 2>&1; then
    printf %s "$1" | md5
  else
    printf %s "$1" | md5sum | cut -d' ' -f1
  fi
}

clip_url() {
  local name="$1" wiki="$2" normalized hash
  normalized="${name// /_}"
  normalized="$(tr '[:lower:]' '[:upper:]' <<<"${normalized:0:1}")${normalized:1}"
  hash="$(md5_hex "$normalized")"
  printf '%s/%s/images/%s/%s/%s' \
    "$STATIC_HOST" "$wiki" "${hash:0:1}" "${hash:0:2}" "$normalized"
}

mode="fetch"
dry_run=0
requested=()

while (($#)); do
  case "$1" in
    --list) mode="list" ;;
    --dry-run) dry_run=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *) requested+=("$1") ;;
  esac
  shift
done

[[ -f "$MANIFEST" ]] || {
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
}

wanted() {
  ((${#requested[@]} == 0)) && return 0
  local set="$1" r
  for r in "${requested[@]}"; do
    [[ "$r" == "$set" ]] && return 0
  done
  return 1
}

# Read the manifest once into parallel arrays so it can be walked more than
# once (validating requested set names, then listing or fetching).
folders=()
names=()
quotes=()
wikis=()
while IFS='|' read -r folder name quote wiki || [[ -n "${folder:-}" ]]; do
  folder="${folder%%#*}"
  [[ -z "${folder// /}" ]] && continue
  [[ -z "${name:-}" ]] && continue
  folders+=("$folder")
  names+=("$name")
  quotes+=("${quote:-}")
  wikis+=("${wiki:-$DEFAULT_WIKI}")
done < "$MANIFEST"

((${#folders[@]} > 0)) || {
  echo "No clips declared in $MANIFEST" >&2
  exit 1
}

# Fail loudly on a typo'd set name rather than silently fetching nothing.
for r in "${requested[@]:-}"; do
  [[ -z "$r" ]] && continue
  found=0
  for f in "${folders[@]}"; do
    [[ "$f" == "$r" ]] && {
      found=1
      break
    }
  done
  ((found)) || {
    echo "Unknown set: $r (try --list)" >&2
    exit 1
  }
done

if [[ "$mode" == "list" ]]; then
  if ((${#requested[@]} == 0)); then
    printf '%s\n' "Sets in $(basename "$MANIFEST"):"
    prev=""
    count=0
    for i in "${!folders[@]}"; do
      if [[ "${folders[i]}" != "$prev" ]]; then
        [[ -n "$prev" ]] && printf '  %-22s %2d clips\n' "$prev" "$count"
        prev="${folders[i]}"
        count=0
      fi
      count=$((count + 1))
    done
    [[ -n "$prev" ]] && printf '  %-22s %2d clips\n' "$prev" "$count"
  else
    for i in "${!folders[@]}"; do
      wanted "${folders[i]}" || continue
      printf '%-22s %-52s %s\n' "${folders[i]}" "${names[i]}" "${quotes[i]}"
    done
  fi
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required" >&2
  exit 1
}

fetched=0
skipped=0
failed=0

for i in "${!folders[@]}"; do
  folder="${folders[i]}"
  name="${names[i]}"
  wanted "$folder" || continue

  dest_dir="${SOUNDS_ROOT}/${folder}"
  dest="${dest_dir}/${name}"

  if [[ -f "$dest" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  url="$(clip_url "$name" "${wikis[i]}")"

  if ((dry_run)); then
    printf 'would fetch %s/%s\n' "$folder" "$name"
    fetched=$((fetched + 1))
    continue
  fi

  mkdir -p "$dest_dir"
  tmp="$(mktemp "${TMPDIR:-/tmp}/completion-sound.XXXXXX")"

  if ! curl -fsSL -H "User-Agent: ${UA}" --max-time 30 -o "$tmp" "$url"; then
    echo "FAILED  ${folder}/${name}" >&2
    rm -f "$tmp"
    failed=$((failed + 1))
    continue
  fi

  # A blocked or missing clip comes back as an HTML error page, which would
  # otherwise sit in the pool as a silent, unplayable "clip".
  if [[ ! -s "$tmp" ]] || [[ "$(head -c 1 "$tmp")" == "<" ]]; then
    echo "FAILED  ${folder}/${name} (not audio)" >&2
    rm -f "$tmp"
    failed=$((failed + 1))
    continue
  fi

  mv "$tmp" "$dest"
  chmod 644 "$dest"
  printf 'fetched %s/%s\n' "$folder" "$name"
  fetched=$((fetched + 1))
done

if ((dry_run)); then
  printf '\n%d to fetch, %d already present\n' "$fetched" "$skipped"
  exit 0
fi

printf '\n%d fetched, %d already present, %d failed\n' "$fetched" "$skipped" "$failed"

if ((fetched > 0)); then
  printf 'Add keepers to %s/favorites.txt, or run: soundmode all\n' "$SOUNDS_ROOT"
fi

((failed == 0))
