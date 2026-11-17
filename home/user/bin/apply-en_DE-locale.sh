#!/bin/bash
# Re-applies en_DE for LC_TIME, LC_NUMERIC, LC_MONETARY and LC_MEASUREMENT,
# e.g. after Mint's Language Settings reset them.
# Install:  install -m 755 apply-en_DE-locale ~/bin/
# Run:      apply-en_DE-locale.sh   (asks for sudo for the system-wide part)
set -euo pipefail
VARS=(LC_TIME LC_NUMERIC LC_MONETARY LC_MEASUREMENT)

locale -a | grep -qi '^en_DE\.utf-\?8$' || {
    echo "en_DE is not compiled. Run: sudo locale-gen" >&2; exit 1; }

sudo update-locale "${VARS[@]/%/=en_DE.UTF-8}"

PAM="$HOME/.pam_environment"
if [ -f "$PAM" ]; then
    for v in "${VARS[@]}"; do
        sed -i "/^$v=/d" "$PAM"
        echo "$v=en_DE.UTF-8" >> "$PAM"
    done
fi

# Mint's Language Settings writes ~/.xsessionrc, which runs last at login
# and overrides everything above.
XS="$HOME/.xsessionrc"
if [ -f "$XS" ]; then
    sed -i -E "s/\b(LC_TIME|LC_NUMERIC|LC_MONETARY|LC_MEASUREMENT)=[A-Za-z_]+\.UTF-8/\1=en_DE.UTF-8/" "$XS"
fi
echo "Done. Log out and back in."
