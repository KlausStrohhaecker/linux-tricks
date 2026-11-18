#!/usr/bin/env bash
# Popup "Battery is charging" only when a battery really charges
# (status Charging AND power_now > 0 for several checks in a row).
# Works around the X240 EC flipping BAT1 Charging/Not charging at 0 W
# inside the charge-threshold window. Also notifies when AC is unplugged.

INTERVAL=5        # seconds between checks
NEED=3            # consecutive real-charging checks before notifying
QUIET=60          # seconds without real charging before re-arming

PS=/sys/class/power_supply

# Single instance
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/battery-charge-notify.lock"
flock -n 9 || exit 0

read_ac() { cat "$PS/AC/online" 2>/dev/null || echo 1; }

streak=0
armed=1
idle_since=$(date +%s)
last_ac=$(read_ac)

while sleep "$INTERVAL"; do
    now=$(date +%s)
    charging=""
    for bat in "$PS"/BAT*; do
        [ -r "$bat/status" ] || continue
        status=$(cat "$bat/status")
        power=$(cat "$bat/power_now" 2>/dev/null || echo 0)
        if [ "$status" = "Charging" ] && [ "${power:-0}" -gt 0 ]; then
            cap=$(cat "$bat/capacity" 2>/dev/null)
            watts=$(awk -v p="$power" 'BEGIN{printf "%.1f", p/1000000}')
            charging+="${charging:+, }$(basename "$bat") ${cap} % – ${watts} W"
        fi
    done

    if [ -n "$charging" ]; then
        streak=$((streak + 1))
        idle_since=$now
        if [ "$armed" = 1 ] && [ "$streak" -ge "$NEED" ]; then
            notify-send -a "Power Manager" -i battery-full-charging \
                "Battery is charging" "$charging"
            armed=0
        fi
    else
        streak=0
        if [ "$armed" = 0 ] && [ $((now - idle_since)) -ge "$QUIET" ]; then
            armed=1
        fi
    fi

    ac=$(read_ac)
    if [ "$last_ac" = 1 ] && [ "$ac" = 0 ]; then
        notify-send -a "Power Manager" -i battery-good \
            "Running on battery" "Power cable unplugged"
    fi
    last_ac=$ac
done
