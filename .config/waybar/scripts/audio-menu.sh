#!/usr/bin/env bash
# rofi audio device switcher (pactl / PipeWire).
# Switching the default sink also moves already-playing streams onto it,
# otherwise running apps keep writing to the old device.
set -uo pipefail

THEME='window {width: 44em;} listview {lines: 10;}'
rofi_menu() { rofi -dmenu -i -markup-rows -format i -p "$1" -theme-str "$THEME"; }

notify() { notify-send -a "Audio" -i audio-volume-high "$@"; }
esc()    { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dim()    { printf '<span foreground="#859289">%s</span>' "$(esc "$1")"; }

# Onboard codecs report names like "Tiger Lake-LP Smart Sound Technology Audio
# Controller Speaker" — every entry looks identical until the last word. Drop
# the controller prefix; names without one (Bluetooth, USB) pass through.
short_desc() {
    local d=$1
    d=${d##*Audio Controller }
    d=${d##*Controller }
    printf '%s' "$d"
}

dev_icon() {
    local s=${1,,}
    case $s in
        *bluez*|*bluetooth*)       printf '󰂰' ;;
        *hdmi*|*displayport*)      printf '󰡁' ;;
        *usb*)                     printf '󰋋' ;;
        *headphone*|*headset*)     printf '󰋋' ;;
        *mic*|*microphone*)        printf '󰍬' ;;
        *)                         printf '󰓃' ;;
    esac
}

# name \t description \t mute \t volume%
list_devices() { # $1 = sinks|sources
    pactl -f json list "$1" 2>/dev/null | jq -r '
        .[]
        | select(.name | endswith(".monitor") | not)
        | [ .name,
            (.description // .name),
            (.mute | tostring),
            ((.volume | to_entries | .[0].value.value_percent) // "?")
          ] | @tsv'
}

move_streams() { # move every playing stream to sink $1
    local sink=$1 id
    while read -r id; do
        [[ -n $id ]] && pactl move-sink-input "$id" "$sink" >/dev/null 2>&1
    done < <(pactl -f json list sink-inputs 2>/dev/null | jq -r '.[].index')
}

cur_sink=$(pactl get-default-sink 2>/dev/null)
cur_source=$(pactl get-default-source 2>/dev/null)

declare -a disp=() act=() arg=()

disp+=("$(dim '── Output ──────────────')"); act+=(noop); arg+=("")
while IFS=$'\t' read -r name desc mute vol; do
    [[ -z ${name:-} ]] && continue
    short=$(short_desc "$desc")
    mark="  "; [[ $name == "$cur_sink" ]] && mark="󰸞 "
    meta="$vol"; [[ $mute == true ]] && meta="muted"
    disp+=("$(printf '%s%s  %s   %s' "$mark" "$(dev_icon "$desc$name")" \
                 "$(esc "$short")" "$(dim "$meta")")")
    act+=(set_sink); arg+=("$name"$'\t'"$short")
done < <(list_devices sinks)

disp+=("$(dim '── Input ───────────────')"); act+=(noop); arg+=("")
while IFS=$'\t' read -r name desc mute vol; do
    [[ -z ${name:-} ]] && continue
    short=$(short_desc "$desc")
    mark="  "; [[ $name == "$cur_source" ]] && mark="󰸞 "
    meta="$vol"; [[ $mute == true ]] && meta="muted"
    disp+=("$(printf '%s󰍬  %s   %s' "$mark" "$(esc "$short")" "$(dim "$meta")")")
    act+=(set_source); arg+=("$name"$'\t'"$short")
done < <(list_devices sources)

disp+=("$(dim '────────────────────────')"); act+=(noop);       arg+=("")
disp+=("󰝟  Toggle output mute");             act+=(mute_sink);   arg+=("")
disp+=("󰍭  Toggle input mute");              act+=(mute_source); arg+=("")
disp+=("󰒓  Open pavucontrol");               act+=(gui);         arg+=("")

idx=$(printf '%s\n' "${disp[@]}" | rofi_menu "Audio")
[[ -z $idx ]] && exit 0

case ${act[$idx]} in
    noop) exec "$0" ;;
    set_sink)
        IFS=$'\t' read -r name desc <<<"${arg[$idx]}"
        pactl set-default-sink "$name" && move_streams "$name"
        notify "Output" "$desc" ;;
    set_source)
        IFS=$'\t' read -r name desc <<<"${arg[$idx]}"
        pactl set-default-source "$name"
        notify "Input" "$desc" ;;
    mute_sink)   pactl set-sink-mute   @DEFAULT_SINK@   toggle ;;
    mute_source) pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
    gui)         pavucontrol & ;;
esac
