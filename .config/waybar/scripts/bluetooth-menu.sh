#!/usr/bin/env bash
# rofi Bluetooth manager (bluetoothctl).
# Index-addressed menus (-format i) — device names are never parsed back out.
set -uo pipefail

THEME='window {width: 38em;} listview {lines: 11;}'
SCAN_SECS=10

rofi_menu() { rofi -dmenu -i -markup-rows -format i -p "$1" -theme-str "$THEME"; }

notify() { notify-send -a "Bluetooth" -i bluetooth "$@"; }
esc()    { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dim()    { printf '<span foreground="#859289">%s</span>' "$(esc "$1")"; }

powered() { bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; }

# ── Device introspection ─────────────────────────────────────────────
# Sets: D_CONNECTED D_PAIRED D_TRUSTED D_ICON D_BATTERY
dev_info() {
    local mac=$1 info
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    D_CONNECTED=no; D_PAIRED=no; D_TRUSTED=no; D_ICON=""; D_BATTERY=""
    grep -q "Connected: yes" <<<"$info" && D_CONNECTED=yes
    grep -q "Paired: yes"    <<<"$info" && D_PAIRED=yes
    grep -q "Trusted: yes"   <<<"$info" && D_TRUSTED=yes
    D_ICON=$(sed -n 's/^\s*Icon:\s*//p' <<<"$info" | head -1)
    # "Battery Percentage: 0x54 (84)" → 84
    D_BATTERY=$(sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p' <<<"$info" | head -1)
}

type_icon() {
    case ${1:-} in
        audio-headset|audio-headphones) printf '󰋋' ;;
        audio-card)                     printf '󰓃' ;;
        input-mouse)                    printf '󰍽' ;;
        input-keyboard)                 printf '󰌌' ;;
        input-gaming)                   printf '󰊴' ;;
        phone)                          printf '󰏲' ;;
        computer)                       printf '󰌢' ;;
        printer)                        printf '󰐪' ;;
        camera-video|camera-photo)      printf '󰄀' ;;
        *)                              printf '󰂯' ;;
    esac
}

# ── Per-device submenu ───────────────────────────────────────────────
device_menu() {
    local mac=$1 name=$2
    dev_info "$mac"

    local -a disp=() act=()
    if [[ $D_CONNECTED == yes ]]; then
        disp+=("󰂲  Disconnect");      act+=(disconnect)
    else
        disp+=("󰂱  Connect");         act+=(connect)
    fi
    if [[ $D_PAIRED == yes ]]; then
        if [[ $D_TRUSTED == yes ]]; then
            disp+=("󰗧  Untrust");     act+=(untrust)
        else
            disp+=("󰄾  Trust (auto-connect)"); act+=(trust)
        fi
        disp+=("󰆴  Remove device");   act+=(remove)
    else
        disp+=("󰌘  Pair");            act+=(pair)
    fi
    disp+=("󰌍  Back");                act+=(back)

    local idx; idx=$(printf '%s\n' "${disp[@]}" | rofi_menu "$(esc "$name")")
    [[ -z $idx ]] && exit 0

    case ${act[$idx]} in
        connect)
            notify "Connecting" "$name…"
            if bluetoothctl connect "$mac" >/dev/null 2>&1; then
                notify "Connected" "$name"
            else
                notify -u critical "Connection failed" "$name"
            fi ;;
        disconnect)
            bluetoothctl disconnect "$mac" >/dev/null 2>&1 && notify "Disconnected" "$name" ;;
        pair)
            notify "Pairing" "$name…"
            if bluetoothctl pair "$mac" >/dev/null 2>&1; then
                bluetoothctl trust "$mac"   >/dev/null 2>&1
                bluetoothctl connect "$mac" >/dev/null 2>&1
                notify "Paired" "$name"
            else
                notify -u critical "Pairing failed" "$name"
            fi ;;
        trust)   bluetoothctl trust "$mac"   >/dev/null 2>&1 && notify "Trusted" "$name" ;;
        untrust) bluetoothctl untrust "$mac" >/dev/null 2>&1 && notify "Untrusted" "$name" ;;
        remove)  bluetoothctl remove "$mac"  >/dev/null 2>&1 && notify "Removed" "$name" ;;
        back)    exec "$0" ;;
    esac
}

# ── Main menu ────────────────────────────────────────────────────────
declare -a disp=() act=() arg=()

if ! powered; then
    disp+=("󰂯  Enable Bluetooth"); act+=(power_on); arg+=("")
    disp+=("󰒓  Open Blueman");     act+=(gui);      arg+=("")
else
    # Known devices, connected first, then paired, then merely discovered.
    declare -a rows_conn=() rows_paired=() rows_other=()
    declare -a args_conn=() args_paired=() args_other=()

    while read -r _ mac name; do
        [[ -z ${mac:-} ]] && continue
        dev_info "$mac"

        meta=""
        [[ -n $D_BATTERY ]] && meta="󰁹 ${D_BATTERY}%"
        [[ $D_PAIRED == yes && $D_CONNECTED != yes ]] && meta="${meta:+$meta · }paired"
        [[ $D_TRUSTED == yes ]] && meta="${meta:+$meta · }trusted"

        mark="  "; [[ $D_CONNECTED == yes ]] && mark="󰸞 "
        row=$(printf '%s%s  %s   %s' "$mark" "$(type_icon "$D_ICON")" \
                     "$(esc "$name")" "$(dim "$meta")")

        if   [[ $D_CONNECTED == yes ]]; then rows_conn+=("$row");   args_conn+=("$mac"$'\t'"$name")
        elif [[ $D_PAIRED    == yes ]]; then rows_paired+=("$row"); args_paired+=("$mac"$'\t'"$name")
        else                                 rows_other+=("$row");  args_other+=("$mac"$'\t'"$name")
        fi
    done < <(bluetoothctl devices 2>/dev/null)

    for i in "${!rows_conn[@]}";   do disp+=("${rows_conn[$i]}");   act+=(device); arg+=("${args_conn[$i]}");   done
    for i in "${!rows_paired[@]}"; do disp+=("${rows_paired[$i]}"); act+=(device); arg+=("${args_paired[$i]}"); done
    for i in "${!rows_other[@]}";  do disp+=("${rows_other[$i]}");  act+=(device); arg+=("${args_other[$i]}");  done

    disp+=("󰑓  Scan for devices ($SCAN_SECS s)"); act+=(scan);      arg+=("")
    disp+=("󰂲  Disable Bluetooth");               act+=(power_off); arg+=("")
    disp+=("󰒓  Open Blueman");                    act+=(gui);       arg+=("")
fi

idx=$(printf '%s\n' "${disp[@]}" | rofi_menu "Bluetooth")
[[ -z $idx ]] && exit 0

case ${act[$idx]} in
    power_on)  bluetoothctl power on  >/dev/null 2>&1; notify "Bluetooth enabled";  sleep 1; exec "$0" ;;
    power_off) bluetoothctl power off >/dev/null 2>&1; notify "Bluetooth disabled" ;;
    scan)
        notify "Scanning" "Looking for devices for ${SCAN_SECS}s…"
        bluetoothctl --timeout "$SCAN_SECS" scan on >/dev/null 2>&1
        exec "$0" ;;
    gui)       blueman-manager & ;;
    device)
        IFS=$'\t' read -r mac name <<<"${arg[$idx]}"
        device_menu "$mac" "$name" ;;
esac
