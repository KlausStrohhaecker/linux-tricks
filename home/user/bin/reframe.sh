#!/bin/sh
# bind under Settings → Keyboard → Application Shortcuts, for example to Super+F.
id=$(xdotool selectwindow)
eval "$(xdotool getwindowgeometry --shell "$id")"   # remembers X and Y
xprop -id "$id" -remove _GTK_FRAME_EXTENTS
xprop -id "$id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "2, 0, 1, 0, 0"
sleep 0.3
# no frame yet? then re-show the window and put it back where it was
if xprop -id "$id" _NET_FRAME_EXTENTS | grep -Eq 'not found|= 0, 0, 0, 0'; then
  xdotool windowunmap --sync "$id"; xdotool windowmap --sync "$id"
  xdotool windowmove "$id" "$X" "$Y"
fi

