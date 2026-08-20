#!/usr/bin/env bash
# Download curated voice/audio clips into ~/sounds/<set>/ for the agent
# completion-sound hook. Played by play-random-completion-sound.sh.
# Documented in GETTING_STARTED.md and README.md.
#
# Clips are fetched to a local, untracked tree. Only this script, the default
# manifest, and the docs are committed; the audio is never added to git.

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Fallback manifest logic
if [[ -n "${COMPLETION_SOUND_MANIFEST:-}" ]]; then
  MANIFEST="$COMPLETION_SOUND_MANIFEST"
elif [[ -f "${SCRIPT_DIR}/completion-sound-sets.txt" ]]; then
  MANIFEST="${SCRIPT_DIR}/completion-sound-sets.txt"
else
  MANIFEST="${SCRIPT_DIR}/completion-sound-sets.default.txt"
fi

SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
UA="agent-completion-sounds-fetch/1.0"

usage() {
  cat <<'EOF'
Usage: fetch-completion-sounds.sh [--list] [--dry-run] [set ...]

  (no args)   Fetch every set in the manifest.
  set ...     Fetch only the named sets (folder names, e.g. kenney-ui).
  --list      List sets with clip counts. With set names, list their clips.
  --dry-run   Report what would be downloaded without writing anything.

Existing files are left alone, so re-running only fills in what is missing.
EOF
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

# Generalised parser supporting JSON and CSV/TXT pipe-separated format
# Outputs: folder\tname\turl\tdescription
manifest_data=""
if command -v python3 >/dev/null 2>&1; then
  manifest_data=$(python3 -c '
import json, os, sys
manifest_path = sys.argv[1]
if not os.path.exists(manifest_path):
    print(f"Error: manifest {manifest_path} not found", file=sys.stderr)
    sys.exit(1)
_, ext = os.path.splitext(manifest_path)
entries = []
if ext.lower() == ".json":
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                for item in data:
                    entries.append((
                        item.get("folder", "").strip(),
                        item.get("name", "").strip(),
                        item.get("url", "").strip(),
                        item.get("description", "").strip()
                    ))
    except Exception as e:
        print(f"Error parsing JSON manifest: {e}", file=sys.stderr)
        sys.exit(1)
else:
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) >= 3:
                    folder = parts[0].strip()
                    name = parts[1].strip()
                    url = parts[2].strip()
                    desc = parts[3].strip() if len(parts) > 3 else ""
                    entries.append((folder, name, url, desc))
    except Exception as e:
        print(f"Error parsing CSV/TXT manifest: {e}", file=sys.stderr)
        sys.exit(1)
for folder, name, url, desc in entries:
    if folder and name and url:
        print(f"{folder}\t{name}\t{url}\t{desc}")
' "$MANIFEST")
else
  # Basic Bash-only fallback for pipe-separated CSV if python3 is unavailable
  # Only handles CSV/TXT format.
  while IFS='|' read -r folder name url desc || [[ -n "${folder:-}" ]]; do
    folder="${folder%%#*}"
    [[ -z "${folder// /}" ]] && continue
    [[ -z "${name:-}" ]] && continue
    [[ -z "${url:-}" ]] && continue
    manifest_data+="${folder%%#*}\t${name}\t${url}\t${desc:-}"$'\n'
  done < "$MANIFEST"
fi

folders=()
names=()
urls=()
descriptions=()

while IFS=$'\t' read -r folder name url desc || [[ -n "${folder:-}" ]]; do
  [[ -z "${folder// /}" ]] && continue
  [[ -z "${name:-}" ]] && continue
  [[ -z "${url:-}" ]] && continue
  folders+=("$folder")
  names+=("$name")
  urls+=("$url")
  descriptions+=("${desc:-}")
done <<< "$manifest_data"

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
      printf '%-22s %-52s %s\n' "${folders[i]}" "${names[i]}" "${descriptions[i]}"
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
  url="${urls[i]}"
  wanted "$folder" || continue

  dest_dir="${SOUNDS_ROOT}/${folder}"
  dest="${dest_dir}/${name}"
  wav_name="${name%.*}.wav"
  if [[ -f "$dest" || -f "${dest_dir}/${wav_name}" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

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

  if [[ "$name" == *.ogg ]] && command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$tmp" "${dest_dir}/${wav_name}" -loglevel error
    rm -f "$tmp"
    chmod 644 "${dest_dir}/${wav_name}"
    printf 'fetched and converted %s/%s -> %s\n' "$folder" "$name" "$wav_name"
  else
    mv "$tmp" "$dest"
    chmod 644 "$dest"
    printf 'fetched %s/%s\n' "$folder" "$name"
  fi
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
