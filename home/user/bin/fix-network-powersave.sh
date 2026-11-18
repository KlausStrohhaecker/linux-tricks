#!/bin/sh
# Stops spurious NetworkManager "connection lost" popups caused by power saving.
#  - Turns Wi-Fi power save off in NetworkManager (any Wi-Fi card).
#  - Turns Energy Efficient Ethernet (EEE) off on every wired port that
#    supports it, now and on every link-up (NetworkManager dispatcher).
# Safe to run more than once. Needs root: sudo fix-network-powersave.sh

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo $0" >&2
    exit 1
fi

NM_CONF=/etc/NetworkManager/conf.d/zz-wifi-powersave-off.conf
DISPATCHER=/etc/NetworkManager/dispatcher.d/50-disable-eee

# Prints the names of physical wired network ports (USB adapters included).
wired_ports() {
    for dev in /sys/class/net/*; do
        name=${dev##*/}
        [ -e "$dev/device" ] || continue          # skip virtual (lo, VPN, bridges)
        [ -e "$dev/wireless" ] && continue         # skip Wi-Fi
        [ -e "$dev/phy80211" ] && continue
        [ "$(cat "$dev/type" 2>/dev/null)" = 1 ] || continue   # Ethernet only
        echo "$name"
    done
}

echo "== Wi-Fi power save"
cat > "$NM_CONF" <<'EOF'
[connection]
wifi.powersave = 2
EOF
echo "   wrote $NM_CONF"

echo "== Energy Efficient Ethernet"
cat > "$DISPATCHER" <<'EOF'
#!/bin/sh
# Turns EEE off whenever a physical wired port comes up.
[ "$2" = "up" ] || exit 0
dev=/sys/class/net/$1
[ -e "$dev/device" ] && [ ! -e "$dev/wireless" ] && [ ! -e "$dev/phy80211" ] || exit 0
[ "$(cat "$dev/type" 2>/dev/null)" = 1 ] || exit 0
ETHTOOL=$(command -v ethtool || echo /usr/sbin/ethtool)
"$ETHTOOL" --set-eee "$1" eee off >/dev/null 2>&1
exit 0
EOF
chown root:root "$DISPATCHER"
chmod 755 "$DISPATCHER"
echo "   wrote $DISPATCHER"

ETHTOOL=$(command -v ethtool || echo /usr/sbin/ethtool)
if [ ! -x "$ETHTOOL" ]; then
    echo "   ethtool is not installed, skipping (sudo apt install ethtool)"
else
    ports=$(wired_ports)
    [ -n "$ports" ] || echo "   no wired port found"
    for port in $ports; do
        if ! "$ETHTOOL" --show-eee "$port" >/dev/null 2>&1; then
            echo "   $port: EEE not supported, nothing to do"
        elif "$ETHTOOL" --show-eee "$port" 2>/dev/null | grep -q 'EEE status: disabled'; then
            echo "   $port: EEE already off"
        elif "$ETHTOOL" --set-eee "$port" eee off 2>/dev/null; then
            echo "   $port: EEE turned off"
        else
            echo "   $port: could not turn EEE off (card may not allow it)"
        fi
    done
fi

echo "== Applying"
systemctl reload NetworkManager
# Reconnect active Wi-Fi so the new power-save setting takes effect.
nmcli -g UUID,TYPE connection show --active | while IFS=: read -r uuid type; do
    if [ "$type" = "802-11-wireless" ]; then
        nmcli connection up uuid "$uuid" >/dev/null && echo "   reconnected Wi-Fi"
    fi
done

echo "== Result"
NetworkManager --print-config 2>/dev/null | grep '^wifi\.powersave' | sed 's/^/   /'
echo "DONE"
