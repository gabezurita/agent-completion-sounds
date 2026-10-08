#!/usr/bin/env bash
# Alfred 5 Script Filter for agent-completion-sounds.
# Outputs JSON items according to Alfred 5 Script Filter specifications.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
MODE_FILE="${SOUNDS_ROOT}/.mode"
DISABLE_FILE="${SOUNDS_ROOT}/.disabled"
FAVORITES_FILE="${SOUNDS_ROOT}/favorites.txt"

query="${1:-}"
query=$(printf '%s' "${query}" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || printf '%s' "${query}")

is_muted=0
[[ -f "${DISABLE_FILE}" ]] && is_muted=1

curr_mode=$(cat "${MODE_FILE}" 2>/dev/null || echo "session")

# Load favorites into array
favorites=()
if [[ -f "${FAVORITES_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="${line## }"
    line="${line%% }"
    [[ -n "${line}" ]] && favorites+=("${line}")
  done < "${FAVORITES_FILE}"
fi

# Load available units
available_units=()
for d in "${SOUNDS_ROOT}"/*/; do
  [[ -d "$d" ]] || continue
  b=$(basename "$d")
  [[ "$b" == .* || "$b" == "scratch" ]] && continue
  available_units+=("$b")
done

# Helper: check if array contains item
is_fav() {
  local target="$1"
  for f in "${favorites[@]}"; do
    [[ "$f" == "$target" ]] && return 0
  done
  return 1
}

# Sub-command: Favorites list
if [[ "${query}" == fav* ]]; then
  subfilter="${query#fav}"
  subfilter=$(printf '%s' "${subfilter}" | xargs 2>/dev/null || true)

  items=()
  for u in "${available_units[@]}"; do
    if [[ -n "${subfilter}" && "${u}" != *"${subfilter}"* ]]; then
      continue
    fi

    if is_fav "${u}"; then
      title="✓ ${u}"
      subtitle="In Favorites — press Enter to remove"
    else
      title="   ${u}"
      subtitle="Press Enter to add to Favorites"
    fi

    # Escape JSON strings
    esc_title=$(printf '%s' "${title}" | sed 's/"/\\"/g')
    esc_sub=$(printf '%s' "${subtitle}" | sed 's/"/\\"/g')
    esc_u=$(printf '%s' "${u}" | sed 's/"/\\"/g')

    items+=( "{\"uid\":\"fav-${esc_u}\",\"title\":\"${esc_title}\",\"subtitle\":\"${esc_sub}\",\"arg\":\"fav ${esc_u}\",\"autocomplete\":\"fav ${esc_u}\"}" )
  done

  if ((${#items[@]} == 0)); then
    items+=( "{\"title\":\"No matching sound packs found\",\"subtitle\":\"Check ~/sounds for valid pack folders\",\"valid\":false}" )
  fi

  printf '{"items":[%s]}\n' "$(IFS=,; echo "${items[*]}")"
  exit 0
fi

# Sub-command: Mode list
if [[ "${query}" == mode* ]]; then
  subfilter="${query#mode}"
  subfilter=$(printf '%s' "${subfilter}" | xargs 2>/dev/null || true)

  modes=(
    "session|Session (Sticky Favorite)|Pick 1 favorite per conversation"
    "session-all|Session All (Sticky Full Pool)|Pick 1 unit from full pool per conversation"
    "favorites|Favorites (Random Turn)|Random favorite unit every completed turn"
    "all|All (Random Full Pool)|Random unit from full pool every turn"
  )

  items=()
  for m in "${modes[@]}"; do
    IFS='|' read -r mid mname mdesc <<< "${m}"
    if [[ -n "${subfilter}" && "${mid}" != *"${subfilter}"* && "${mname}" != *"${subfilter}"* ]]; then
      continue
    fi
    check="  "
    [[ "${curr_mode}" == "${mid}" ]] && check="✓ "
    items+=( "{\"uid\":\"mode-${mid}\",\"title\":\"${check}${mname}\",\"subtitle\":\"${mdesc}\",\"arg\":\"mode ${mid}\"}" )
  done

  printf '{"items":[%s]}\n' "$(IFS=,; echo "${items[*]}")"
  exit 0
fi

# Sub-command: Fetch list
if [[ "${query}" == fetch* ]]; then
  items=()
  manifest="${REPO_ROOT}/scripts/completion-sound-sets.default.txt"
  if [[ -f "${manifest}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^# ]] && continue
      [[ -z "$line" ]] && continue
      set_name=$(printf '%s' "${line}" | cut -d'|' -f1)
      set_desc=$(printf '%s' "${line}" | cut -d'|' -f4)
      items+=( "{\"uid\":\"fetch-${set_name}\",\"title\":\"Download '${set_name}'\",\"subtitle\":\"${set_desc}\",\"arg\":\"fetch ${set_name}\"}" )
      break # default manifest only has kenney-ui
    done < "${manifest}"
  fi
  items+=( "{\"uid\":\"fetch-all\",\"title\":\"Download All Curated Sound Sets\",\"subtitle\":\"Downloads every sound pack in the manifest\",\"arg\":\"fetch all\"}" )

  printf '{"items":[%s]}\n' "$(IFS=,; echo "${items[*]}")"
  exit 0
fi

# Main / Default Menu
items=()

# 1. Mute Toggle
if [[ "${is_muted}" -eq 1 ]]; then
  items+=( "{\"uid\":\"toggle\",\"title\":\"🔇 Sounds Muted (Click to Unmute)\",\"subtitle\":\"Current Mode: ${curr_mode} | ${#favorites[@]} favorites\",\"arg\":\"toggle-mute\"}" )
else
  items+=( "{\"uid\":\"toggle\",\"title\":\"🔊 Sounds Active (Click to Mute)\",\"subtitle\":\"Current Mode: ${curr_mode} | ${#favorites[@]} favorites\",\"arg\":\"toggle-mute\"}" )
fi

# 2. Test Sound
items+=( "{\"uid\":\"test\",\"title\":\"▶ Play Test Sound\",\"subtitle\":\"Test playback immediately with a random completion sound\",\"arg\":\"test\"}" )

# 3. Change Mode
items+=( "{\"uid\":\"modes\",\"title\":\"⚙ Change Playback Mode (Current: ${curr_mode})\",\"subtitle\":\"Switch between session, session-all, favorites, or all\",\"arg\":\"mode\",\"autocomplete\":\"mode \"}" )

# 4. Favorites
items+=( "{\"uid\":\"favs\",\"title\":\"★ Curate Favorites (${#favorites[@]}/${#available_units[@]} selected)\",\"subtitle\":\"Browse and toggle sound packs in ~/sounds/favorites.txt\",\"arg\":\"fav\",\"autocomplete\":\"fav \"}" )

# 5. Open Finder
items+=( "{\"uid\":\"open\",\"title\":\"📁 Open ~/sounds in Finder\",\"subtitle\":\"Add new sound files or drag-and-drop packs directly\",\"arg\":\"open\"}" )

# 6. Fetch packs
items+=( "{\"uid\":\"fetch\",\"title\":\"☁ Download Curated Sound Packs\",\"subtitle\":\"Download royalty-free UI sound packs\",\"arg\":\"fetch\",\"autocomplete\":\"fetch \"}" )

printf '{"items":[%s]}\n' "$(IFS=,; echo "${items[*]}")"
