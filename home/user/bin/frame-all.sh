#!/bin/sh
# frame-all: give frameless (client-side-decorated) application windows a
# normal xfwm4 title bar and border. The app's own UI (header bars etc.)
# is left untouched; only the window manager frame is added around it.
#
# Set XFCE Window Manager to plain "Xfmw4", with no compositor etc
#
# Each window is watched for as long as it exists: if the app switches back
# to frameless later (e.g. on maximize), the frame is added again.
#
# Start once per session: Settings -> Session and Startup -> Application Autostart.
# Needs: xprop, xdotool, flock

# WM_CLASS names to leave alone (extended regex, case-insensitive, | separated).
# Find a window's class with:  xprop WM_CLASS   (then click the window)
#   use window-name.sh for this
# Empty = frame everything.
EXCLUDE='protonvpn-app'

MAX_FIXES=5   # per window; stops a tug-of-war with an app that keeps resetting

# only one instance per session
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/frame-all.lock"
flock -n 9 || exit 0

STATE=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/frame-all.XXXXXX")
trap 'rm -rf "$STATE"' EXIT

# true if the window currently asks for no window manager frame
is_frameless() {
    p=$(xprop -id "$1" _GTK_FRAME_EXTENTS _MOTIF_WM_HINTS 2>/dev/null) || return 1
    echo "$p" | grep -q '^_GTK_FRAME_EXTENTS(.*=' && return 0
    mwm=$(echo "$p" | sed -n 's/^_MOTIF_WM_HINTS(.*= //p' | tr -d ' ')
    [ -n "$mwm" ] || return 1
    flags=${mwm%%,*}; rest=${mwm#*,}; rest=${rest#*,}; deco=${rest%%,*}
    [ $((flags & 2)) -ne 0 ] && [ $((deco)) -eq 0 ]
}

add_frame() {
    id=$1
    eval "$(xdotool getwindowgeometry --shell "$id" 2>/dev/null)" || return
    xprop -id "$id" -remove _GTK_FRAME_EXTENTS
    xprop -id "$id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "2, 0, 1, 0, 0"
    sleep 0.3
    # no frame yet? then re-show the window and put it back where it was
    if xprop -id "$id" _NET_FRAME_EXTENTS | grep -Eq 'not found|= 0, 0, 0, 0'; then
        xdotool windowunmap --sync "$id"; xdotool windowmap --sync "$id"
        xdotool windowmove "$id" "$X" "$Y"
    fi
}

watch_one() {
    id=$1
    mkdir "$STATE/$id" 2>/dev/null || return     # already being watched
    props=$(xprop -id "$id" WM_CLASS _NET_WM_WINDOW_TYPE 2>/dev/null)
    if  ! echo "$props" | grep -q '_NET_WM_WINDOW_TYPE_NORMAL' ||
        { [ -n "$EXCLUDE" ] && echo "$props" | grep '^WM_CLASS' | grep -Eiq "$EXCLUDE"; }
    then
        rmdir "$STATE/$id"; return               # not an app window, or excluded
    fi

    # xprop -spy prints the current values, then one line per change,
    # and exits when the window is closed
    n=0
    xprop -id "$id" -spy _GTK_FRAME_EXTENTS _MOTIF_WM_HINTS 2>/dev/null |
    while read -r _; do
        is_frameless "$id" || continue
        n=$((n + 1)); [ "$n" -gt "$MAX_FIXES" ] && break
        add_frame "$id"
    done
    rmdir "$STATE/$id" 2>/dev/null
}

# watch the window manager's client list; start a watcher for every window
# that appears (on start this also covers the windows already open)
prev=" "
xprop -root -spy _NET_CLIENT_LIST | while read -r line; do
    cur=" $(echo "$line" | grep -o '0x[0-9a-f]*' | tr '\n' ' ')"
    for id in $cur; do
        case "$prev" in *" $id "*) ;; *) watch_one "$id" & ;; esac
    done
    prev=$cur
done

