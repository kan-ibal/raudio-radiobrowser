#!/bin/bash
# ==============================================================================
# rAudio Radio Browser Native Addon Uninstaller
# Invoked via rAudio Addons Manager: /srv/http/settings/addonsprogress.php
# Or executed standalone via SSH on Raspberry Pi
# ==============================================================================

set -e

echo "==> [rAudio Addon] Removing Radio Browser Plugin..."
rm -f /srv/http/bash/radiobrowser.sh
rm -f /srv/http/app/radiobrowser.php
rm -f /srv/http/assets/js/radiobrowser-webradio-hook.js
rm -rf /srv/http/radiobrowser
rm -rf /srv/http/data/radiobrowser
rm -f /srv/http/data/system/raudio-radiobrowser.conf
rm -f /usr/local/bin/uninstall_radiobrowser.sh

# Remove script injection from entry points
for file in "/srv/http/app/index.php" "/srv/http/index.html" "/srv/http/app/templates/library.html"; do
    if [[ -f "$file" ]]; then
        sed -i '/radiobrowser-webradio-hook.js/d' "$file" 2>/dev/null || true
    fi
done

echo "==> Notifying rAudio Redis & WebRadio database..."
command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
command -v redis-cli &>/dev/null && redis-cli publish notify '{"title":"Radio Browser","text":"Radio Browser plugin uninstalled"}' &>/dev/null || true
[[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true
command -v mpc &>/dev/null && mpc update Webradio &>/dev/null || true

echo "==> [rAudio Addon] Radio Browser Plugin successfully uninstalled."
exit 0
