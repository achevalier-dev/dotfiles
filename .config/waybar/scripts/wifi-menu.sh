#!/usr/bin/env bash
# rofi Wi-Fi manager (nmcli).
# Menus are index-addressed (-format i) so SSIDs never get parsed back out of
# the rendered row — SSIDs may contain spaces, colons and markup characters.
set -uo pipefail

THEME='window {width: 38em;} listview {lines: 11;}'

rofi_menu() { # $1 = prompt; rows on stdin; echoes selected index ("" if cancelled)
    rofi -dmenu -i -markup-rows -format i -p "$1" -theme-str "$THEME"
}
rofi_input() { rofi -dmenu -p "$1" -theme-str 'window {width: 26em;} listview {lines: 0;}' </dev/null; }
rofi_pass()  { rofi -dmenu -password -p "$1" -theme-str 'window {width: 26em;} listview {lines: 0;}' </dev/null; }

notify()  { notify-send -a "Wi-Fi" -i network-wireless "$@"; }
esc()     { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dim()     { printf '<span foreground="#859289">%s</span>' "$(esc "$1")"; }

sig_icon() {
    local s=${1:-0}
    if   (( s >= 75 )); then printf '󰤨'
    elif (( s >= 50 )); then printf '󰤥'
    elif (( s >= 25 )); then printf '󰤢'
    elif (( s >  0 )); then printf '󰤟'
    else                     printf '󰤯'; fi
}

# ── State ────────────────────────────────────────────────────────────
radio_on() { [[ $(nmcli -t -f WIFI radio wifi 2>/dev/null) == enabled ]]; }

active_ssid() {
    nmcli -t -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null \
        | sed 's/\\:/\x01/g' | awk -F: '$1=="yes"{gsub(/\x01/,":",$2); print $2; exit}'
}

# Saved wireless profile names, one per line, colons unescaped.
saved_list() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | sed 's/\\:/\x01/g' \
        | awk -F: '$2=="802-11-wireless"{gsub(/\x01/,":",$1); print $1}'
}

declare -A SAVED=()
load_saved() {
    local n
    while IFS= read -r n; do [[ -n $n ]] && SAVED["$n"]=1; done < <(saved_list)
}
is_saved() { [[ -v SAVED["$1"] ]]; }

# ── Per-network submenu ──────────────────────────────────────────────
network_menu() {
    local ssid=$1 active=$2 saved=$3
    local -a disp=() act=()

    if [[ $active == yes ]]; then
        disp+=("󰖪  Disconnect");            act+=(down)
    else
        disp+=("󰄾  Connect");               act+=(up)
    fi
    if [[ $saved == yes ]]; then
        disp+=("󰆴  Forget this network");   act+=(forget)
    fi
    disp+=("󰒓  Edit connection…");          act+=(edit)
    disp+=("󰌍  Back");                      act+=(back)

    local idx
    idx=$(printf '%s\n' "${disp[@]}" | rofi_menu "$(esc "$ssid")")
    [[ -z $idx ]] && exit 0

    case ${act[$idx]} in
        up)
            notify "Connecting" "$ssid…"
            if nmcli -w 25 connection up id "$ssid" >/dev/null 2>&1; then
                notify "Connected" "$ssid"
            else
                notify -u critical "Connection failed" "$ssid"
            fi ;;
        down)
            nmcli connection down id "$ssid" >/dev/null 2>&1 \
                && notify "Disconnected" "$ssid" ;;
        forget)
            nmcli connection delete id "$ssid" >/dev/null 2>&1 \
                && notify "Forgotten" "$ssid" ;;
        edit)   nm-connection-editor & ;;
        back)   exec "$0" ;;
    esac
}

# ── Connect to a network we have no profile for ──────────────────────
connect_new() {
    local ssid=$1 secured=$2 pass=""
    if [[ $secured == yes ]]; then
        pass=$(rofi_pass "Password for $ssid")
        [[ -z $pass ]] && exit 0
    fi

    notify "Connecting" "$ssid…"
    if [[ -n $pass ]]; then
        nmcli -w 30 device wifi connect "$ssid" password "$pass" >/dev/null 2>&1
    else
        nmcli -w 30 device wifi connect "$ssid" >/dev/null 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        notify "Connected" "$ssid"
    else
        notify -u critical "Connection failed" "$ssid — wrong password?"
    fi
}

