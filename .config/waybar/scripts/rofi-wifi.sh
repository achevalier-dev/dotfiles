#!/usr/bin/env bash
# rofi wifi menu via nmcli

nmcli device wifi rescan 2>/dev/null

if [ "$(nmcli -t -f WIFI radio wifi)" = "enabled" ]; then
    toggle="󰖪  Disable Wi-Fi"
else
    toggle="󰖩  Enable Wi-Fi"
fi

# -t escapes ':' inside SSID as '\:'; protect it, split on real ':'
list=$(nmcli -t -f IN-USE,SIGNAL,SSID device wifi list \
    | sed 's/\\:/\x01/g' \
    | awk -F: '$3!=""{ ic=($1=="*")?"󰸞":" "; gsub(/\x01/,":",$3); printf "%s %3s  %s\n", ic, $2, $3 }')

chosen=$(printf "%s\n%s\n%s" "$toggle" "$list" "󰑓  Rescan" \
    | rofi -dmenu -i -p "Wi-Fi" -theme-str 'window {width: 30%;}')

[ -z "$chosen" ] && exit 0
case "$chosen" in
    *"Enable Wi-Fi")  nmcli radio wifi on;  exit 0 ;;
    *"Disable Wi-Fi") nmcli radio wifi off; exit 0 ;;
    *"Rescan")        exec "$0" ;;
esac

ssid=$(echo "$chosen" | sed -E 's/^.{1,3} +[0-9]+ +//')
[ -z "$ssid" ] && exit 0

if nmcli -t -f NAME connection show | sed 's/\\:/:/g' | grep -Fxq "$ssid"; then
    nmcli connection up id "$ssid"
elif ! nmcli device wifi connect "$ssid" 2>/dev/null; then
    pass=$(rofi -dmenu -password -p "Password for $ssid")
    [ -z "$pass" ] && exit 0
    nmcli device wifi connect "$ssid" password "$pass"
fi
