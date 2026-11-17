#!/bin/bash
# Installs the manually patched en_US locale as a new locale "en_DE"
# that package updates will not overwrite.
#
# Run with:  sudo bash install-en_DE-locale.sh
# Run it BEFORE the next update of the "locales" package, because that
# update would restore the stock /usr/share/i18n/locales/en_US.
set -euo pipefail

SRC=/usr/share/i18n/locales/en_US
DEST_DIR=/usr/local/share/i18n/locales
DEST=$DEST_DIR/en_DE
LINK=/usr/share/i18n/locales/en_DE
SUPPORTED=/var/lib/locales/supported.d/en_DE
VARS=(LC_TIME LC_NUMERIC LC_MONETARY LC_MEASUREMENT)

[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo." >&2; exit 1; }
TARGET_USER=${SUDO_USER:-root}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# 1. Make sure the source really is the patched file.
if [ -e "$DEST" ]; then
    echo "en_DE source already exists at $DEST - keeping it."
else
    if dpkg -V locales 2>/dev/null | grep -q " $SRC\$"; then
        echo "OK: $SRC differs from the package version (patched)."
    else
        echo "WARNING: $SRC matches the stock package version."
        echo "Your patch may already have been overwritten by an update."
        read -r -p "Continue anyway? [y/N] " a
        [ "${a,,}" = y ] || exit 1
    fi
    mkdir -p "$DEST_DIR"
    cp -a "$SRC" "$DEST_DIR/en_US.patched.orig"   # backup
    cp -a "$SRC" "$DEST"
    echo "Copied patched file to $DEST (backup: $DEST_DIR/en_US.patched.orig)."
fi

# 2. locale-gen only looks in /usr/share/i18n/locales, so link it there.
#    No package owns this name, so updates leave the link alone.
ln -sfn "$DEST" "$LINK"

# 3. Register it so locale-gen rebuilds it after every libc/locales update.
mkdir -p "$(dirname "$SUPPORTED")"
echo "en_DE.UTF-8 UTF-8" > "$SUPPORTED"
locale-gen

locale -a | grep -qi '^en_DE\.utf-\?8$' || { echo "ERROR: en_DE was not generated." >&2; exit 1; }
echo "en_DE.UTF-8 compiled."

# 4. Apply the four categories system-wide.
update-locale "${VARS[@]/%/=en_DE.UTF-8}"
echo "Set ${VARS[*]} in /etc/default/locale."

# 5. Per-user override file (Mint's Language Settings writes here; if it has
#    other values for these variables they would win over /etc/default/locale).
PAM="$TARGET_HOME/.pam_environment"
if [ -f "$PAM" ]; then
    for v in "${VARS[@]}"; do
        sed -i "/^$v=/d" "$PAM"
        echo "$v=en_DE.UTF-8" >> "$PAM"
    done
    chown "$TARGET_USER": "$PAM"
    echo "Updated $PAM."
fi

echo
echo "Check:  LC_TIME=en_DE.UTF-8 date"
echo "        LC_ALL=en_DE.UTF-8 locale -k first_weekday decimal_point currency_symbol"
echo "Then log out and back in."
