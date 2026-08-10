#!/usr/bin/env bash
# waybar custom/media — streams playerctl state as JSON lines.
# Emits an empty object when nothing is playing so waybar hides the module.

set -uo pipefail

# US (0x1f). Must be a NON-whitespace delimiter: bash `read` collapses runs of
# IFS-whitespace into one separator, which would shift fields whenever a track
# has no artist (podcasts, browser audio).
SEP=$'\x1f'

emit_empty() { printf '{"text":"","alt":"","tooltip":"","class":"stopped"}\n'; }

if ! command -v playerctl >/dev/null 2>&1; then
    emit_empty
    exit 0
fi

# --follow blocks and re-emits on every metadata/status change.
playerctl --follow --format \
    "{{status}}${SEP}{{artist}}${SEP}{{title}}${SEP}{{playerName}}" metadata 2>/dev/null |
while IFS="$SEP" read -r status artist title player; do
    if [[ -z ${status:-} || $status == "Stopped" || -z ${title:-} ]]; then
        emit_empty
        continue
    fi

    if [[ -n ${artist:-} ]]; then
        text="$artist — $title"
    else
        text="$title"
    fi

    case $status in
        Playing) class="playing" ;;
        Paused)  class="paused"  ;;
        *)       class="stopped" ;;
    esac

    jq -cn \
        --arg text "$text" \
        --arg alt "$class" \
        --arg tooltip "${player:-player} — $status"$'\n'"$text" \
        --arg class "$class" \
        '{text:$text, alt:$alt, tooltip:$tooltip, class:$class}'
done

# playerctl exited (no session bus / daemon died) — leave the module hidden.
emit_empty