connect_hidden() {
    local ssid pass
    ssid=$(rofi_input "Hidden SSID"); [[ -z $ssid ]] && exit 0
    pass=$(rofi_pass "Password for $ssid")
    notify "Connecting" "$ssid…"
    if [[ -n $pass ]]; then
        nmcli -w 30 device wifi connect "$ssid" password "$pass" hidden yes >/dev/null 2>&1
    else
        nmcli -w 30 device wifi connect "$ssid" hidden yes >/dev/null 2>&1
    fi
    (( $? == 0 )) && notify "Connected" "$ssid" || notify -u critical "Connection failed" "$ssid"
}

# ── Main menu ────────────────────────────────────────────────────────
declare -a disp=() act=() arg=()

if ! radio_on; then
    disp+=("󰖩  Enable Wi-Fi"); act+=(radio_on); arg+=("")
else
    nmcli device wifi rescan >/dev/null 2>&1 &   # refresh in the background

    current=$(active_ssid)
    load_saved

    # Strongest AP per SSID: IN-USE / SIGNAL / SECURITY / SSID
    # -t escapes ':' inside the SSID as '\:' — swap it out before splitting.
    while IFS=$'\t' read -r inuse signal security ssid; do
        [[ -z $ssid ]] && continue

        saved=no; is_saved "$ssid" && saved=yes
        act_flag=no; [[ $inuse == "*" ]] && act_flag=yes

        secured=no; [[ -n $security && $security != "--" ]] && secured=yes
        lock=""; [[ $secured == yes ]] && lock="󰌾 "

        meta="${signal}%"
        [[ $secured == yes ]] && meta+=" · ${security}"
        [[ $saved == yes ]] && meta+=" · saved"

        mark="  "; [[ $act_flag == yes ]] && mark="󰸞 "

        disp+=("$(printf '%s%s  %s %s   %s' "$mark" "$(sig_icon "$signal")" "$lock" \
                    "$(esc "$ssid")" "$(dim "$meta")")")
        if [[ $act_flag == yes || $saved == yes ]]; then
            act+=(menu)
        else
            act+=(new)
        fi
        arg+=("$ssid"$'\t'"$act_flag"$'\t'"$saved"$'\t'"$secured")
    done < <(
        nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no 2>/dev/null \
        | sed 's/\\:/\x01/g' \
        | awk -F: '
            $4 == "" { next }
            {
                ssid = $4
                sig  = $2 + 0
                # IN-USE is OR-ed across every AP of the SSID: the associated AP
                # is often not the strongest one, and keeping only the strongest
                # row would drop the "connected" marker.
                if ($1 == "*") inuse[ssid] = 1
                if (!(ssid in best) || sig > best[ssid]) {
                    best[ssid] = sig; sec[ssid] = $3
                }
            }
            END {
                for (s in best) {
                    name = s; gsub(/\x01/, ":", name)
                    printf "%s\t%d\t%s\t%s\n", (s in inuse ? "*" : " "), best[s], sec[s], name
                }
            }' \
        | sort -t$'\t' -k1,1r -k2,2nr
    )

    disp+=("󰛳  Hidden network…");   act+=(hidden);   arg+=("")
    disp+=("󰑓  Rescan");            act+=(rescan);   arg+=("")
    disp+=("󰖪  Disable Wi-Fi");     act+=(radio_off);arg+=("")
    disp+=("󰒓  Network settings…"); act+=(settings); arg+=("")
fi

prompt="Wi-Fi"
[[ -n ${current:-} ]] && prompt="Wi-Fi · $current"

idx=$(printf '%s\n' "${disp[@]}" | rofi_menu "$prompt")
[[ -z $idx ]] && exit 0

case ${act[$idx]} in
    radio_on)  nmcli radio wifi on;  notify "Wi-Fi enabled" ;;
    radio_off) nmcli radio wifi off; notify "Wi-Fi disabled" ;;
    rescan)    nmcli device wifi rescan >/dev/null 2>&1; exec "$0" ;;
    hidden)    connect_hidden ;;
    settings)  nm-connection-editor & ;;
    menu)
        IFS=$'\t' read -r ssid a s _ <<<"${arg[$idx]}"
        network_menu "$ssid" "$a" "$s" ;;
    new)
        IFS=$'\t' read -r ssid _ _ sec <<<"${arg[$idx]}"
        connect_new "$ssid" "$sec" ;;
esac
