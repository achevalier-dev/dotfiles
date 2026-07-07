#!/bin/bash
export SWAYSOCK=$(ls /run/user/$(id -u)/sway-ipc.*.sock 2>/dev/null | head -1)

WS="dashboard"
swaymsg "workspace $WS" >/dev/null

wait_for() {
    local id="$1"
    for _ in $(seq 1 50); do
        if swaymsg -t get_tree | grep -q "\"app_id\": \"$id\""; then
            return 0
        fi
        sleep 0.1
    done
}

foot -a dash_btop -e btop &
wait_for dash_btop
swaymsg '[app_id="dash_btop"] focus' >/dev/null
swaymsg splith >/dev/null

if command -v sensors >/dev/null 2>&1; then
    foot -a dash_sensors -e watch -n 2 sensors &
else
    foot -a dash_sensors -e sh -c 'echo "lm_sensors not installed - sudo dnf install lm_sensors"; exec $SHELL' &
fi
wait_for dash_sensors
swaymsg '[app_id="dash_sensors"] focus' >/dev/null
swaymsg resize set width 35 ppt >/dev/null
swaymsg splitv >/dev/null

foot -a dash_fastfetch -e sh -c 'fastfetch; SKIP_FASTFETCH=1 exec $SHELL' &
wait_for dash_fastfetch
swaymsg '[app_id="dash_fastfetch"] focus' >/dev/null
