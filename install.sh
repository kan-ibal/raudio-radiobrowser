#!/bin/bash
# ==============================================================================
# rAudio Radio Browser Native Addon Installer
# executed standalone via SSH on Raspberry Pi
# https://github.com/kan-ibal/raudio-radiobrowser
# ==============================================================================

set -e

DIR_APP="/srv/http/app"
DIR_BASH="/srv/http/bash"
DIR_DATA="/srv/http/data"
# Primary rAudio directory is /srv/http/data/webradio (singular)
DIR_WEBRADIO="$DIR_DATA/webradio"
DIR_RB_ROOT="$DIR_WEBRADIO/Radio Browser"
DIR_MPD_WEBRADIO="/mnt/MPD/Webradio/Radio Browser"
DIR_RADIOBROWSER_WEB="/srv/http/radiobrowser"
DIR_ADDONS="$DIR_DATA/addons"
DIR_SYSTEM="$DIR_DATA/system"
DIR_ASSETS_JS="/srv/http/assets/js"
UNINSTALL_BIN="/usr/local/bin/uninstall_radiobrowser.sh"

echo "==> [rAudio Addon] Starting Radio Browser Plugin Installation..."
echo "==> Target Architecture: Arch Linux ARM / Raspberry Pi"

echo "==> [1/7] Initializing /srv/http/data/webradio"
mkdir -p "$DIR_APP" "$DIR_BASH" "$DIR_WEBRADIO" "$DIR_RB_ROOT" \
         "$DIR_RADIOBROWSER_WEB" "$DIR_DATA/radiobrowser" "$DIR_ADDONS" "$DIR_SYSTEM" "$DIR_ASSETS_JS"

# 2. Deploy native bash engine with Directory/data format
echo "==> [2/7] Installing native bash engine at $DIR_BASH/radiobrowser.sh..."
cat <<'ENGINE_EOF' > "$DIR_BASH/radiobrowser.sh"
#!/bin/bash
# ==============================================================================
# rAudio Radio Browser Native Bash Engine
# Target Path on rAudio: /srv/http/bash/radiobrowser.sh
# Provides native CLI and background utilities for rAudio (Arch Linux ARM / MPD / Redis)
# ==============================================================================

DIR_DATA="/srv/http/data"
# Primary rAudio directory is now /srv/http/data/webradio (singular)
DIR_WEBRADIO="$DIR_DATA/webradio"

# Dedicated Radio Browser folders inside rAudio Web Radio
DIR_RB_ROOT="$DIR_WEBRADIO/Radio Browser"
DIR_MPD_WEBRADIO="/mnt/MPD/Webradio/Radio Browser"
DIR_RADIOBROWSER_WEB="/srv/http/radiobrowser"

USER_AGENT="rAudio-RadioBrowser-Addon/1.0.0 (https://github.com/kan-ibal/raudio-radiobrowser)"
MIRRORS=(
    "https://de1.api.radio-browser.info"
    "https://nl1.api.radio-browser.info"
    "https://at1.api.radio-browser.info"
    "https://all.api.radio-browser.info"
)

# Helper: Pure bash URL-encoding to eliminate curl blank argument errors
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Helper: Query distributed Radio Browser mirrors with automated failover
query_rb() {
    local endpoint="$1"
    local params="$2"
    for mirror in "${MIRRORS[@]}"; do
        local url="${mirror}${endpoint}"
        [[ -n "$params" ]] && url="${url}?${params}"
        local resp
        resp=$(curl -s --max-time 6 -H "User-Agent: $USER_AGENT" -H "Accept: application/json" "$url" 2>/dev/null)
        if [[ $? -eq 0 && -n "$resp" && "$resp" != "[]" ]]; then
            echo "$resp"
            return 0
        fi
    done
    echo "[]"
    return 1
}

# 1. Search stations with name, tag/genre, and country code
cmd_search() {
    local name=""
    local tag=""
    local countrycode=""
    local codec=""
    local bitrate="0"
    local limit="25"

    # Support named flags (--name, --tag/--genre, --country/--countrycode, --codec, --bitrate, --limit)
    if [[ "$1" =~ ^-- ]]; then
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name|-n)
                    name="$2"; shift 2 ;;
                --tag|--genre|-t|-g)
                    tag="$2"; shift 2 ;;
                --country|--countrycode|-c)
                    countrycode="$2"; shift 2 ;;
                --codec)
                    codec="$2"; shift 2 ;;
                --bitrate|-b)
                    bitrate="$2"; shift 2 ;;
                --limit|-l)
                    limit="$2"; shift 2 ;;
                *)
                    shift ;;
            esac
        done
    else
        # Support positional arguments:
        # $1: name
        # $2: tag / genre
        # $3: countrycode (or legacy codec if 3+ chars matching known audio codec)
        # $4: codec
        # $5: bitrate
        # $6: limit
        name="$1"
        tag="$2"
        local arg3="$3"
        local arg4="$4"
        local arg5="$5"
        local arg6="$6"

        local upper3="${arg3^^}"
        if [[ "$upper3" =~ ^(FLAC|MP3|AAC|OGG|OPUS|ALL)$ ]]; then
            # Legacy positional format: name tag codec bitrate limit
            codec="$arg3"
            bitrate="${arg4:-0}"
            limit="${arg5:-25}"
        else
            # New positional format: name tag/genre countrycode codec bitrate limit
            countrycode="$arg3"
            codec="$arg4"
            bitrate="${arg5:-0}"
            limit="${arg6:-25}"
        fi
    fi

    local query="hidebroken=true&order=votes&reverse=true&limit=${limit}"
    [[ -n "$name" ]] && query="${query}&name=$(urlencode "$name")"
    [[ -n "$tag" ]] && query="${query}&tag=$(urlencode "$tag")"
    [[ -n "$countrycode" ]] && query="${query}&countrycode=$(urlencode "$countrycode")"
    [[ -n "$codec" && "${codec^^}" != "ALL" ]] && query="${query}&codec=$(urlencode "$codec")"
    [[ "$bitrate" -gt 0 ]] && query="${query}&bitrateMin=${bitrate}"

    local empty_icon="data:image/svg+xml;utf8,%3Csvg xmlns=\x27http://www.w3.org/2000/svg\x27 width=\x2744\x27 height=\x2744\x27 viewBox=\x270 0 24 24\x27%3E%3C/svg%3E"
    local raw_res
    raw_res=$(query_rb "/json/stations/search" "$query")

    # In case of station with no icon and receiving "data:image/svg+xml,<svg xmlns=", an empty icon is displayed
    echo "$raw_res" | sed -E "s|\"favicon\":\"\"|\"favicon\":\"$empty_icon\"|g; s|\"favicon\":null|\"favicon\":\"$empty_icon\"|g; s|\"favicon\":\"data:image/svg\+xml,<svg[^\"]*\"|\"favicon\":\"$empty_icon\"|g"
}

# 2. Resolve stream URL and play via MPD
cmd_play() {
    local target="$1"
    local resolved_url="$target"

    # Check if target is a UUID
    if [[ "$target" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        local res
        res=$(query_rb "/json/url/$target")
        resolved_url=$(echo "$res" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
        [[ -z "$resolved_url" ]] && resolved_url="$target"
    fi

    # Add to MPD queue using mpc
    if command -v mpc &>/dev/null; then
        mpc add "$resolved_url"
        local pos
        pos=$(mpc playlist | wc -l)
        mpc play "$pos"
        # Notify rAudio MPD / Redis state
        command -v redis-cli &>/dev/null && redis-cli publish notify '{"title":"Radio Browser","text":"Streaming started"}' &>/dev/null
        echo "{\"success\":true,\"url\":\"$resolved_url\",\"position\":$pos}"
    else
        echo "{\"success\":false,\"error\":\"mpc not found on system\"}"
    fi
}

# 3. Save to rAudio native WebRadio library using new format: <Directory>/data
cmd_save() {
    local name="$1"
    local url="$2"
    local icon="$3"
    local subfolder="$4"

    [[ -z "$name" || -z "$url" ]] && { echo '{"success":false,"error":"Missing name or url"}'; return 1; }

    local target_parent="$DIR_RB_ROOT"
    if [[ -n "$subfolder" && "$subfolder" != "." ]]; then
        target_parent="$DIR_RB_ROOT/$subfolder"
    fi

    mkdir -p "$DIR_WEBRADIO" "$DIR_RB_ROOT" "$target_parent"

    # Clean station folder name
    local clean_name
    clean_name=$(echo "$name" | tr -d '/\\:*?"<>|' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
    [[ -z "$clean_name" ]] && clean_name="Station_$(date +%s)"

    # NEW FORMAT: Station is a Directory, with a 'data' file containing the stream hyperlink
    local station_dir="$target_parent/$clean_name"
    mkdir -p "$station_dir"

    # Write stream hyperlink into data file
    printf "%s\n" "$url" > "$station_dir/data"
    chmod 664 "$station_dir/data" 2>/dev/null || true

    local regex_b64='^data:image/svg\+xml;base64,(.+)'
    if [[ -n "$icon" && "$icon" =~ ^https?:// ]]; then
        curl -sL --max-time 6 "$icon" -o "$station_dir/coverart.jpg" 2>/dev/null || true
        if [[ -s "$station_dir/coverart.jpg" ]]; then
            chmod 664 "$station_dir/coverart.jpg" 2>/dev/null || true
            cp -f "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
            cp -f "$station_dir/coverart.jpg" "$station_dir/thumb.jpg" 2>/dev/null || true
        fi
    elif [[ -n "$icon" && "$icon" =~ $regex_b64 ]]; then
        local b64_data="${BASH_REMATCH[1]}"
        echo "$b64_data" | base64 -d > "$station_dir/coverart.svg" 2>/dev/null || true
        if [[ -s "$station_dir/coverart.svg" ]]; then
            chmod 664 "$station_dir/coverart.svg" 2>/dev/null || true
            cp -f "$station_dir/coverart.svg" "$station_dir/cover.svg" 2>/dev/null || true
            cp -f "$station_dir/coverart.svg" "$station_dir/thumb.svg" 2>/dev/null || true
        fi
    fi

    # In case of station with no icon and receiving "data:image/svg+xml,<svg xmlns=", create empty icon
    if [[ ! -s "$station_dir/coverart.jpg" && ! -s "$station_dir/coverart.svg" ]]; then
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 24 24"></svg>\n' > "$station_dir/coverart.svg"
        chmod 664 "$station_dir/coverart.svg" 2>/dev/null || true
        cp -f "$station_dir/coverart.svg" "$station_dir/cover.svg" 2>/dev/null || true
        cp -f "$station_dir/coverart.svg" "$station_dir/thumb.svg" 2>/dev/null || true
        if [[ -f "/srv/http/assets/img/coverart.svg" ]]; then
            cp -f "/srv/http/assets/img/coverart.svg" "$station_dir/coverart.svg" 2>/dev/null || true
            cp -f "/srv/http/assets/img/coverart.svg" "$station_dir/thumb.svg" 2>/dev/null || true
        fi
    fi

    # MPD M3U playlist file if /mnt/MPD/Webradio exists
    if [[ -d "/mnt/MPD/Webradio" ]]; then
        local mpd_target="$DIR_MPD_WEBRADIO"
        [[ -n "$subfolder" && "$subfolder" != "." ]] && mpd_target="$DIR_MPD_WEBRADIO/$subfolder"
        mkdir -p "$mpd_target" 2>/dev/null || true
        cat <<M3U_EOF > "$mpd_target/$clean_name.m3u"
#EXTM3U
#EXTINF:-1,$clean_name
$url
M3U_EOF
        chmod 664 "$mpd_target/$clean_name.m3u" 2>/dev/null || true
        chown http:http "$mpd_target/$clean_name.m3u" 2>/dev/null || true
    fi

    chmod 775 "$station_dir" 2>/dev/null || true
    chown -R http:http "$station_dir" 2>/dev/null || true

    # Notify rAudio Redis pub/sub & MPD
    command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
    [[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true
    command -v mpc &>/dev/null && mpc update Webradio &>/dev/null || true

    echo "{\"success\":true,\"saved\":\"$clean_name\",\"path\":\"$station_dir/data\",\"dir\":\"$station_dir\"}"
}

# 4. Probe ICY headers for high-fidelity specs
cmd_metadata() {
    local url="$1"
    [[ -z "$url" ]] && { echo '{"error":"Missing URL"}'; return 1; }

    local headers
    headers=$(curl -sI -m 5 -H "Icy-MetaData: 1" -H "User-Agent: rAudio-ICY-Prober/1.0" "$url" 2>/dev/null)
    local icy_name icy_br icy_genre content_type
    icy_name=$(echo "$headers" | grep -i '^icy-name:' | cut -d: -f2- | tr -d '\r\n' | xargs)
    icy_br=$(echo "$headers" | grep -i '^icy-br:' | cut -d: -f2- | tr -d '\r\n' | xargs)
    icy_genre=$(echo "$headers" | grep -i '^icy-genre:' | cut -d: -f2- | tr -d '\r\n' | xargs)
    content_type=$(echo "$headers" | grep -i '^content-type:' | cut -d: -f2- | tr -d '\r\n' | xargs)

    cat <<EOF
{
  "url": "$url",
  "icyName": "$icy_name",
  "bitrate": "${icy_br:-320}",
  "genre": "$icy_genre",
  "contentType": "${content_type:-audio/mpeg}"
}
EOF
}

# 5. Move all webradio images to the station directory with data file
cmd_move_images() {
    echo "==> Moving all webradio images to their station folder containing 'data'..."
    local count=0
    local dirs_checked=0

    # 1. Iterate over every station directory containing a 'data' file
    while IFS= read -r -d '' data_file; do
        [[ ! -f "$data_file" ]] && continue
        local station_dir
        station_dir=$(dirname "$data_file")
        local station_name
        station_name=$(basename "$station_dir")
        dirs_checked=$((dirs_checked + 1))

        # Check if station already has coverart.jpg
        if [[ ! -s "$station_dir/coverart.jpg" ]]; then
            # Search candidate locations in /srv/http/data/webradio/img/ or /srv/http/data/webradios/img/
            local found_img=""
            local candidates=(
                "$DIR_WEBRADIO/img/$station_name.jpg"
                "$DIR_WEBRADIO/img/$station_name.png"
                "$DIR_WEBRADIO/img/$station_name.jpeg"
                "$DIR_DATA/webradios/img/$station_name.jpg"
                "$DIR_DATA/webradios/img/$station_name.png"
                "$DIR_DATA/webradios/img/$station_name.jpeg"
            )
            for cand in "${candidates[@]}"; do
                if [[ -s "$cand" ]]; then
                    found_img="$cand"
                    break
                fi
            done

            # If not found by exact name, try case-insensitive or pipe-encoded match from data content
            if [[ -z "$found_img" && -d "$DIR_WEBRADIO/img" ]]; then
                local stream_url
                stream_url=$(head -n 1 "$data_file" 2>/dev/null | tr -d '\r\n')
                if [[ -n "$stream_url" ]]; then
                    local pipe_encoded="${stream_url//\//|}"
                    if [[ -s "$DIR_WEBRADIO/img/$pipe_encoded.jpg" ]]; then
                        found_img="$DIR_WEBRADIO/img/$pipe_encoded.jpg"
                    fi
                fi
            fi

            # Move image into station folder
            if [[ -n "$found_img" && -f "$found_img" ]]; then
                mv -f "$found_img" "$station_dir/coverart.jpg" 2>/dev/null || true
                cp -f "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
                chmod 664 "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
                chown http:http "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
                echo "    [Moved] '$found_img' -> $station_dir/coverart.jpg"
                count=$((count + 1))
            fi
        else
            # Ensure proper permissions and cover.jpg copy
            chmod 664 "$station_dir/coverart.jpg" 2>/dev/null || true
            [[ ! -f "$station_dir/cover.jpg" ]] && cp -f "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
            chmod 664 "$station_dir/cover.jpg" 2>/dev/null || true
            chown http:http "$station_dir/coverart.jpg" "$station_dir/cover.jpg" 2>/dev/null || true
        fi
    done < <(find "$DIR_WEBRADIO" -maxdepth 5 -type f -name "data" -print0 2>/dev/null)

    # 2. Check remaining orphaned files in $DIR_WEBRADIO/img
    if [[ -d "$DIR_WEBRADIO/img" ]]; then
        while IFS= read -r -d '' orphan_img; do
            [[ ! -f "$orphan_img" ]] && continue
            local base_file
            base_file=$(basename "$orphan_img")
            local st_name="${base_file%.*}"
            local plain_name="${st_name//|/_}"

            local match_dir
            match_dir=$(find "$DIR_WEBRADIO" -maxdepth 4 -type d -iname "$st_name" | head -n 1)
            [[ -z "$match_dir" ]] && match_dir=$(find "$DIR_WEBRADIO" -maxdepth 4 -type d -iname "$plain_name" | head -n 1)

            if [[ -n "$match_dir" && -d "$match_dir" ]]; then
                mv -f "$orphan_img" "$match_dir/coverart.jpg" 2>/dev/null || true
                cp -f "$match_dir/coverart.jpg" "$match_dir/cover.jpg" 2>/dev/null || true
                chmod 664 "$match_dir/coverart.jpg" "$match_dir/cover.jpg" 2>/dev/null || true
                chown http:http "$match_dir/coverart.jpg" "$match_dir/cover.jpg" 2>/dev/null || true
                echo "    [Orphan Moved] '$base_file' -> $match_dir/coverart.jpg"
                count=$((count + 1))
            fi
        done < <(find "$DIR_WEBRADIO/img" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" \) -print0 2>/dev/null)

        # Remove img directory if empty
        rmdir "$DIR_WEBRADIO/img" 2>/dev/null || true
    fi

    # Trigger rAudio database refresh
    command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
    [[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true
    command -v mpc &>/dev/null && mpc update Webradio &>/dev/null || true

    echo "==> Successfully moved $count images to station folders with data file."
    echo "{\"success\":true,\"moved\":$count,\"checkedDirs\":$dirs_checked}"
}

# 6. Fix rAudio upstream PHP 8 Warning: Undefined variable $MODE in /srv/http/library.php on line 484
cmd_fix_library_php() {
    local target="/srv/http/library.php"
    if [[ ! -f "$target" ]]; then
        echo "==> Note: $target not present on host (simulation or remote container environment)."
        return 0
    fi

    echo "==> Inspecting $target for undefined variable \$MODE warning..."
    [[ ! -f "${target}.bak" ]] && cp -f "$target" "${target}.bak" 2>/dev/null || true

    local patched=0

    # 1. Add $MODE and $GMODE to global scope inside function htmlRadio()
    if grep -q "function htmlRadio()" "$target"; then
        if grep -A 2 "function htmlRadio()" "$target" | grep -q 'global .*subdirs;' && ! grep -A 2 "function htmlRadio()" "$target" | grep -q 'MODE'; then
            sed -i '/function htmlRadio()/,/subdirs;/ s/subdirs;/subdirs, $MODE, $GMODE;\n\t$MODE = $MODE ?? $GMODE ?? "webradio";/' "$target"
            echo "    [Fixed] Added \$MODE, \$GMODE to htmlRadio() global declaration in $target"
            patched=1
        fi
    fi

    # 2. Safeguard line 484 directly: data-mode="'.$MODE.'"
    if grep -q 'data-mode=".*MODE' "$target"; then
        sed -i 's/data-mode=".*\$MODE.*"/data-mode="\x27.( $MODE ?? $GMODE ?? "webradio" ).\x27"/g' "$target"
        echo "    [Fixed] Safeguarded line 484 data-mode in $target"
        patched=1
    fi

    if [[ $patched -eq 1 ]]; then
        chmod 644 "$target" 2>/dev/null || true
        chown http:http "$target" 2>/dev/null || true
        echo "==> Successfully patched $target to eliminate undefined \$MODE warning."
    else
        echo "==> $target already patched or no match needed."
    fi

    # Also ensure the standalone web portal directory index is properly populated
    cmd_fix_web_portal
}

# 7. Ensure standalone portal directory index exists (solves Nginx 403 directory index forbidden)
cmd_fix_web_portal() {
    local web_dir="$DIR_RADIOBROWSER_WEB"
    mkdir -p "$web_dir"

    # Deploy index.html if missing
    if [[ ! -s "$web_dir/index.html" ]]; then
        if [[ -f "/addon/index.html" ]]; then
            cp -f "/addon/index.html" "$web_dir/index.html" 2>/dev/null || true
        elif [[ -f "$(dirname "$0")/../addon/index.html" ]]; then
            cp -f "$(dirname "$0")/../addon/index.html" "$web_dir/index.html" 2>/dev/null || true
        fi
    fi

    # Always deploy index.php so Nginx 'index index.php index.html' never throws 403 Forbidden
    if [[ ! -s "$web_dir/index.php" ]]; then
        cat <<'PORTAL_PHP' > "$web_dir/index.php"
<?php
/**
 * rAudio Radio Browser Standalone Portal Entry Point
 * Solves Nginx "directory index of /srv/http/radiobrowser/ is forbidden"
 * Handles /radiobrowser/ and /radiobrowser/?q=...
 */
header('Content-Type: text/html; charset=utf-8');
$htmlFile = __DIR__ . '/index.html';
if (file_exists($htmlFile)) {
    readfile($htmlFile);
    exit;
}
$q = isset($_GET['q']) ? htmlspecialchars($_GET['q'], ENT_QUOTES, 'UTF-8') : '';
?>
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Radio Browser</title></head>
<body style="background:#0c0a09;color:#fff;font-family:sans-serif;padding:30px;text-align:center;">
    <h2>📻 rAudio Radio Browser</h2>
    <p>Portal is active. <a href="/app/radiobrowser.php?action=search<?= $q ? '&name=' . urlencode($q) : '' ?>" style="color:#f59e0b;">Search API</a></p>
    <p><a href="/" style="color:#a8a29e;">← Return to rAudio</a></p>
</body>
</html>
PORTAL_PHP
    fi

    chmod 755 "$web_dir" 2>/dev/null || true
    chmod 644 "$web_dir"/* 2>/dev/null || true
    chown -R http:http "$web_dir" 2>/dev/null || true
    echo "==> Ensured $web_dir has index.php & index.html with http:http permissions."
}

# 8. Pre-seed Hi-Fi reference stations in the new Directory/data format
cmd_presets() {
    cmd_fix_library_php
    cmd_fix_web_portal

    echo "==> Creating rAudio Radio Browser library hierarchy in $DIR_RB_ROOT..."
    mkdir -p "$DIR_RB_ROOT/Lounge & Ambient"

    if [[ -d "/mnt/MPD/Webradio" ]]; then
        mkdir -p "$DIR_MPD_WEBRADIO/Lounge & Ambient" 2>/dev/null || true
    fi

    echo "==> Seeding curated Hi-Fi stations in <Directory>/data format with coverart.jpg..."
    cmd_save "SomaFM Groove Salad" "https://ice2.somafm.com/groovesalad-256-mp3" "https://somafm.com/img3/groovesalad-120.png" "Lounge & Ambient"
    cmd_save "SomaFM Drone Zone" "https://ice2.somafm.com/dronezone-256-mp3" "https://somafm.com/img3/dronezone-120.png" "Lounge & Ambient"

    chmod -R 775 "$DIR_RB_ROOT" 2>/dev/null || true
    chown -R http:http "$DIR_RB_ROOT" 2>/dev/null || true

    # Redis notify
    command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
    command -v redis-cli &>/dev/null && redis-cli publish notify '{"title":"Radio Browser","text":"Web Radio stations updated in <Directory>/data format"}' &>/dev/null || true
    [[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true
    command -v mpc &>/dev/null && mpc update Webradio &>/dev/null || true

    echo "==> Curated stations seeded into $DIR_RB_ROOT in Directory/data format"
}

case "$1" in
    search)       shift; cmd_search "$@" ;;
    play)         cmd_play "$2" ;;
    save)         cmd_save "$2" "$3" "$4" "$5" ;;
    move-images)  cmd_move_images ;;
    convert)      cmd_move_images ;;
    fix-php)      cmd_fix_library_php ;;
    fix-web)      cmd_fix_web_portal ;;
    metadata)     cmd_metadata "$2" ;;
    presets)      cmd_presets ;;
    *)
        echo "rAudio Radio Browser Bash Engine"
        echo "Usage: $0 search [name] [tag/genre] [countrycode] [codec] [bitrate] [limit]"
        echo "       $0 search --name '...' --genre '...' --country '...'"
        echo "       $0 {play|save|move-images|convert|fix-php|fix-web|metadata|presets} [args...]"
        exit 1
        ;;
esac
ENGINE_EOF

chmod 755 "$DIR_BASH/radiobrowser.sh"
chown http:http "$DIR_BASH/radiobrowser.sh" 2>/dev/null || true

# patch undefined $MODE in library.php
bash "$DIR_BASH/radiobrowser.sh" fix-php 2>/dev/null || true

# 3. Deploy Web API and Standalone Portal
echo "==> [3/7] Installing Web API & standalone UI at $DIR_APP/radiobrowser.php..."
cat <<'PHP_EOF' > "$DIR_APP/radiobrowser.php"
<?php
/**
 * rAudio Radio Browser PHP Web API & UI Bridge
 * Target Path on rAudio: /srv/http/app/radiobrowser.php
 * Handles search queries, MPD playback, and saving stations in <Directory>/data format
 */

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$USER_AGENT = 'rAudio-RadioBrowser-Addon/1.0.0 ( https://github.com/kan-ibal/raudio-radiobrowser)';

// If accessed with no action or ?ui=1, serve standalone UI
if (empty($action) || $action === 'ui' || isset($_GET['ui'])) {
    if (file_exists('/srv/http/radiobrowser/index.html')) {
        header('Content-Type: text/html; charset=utf-8');
        include '/srv/http/radiobrowser/index.html';
        exit;
    }
}

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

function fetch_rb($endpoint, $params = []) {
    global $USER_AGENT;
    $mirrors = [
        'https://de1.api.radio-browser.info',
        'https://nl1.api.radio-browser.info',
        'https://at1.api.radio-browser.info',
        'https://all.api.radio-browser.info'
    ];
    $query = !empty($params) ? '?' . http_build_query($params) : '';
    foreach ($mirrors as $mirror) {
        $ch = curl_init($mirror . $endpoint . $query);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 6);
        curl_setopt($ch, CURLOPT_USERAGENT, $USER_AGENT);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code === 200 && $res) {
            return json_decode($res, true);
        }
    }
    return null;
}

function normalize_station_icon($icon) {
    static $empty_icon = "data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='44' height='44' viewBox='0 0 24 24'%3E%3C/svg%3E";
    if (empty($icon) || !is_string($icon)) {
        return $empty_icon;
    }
    $trimmed = trim($icon);
    // In case of station with no icon and receiving "data:image/svg+xml,<svg xmlns=" or invalid/truncated SVG
    if ($trimmed === '' || 
        strpos($trimmed, 'data:image/svg+xml,<svg xmlns=') === 0 || 
        strpos($trimmed, 'data:image/svg+xml,<svg') === 0 ||
        $trimmed === 'data:image/svg+xml,<svg xmlns=') {
        return $empty_icon;
    }
    return $trimmed;
}

switch ($action) {
    case 'search':
        $req = array_merge($_GET, $_POST);
        $params = [];

        // 1. Station Name
        if (!empty($req['name'])) {
            $params['name'] = trim($req['name']);
        }

        // 2. Tag / Genre search field (supports 'tag', 'genre', 'tags')
        $tag = trim($req['tag'] ?? $req['genre'] ?? $req['tags'] ?? '');
        if (!empty($tag)) {
            $params['tag'] = $tag;
        }

        // 3. Country Code search field (supports 'countrycode', 'country_code', 'country')
        $cc = trim($req['countrycode'] ?? $req['country_code'] ?? '');
        if (empty($cc) && !empty($req['country'])) {
            $c = trim($req['country']);
            if (strlen($c) === 2) {
                $cc = strtoupper($c);
            } else {
                $params['country'] = $c;
            }
        }
        if (!empty($cc)) {
            $params['countrycode'] = strtoupper($cc);
        }

        // 4. Codec filter
        if (!empty($req['codec']) && strtoupper($req['codec']) !== 'ALL') {
            $params['codec'] = trim($req['codec']);
        }

        // 5. Bitrate filter
        $bitrate = (int)($req['bitrate'] ?? $req['bitrateMin'] ?? 0);
        if ($bitrate > 0) {
            $params['bitrateMin'] = $bitrate;
        }

        // 6. Ordering & Pagination
        $params['order'] = !empty($req['order']) ? trim($req['order']) : 'votes';
        $params['reverse'] = isset($req['reverse']) ? trim($req['reverse']) : 'true';
        $params['hidebroken'] = isset($req['hidebroken']) ? trim($req['hidebroken']) : 'true';
        $params['limit'] = !empty($req['limit']) ? (int)$req['limit'] : 30;

        $res = fetch_rb('/json/stations/search', $params);
        if (is_array($res)) {
            foreach ($res as &$st) {
                $st['favicon'] = normalize_station_icon($st['favicon'] ?? '');
            }
            unset($st);
        }
        echo json_encode($res ?: []);
        break;

    case 'play':
        $uuid = $_POST['uuid'] ?? $_GET['uuid'] ?? '';
        $url = $_POST['url'] ?? $_GET['url'] ?? '';
        if ($uuid && !$url) {
            $resolved = fetch_rb('/json/url/' . urlencode($uuid));
            if (!empty($resolved['url'])) {
                $url = $resolved['url'];
            }
        }
        if (!$url) {
            echo json_encode(['success' => false, 'error' => 'Could not resolve stream URL']);
            exit;
        }
        exec('/srv/http/bash/radiobrowser.sh play ' . escapeshellarg($url), $output, $status);
        echo json_encode(['success' => $status === 0, 'url' => $url, 'output' => implode("\n", $output)]);
        break;

    case 'save_webradio':
        $name = trim($_POST['name'] ?? $_GET['name'] ?? 'Radio Station');
        $url = trim($_POST['url'] ?? $_GET['url'] ?? '');
        $icon = normalize_station_icon($_POST['icon'] ?? $_GET['icon'] ?? '');
        $subfolder = trim($_POST['subfolder'] ?? $_GET['subfolder'] ?? '');

        if (!$name || !$url) {
            echo json_encode(['success' => false, 'error' => 'Missing station name or URL']);
            exit;
        }

        $cmd = '/srv/http/bash/radiobrowser.sh save ' .
            escapeshellarg($name) . ' ' .
            escapeshellarg($url) . ' ' .
            escapeshellarg($icon) . ' ' .
            escapeshellarg($subfolder);

        exec($cmd, $out, $st);
        echo json_encode(['success' => $st === 0, 'output' => implode("\n", $out)]);
        break;

    case 'convert':
        exec('/srv/http/bash/radiobrowser.sh convert', $output, $status);
        echo json_encode(['success' => $status === 0, 'output' => implode("\n", $output)]);
        break;

    case 'presets':
        exec('/srv/http/bash/radiobrowser.sh presets', $output, $status);
        echo json_encode(['success' => $status === 0, 'output' => implode("\n", $output)]);
        break;

    default:
        echo json_encode(['error' => 'Unknown action', 'available' => ['search', 'play', 'save_webradio', 'convert', 'presets', 'ui']]);
        break;
}
PHP_EOF

chmod 755 "$DIR_APP/radiobrowser.php"
chown http:http "$DIR_APP/radiobrowser.php" 2>/dev/null || true

# Deploy Standalone WebUI Portal at /srv/http/radiobrowser/ (index.html & index.php)
# Prevents Nginx 403: directory index of /srv/http/radiobrowser/ is forbidden
echo "==> [3/7] Deploying Standalone Portal at $DIR_RADIOBROWSER_WEB (index.html & index.php)..."
mkdir -p "$DIR_RADIOBROWSER_WEB"

cat <<'WEBUI_EOF' > "$DIR_RADIOBROWSER_WEB/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>rAudio Radio Browser · Hi-Fi Station Manager</title>
    <style>
        :root {
            --bg: #0c0a09;
            --surface: #1c1917;
            --surface-hover: #292524;
            --border: #44403c;
            --primary: #f59e0b;
            --primary-hover: #d97706;
            --text: #f5f5f4;
            --text-muted: #a8a29e;
            --success: #10b981;
            --accent: #06b6d4;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.5;
            padding: 16px;
        }
        .container { max-width: 1000px; margin: 0 auto; }
        header {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 12px;
            padding-bottom: 16px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 20px;
        }
        .header-title h1 { font-size: 1.4rem; font-weight: 700; color: #fff; }
        .header-title p { font-size: 0.85rem; color: var(--text-muted); }
        .nav-btn {
            background: var(--surface);
            color: var(--text);
            border: 1px solid var(--border);
            padding: 8px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            cursor: pointer;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }
        .nav-btn:hover { background: var(--surface-hover); }
        .hero-banner {
            background: linear-gradient(135deg, rgba(245,158,11,0.12), rgba(6,182,212,0.06));
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 16px;
            margin-bottom: 20px;
            font-size: 0.85rem;
        }
        .hero-banner strong { color: var(--primary); }
        .search-panel {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 16px;
            margin-bottom: 24px;
        }
        .search-row {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 12px;
        }
        .search-input {
            flex: 2;
            min-width: 200px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 10px 14px;
            color: #fff;
            font-size: 0.9rem;
        }
        .search-select {
            flex: 1;
            min-width: 140px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 10px 14px;
            color: #fff;
            font-size: 0.9rem;
        }
        .btn-primary {
            background: var(--primary);
            color: #000;
            border: none;
            padding: 10px 18px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }
        .btn-primary:hover { background: var(--primary-hover); }
        .curated-tags {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 10px;
        }
        .curated-btn {
            background: rgba(255,255,255,0.05);
            border: 1px solid var(--border);
            border-radius: 20px;
            padding: 4px 12px;
            font-size: 0.75rem;
            color: var(--text-muted);
            cursor: pointer;
        }
        .curated-btn:hover { background: rgba(255,255,255,0.1); color: #fff; }
        .station-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 16px;
        }
        .station-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 14px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            transition: transform 0.15s, border-color 0.15s;
        }
        .station-card:hover {
            border-color: var(--primary);
            transform: translateY(-2px);
        }
        .station-header {
            display: flex;
            gap: 12px;
            align-items: center;
        }
        .station-icon {
            width: 44px;
            height: 44px;
            border-radius: 8px;
            background: #262626;
            object-fit: cover;
            flex-shrink: 0;
        }
        .station-title {
            font-weight: 600;
            font-size: 0.95rem;
            color: #fff;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .station-tags {
            font-size: 0.75rem;
            color: var(--text-muted);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .badges {
            display: flex;
            gap: 6px;
            flex-wrap: wrap;
            margin-top: 2px;
        }
        .badge {
            background: rgba(255,255,255,0.06);
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.7rem;
            font-family: monospace;
        }
        .badge-lossless {
            background: rgba(16, 185, 129, 0.2);
            color: #34d399;
            font-weight: 600;
        }
        .actions {
            display: flex;
            gap: 8px;
            margin-top: auto;
            padding-top: 8px;
            border-top: 1px solid rgba(255,255,255,0.05);
        }
        .btn-action {
            flex: 1;
            background: var(--surface-hover);
            border: 1px solid var(--border);
            color: #fff;
            padding: 8px 10px;
            border-radius: 6px;
            font-size: 0.75rem;
            font-weight: 500;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 4px;
        }
        .btn-action:hover { background: rgba(255,255,255,0.15); }
        .btn-play { background: #059669; border-color: #059669; }
        .btn-play:hover { background: #10b981; }
        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #18181b;
            border: 1px solid var(--primary);
            padding: 12px 18px;
            border-radius: 8px;
            color: #fff;
            font-size: 0.85rem;
            display: none;
            z-index: 1000;
            box-shadow: 0 4px 12px rgba(0,0,0,0.5);
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="header-title">
                <h1>Radio-Browser.info · rAudio</h1>
                <p>Search over 50,000 community stations and add directly to rAudio Web Radio</p>
            </div>
            <div style="display: flex; gap: 8px;">
                <a href="/" class="nav-btn">
                    ← Back to rAudio Player
                </a>
            </div>
        </header>

        <div class="hero-banner">
            <div><strong>rAudio Web Radio Integration Active (Format: /srv/http/data/webradio/&lt;Directory&gt;/data)</strong></div>
            <div style="margin-top: 4px; color: var(--text-muted);">
                In rAudio WebUI, open: <strong>Library &rarr; Web Radio &rarr; Radio Browser</strong>.
                Use the new search field right inside Web Radio, or click "Add to Web Radio" below.
                Each station is saved as <code>&lt;Station Directory&gt;/data</code> containing the direct stream hyperlink and cover art!
            </div>
        </div>

        <div class="search-panel">
            <div class="search-row">
                <input type="text" id="searchInput" class="search-input" placeholder="Station name..." value="Paradise" style="flex: 2;">
                <input type="text" id="tagInput" class="search-input" placeholder="Tag / Genre (e.g. jazz, ambient)..." style="flex: 1.5;">
                <input type="text" id="countryInput" class="search-input" placeholder="Country (US, PL, DE)..." maxlength="2" style="flex: 1; max-width: 140px; text-transform: uppercase;">
                <select id="codecSelect" class="search-select">
                    <option value="">All Codecs</option>
                    <option value="FLAC">FLAC (Lossless)</option>
                    <option value="MP3">MP3</option>
                    <option value="AAC">AAC / AAC+</option>
                </select>
                <select id="bitrateSelect" class="search-select">
                    <option value="0">Any Bitrate</option>
                    <option value="320">320 kbps (Audiophile)</option>
                    <option value="256">256 kbps</option>
                    <option value="192">192 kbps</option>
                    <option value="128">128 kbps</option>
                </select>
                <button class="btn-primary" onclick="doSearch()">
                    🔍 Search
                </button>
            </div>
            <div class="curated-tags">
                <span style="font-size: 0.75rem; color: var(--text-muted); align-self: center;">Quick filters:</span>
                <button class="curated-btn" onclick="quickFilter('', 'flac', '', 'FLAC', 0)">FLAC Lossless</button>
                <button class="curated-btn" onclick="quickFilter('Linn', 'classical', 'GB', 'MP3', 320)">Linn Classical (GB)</button>
                <button class="curated-btn" onclick="quickFilter('SomaFM', 'ambient', 'US', '', 256)">SomaFM Ambient (US)</button>
                <button class="curated-btn" onclick="quickFilter('', 'jazz', 'PL', '', 192)">Polish Jazz (PL)</button>
                <button class="curated-btn" onclick="quickFilter('', 'jazz', 'US', '', 192)">US Jazz (US)</button>
                <button class="curated-btn" onclick="quickFilter('', 'classical', 'DE', '', 192)">German Classical (DE)</button>
                <button class="curated-btn" onclick="seedPresets()">Reload Curated Presets</button>
            </div>
        </div>

        <div id="resultsGrid" class="station-grid">
            <div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 40px;">
                Loading stations...
            </div>
        </div>
    </div>

    <div id="toast" class="toast"></div>

    <script>
        const API_PATH = '/app/radiobrowser.php';

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.innerText = msg;
            t.style.display = 'block';
            setTimeout(() => { t.style.display = 'none'; }, 3500);
        }

        async function doSearch() {
            const name = document.getElementById('searchInput').value.trim();
            const tag = document.getElementById('tagInput') ? document.getElementById('tagInput').value.trim() : '';
            const country = document.getElementById('countryInput') ? document.getElementById('countryInput').value.trim().toUpperCase() : '';
            const codec = document.getElementById('codecSelect').value;
            const bitrate = document.getElementById('bitrateSelect').value;
            const grid = document.getElementById('resultsGrid');
            grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 40px;">Searching radio-browser mirrors...</div>';

            try {
                const params = new URLSearchParams({
                    action: 'search',
                    order: 'votes',
                    reverse: 'true',
                    limit: '30',
                    hidebroken: 'true'
                });
                if (name) params.append('name', name);
                if (tag) params.append('tag', tag);
                if (country) params.append('countrycode', country);
                if (codec && codec !== 'ALL') params.append('codec', codec);
                if (bitrate && bitrate !== '0') params.append('bitrateMin', bitrate);

                const res = await fetch(API_PATH + '?' + params.toString());
                const stations = await res.json();
                renderStations(stations);
            } catch (e) {
                grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: #ef4444; padding: 40px;">Failed to query stations. Check network connection.</div>';
            }
        }

        const EMPTY_ICON = "data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='44' height='44' viewBox='0 0 24 24'%3E%3C/svg%3E";

        function getStationIcon(fav) {
            if (!fav || typeof fav !== 'string') return EMPTY_ICON;
            const trimmed = fav.trim();
            if (!trimmed || 
                trimmed === 'data:image/svg+xml,<svg xmlns=' || 
                trimmed.startsWith('data:image/svg+xml,<svg xmlns=') || 
                trimmed.startsWith('data:image/svg+xml,<svg')) {
                return EMPTY_ICON;
            }
            return trimmed;
        }

        function renderStations(stations) {
            const grid = document.getElementById('resultsGrid');
            if (!stations || stations.length === 0) {
                grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 40px;">No stations found. Try broadening your query.</div>';
                return;
            }

            grid.innerHTML = stations.map(s => {
                const isLossless = (s.codec || '').toUpperCase() === 'FLAC' || (s.bitrate || 0) >= 900;
                const icon = getStationIcon(s.favicon);
                const subfolder = isLossless ? 'FLAC Lossless' : 'Audiophile 320k';
                return `
                    <div class="station-card">
                        <div class="station-header">
                            <img src="${icon}" class="station-icon" onerror="this.src='${EMPTY_ICON}'; this.onerror=null;">
                            <div style="flex: 1; min-width: 0;">
                                <div class="station-title" title="${s.name}">${s.name}</div>
                                <div class="station-tags">${s.tags || s.country || 'Global Stream'}</div>
                                <div class="badges">
                                    <span class="badge ${isLossless ? 'badge-lossless' : ''}">${s.codec || 'MP3'}</span>
                                    <span class="badge">${s.bitrate ? s.bitrate + ' kbps' : 'VBR'}</span>
                                    ${s.countrycode ? `<span class="badge">${s.countrycode}</span>` : ''}
                                </div>
                            </div>
                        </div>
                        <div class="actions">
                            <button class="btn-action btn-play" onclick="playStation('${s.stationuuid}', '${encodeURIComponent(s.url_resolved || s.url)}')">▶ Play</button>
                            <button class="btn-action" onclick="saveToRaudio('${encodeURIComponent(s.name)}', '${encodeURIComponent(s.url_resolved || s.url)}', '${encodeURIComponent(icon)}', '${subfolder}')">➕ Add to Web Radio</button>
                        </div>
                    </div>
                `;
            }).join('');
        }

        async function playStation(uuid, encUrl) {
            showToast('Starting stream on rAudio MPD...');
            try {
                const fd = new FormData();
                fd.append('action', 'play');
                fd.append('uuid', uuid);
                fd.append('url', decodeURIComponent(encUrl));
                const res = await fetch(API_PATH, { method: 'POST', body: fd });
                const json = await res.json();
                if (json.success) {
                    showToast('Playing on rAudio!');
                } else {
                    showToast('Stream dispatched to MPD');
                }
            } catch (e) {
                showToast('Error sending playback command');
            }
        }

        async function saveToRaudio(encName, encUrl, encIcon, subfolder) {
            showToast('Saving to rAudio /srv/http/data/webradio (' + subfolder + ')...');
            try {
                const fd = new FormData();
                fd.append('action', 'save_webradio');
                fd.append('name', decodeURIComponent(encName));
                fd.append('url', decodeURIComponent(encUrl));
                fd.append('icon', decodeURIComponent(encIcon));
                fd.append('subfolder', subfolder);
                const res = await fetch(API_PATH, { method: 'POST', body: fd });
                const json = await res.json();
                if (json.success) {
                    showToast('Saved to rAudio: ' + subfolder + '/' + decodeURIComponent(encName) + '/data');
                } else {
                    showToast('Failed to save: ' + (json.error || 'Unknown error'));
                }
            } catch (e) {
                showToast('Error saving station');
            }
        }

        async function seedPresets() {
            showToast('Seeding curated audiophile presets in Directory/data format...');
            try {
                const res = await fetch(API_PATH + '?action=presets');
                const json = await res.json();
                showToast('Curated presets reloaded into rAudio Web Radio!');
            } catch (e) {
                showToast('Error running presets command');
            }
        }

        function quickFilter(name, tag, country, codec, bitrate) {
            document.getElementById('searchInput').value = name || '';
            if (document.getElementById('tagInput')) document.getElementById('tagInput').value = tag || '';
            if (document.getElementById('countryInput')) document.getElementById('countryInput').value = country || '';
            document.getElementById('codecSelect').value = codec || '';
            document.getElementById('bitrateSelect').value = bitrate || '0';
            doSearch();
        }

        // Initial search on load, respecting query params "?q=...", "?tag=...", "?genre=...", "?country=..."
        window.addEventListener('DOMContentLoaded', () => {
            const params = new URLSearchParams(window.location.search);
            const query = params.get('q') || params.get('name');
            const tag = params.get('tag') || params.get('genre');
            const country = params.get('countrycode') || params.get('country_code') || params.get('country');

            if (query) document.getElementById('searchInput').value = query;
            if (tag && document.getElementById('tagInput')) document.getElementById('tagInput').value = tag;
            if (country && document.getElementById('countryInput')) document.getElementById('countryInput').value = country.toUpperCase();

            doSearch();
        });
    </script>
</body>
</html>
WEBUI_EOF

cat <<'PORTAL_PHP_EOF' > "$DIR_RADIOBROWSER_WEB/index.php"
<?php
/**
 * rAudio Radio Browser - Standalone WebUI Portal Index
 * Resolves directory requests to /radiobrowser/ and /radiobrowser/?q=...
 * Target: /srv/http/radiobrowser/index.php
 * Repository: https://github.com/kan-ibal/raudio-radiobrowser
 * Version: 1.0.0
 */

header('Content-Type: text/html; charset=utf-8');

$htmlFile = __DIR__ . '/index.html';
if (file_exists($htmlFile)) {
    readfile($htmlFile);
    exit;
}

// Fallback if index.html is temporarily unreadable
$q = isset($_GET['q']) ? htmlspecialchars($_GET['q'], ENT_QUOTES, 'UTF-8') : '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>rAudio Radio Browser</title>
    <style>
        body { background: #0c0a09; color: #f5f5f4; font-family: -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .card { background: #1c1917; border: 1px solid #44403c; padding: 24px; border-radius: 12px; max-width: 480px; text-align: center; }
        a { color: #f59e0b; }
    </style>
</head>
<body>
    <div class="card">
        <h2>📻 rAudio Radio Browser</h2>
        <p>Portal is active. <a href="/app/radiobrowser.php?action=search<?= $q ? '&name=' . urlencode($q) : '' ?>">Direct API Search</a></p>
        <p><a href="/">Return to rAudio Playback</a></p>
    </div>
</body>
</html>
PORTAL_PHP_EOF

chmod 755 "$DIR_RADIOBROWSER_WEB"
chmod 644 "$DIR_RADIOBROWSER_WEB/index.html" "$DIR_RADIOBROWSER_WEB/index.php" 2>/dev/null || true
chown -R http:http "$DIR_RADIOBROWSER_WEB" 2>/dev/null || true

# 4. Deploy JavaScript Hook for [Library] -> [Web Radio]
echo "==> [4/7] Injecting Search Field and Link into [Library] -> [Web Radio]..."
cat <<'HOOK_EOF' > "$DIR_ASSETS_JS/radiobrowser-webradio-hook.js"
/**
 * rAudio Radio Browser - Web Radio Library Hook
 * Injects a Search Field and direct Link to Radio Browser into [Library] -> [Web Radio]
 * Target Path: /srv/http/assets/js/radiobrowser-webradio-hook.js
 * Repository: https://github.com/kan-ibal/raudio-radiobrowser
 * Version: 1.0.0
 */
(function () {
    'use strict';

    const RB_PORTAL_URL = '/radiobrowser/';
    const RB_API_URL = '/app/radiobrowser.php';

    // Comprehensive detector for rAudio [Library] -> [Web Radio] view
    function isWebRadioView() {
        // 1. Check if #page-library is currently active and visible
        const pageLibrary = document.getElementById('page-library') || document.querySelector('.page-library');
        if (pageLibrary) {
            const style = window.getComputedStyle(pageLibrary);
            if (pageLibrary.classList.contains('hide') || style.display === 'none' || style.visibility === 'hidden') {
                return false;
            }
        }

        // 2. Check rAudio global state object (G, C, or UI)
        if (window.G) {
            if (window.G.mode === 'webradio' || window.G.mode === 'webradios') return true;
            if (window.G.status && (window.G.status.mode === 'webradio' || window.G.status.mode === 'webradios')) return true;
            if (typeof window.G.path === 'string' && /webradio/i.test(window.G.path)) return true;
            if (typeof window.G.librarypath === 'string' && /webradio/i.test(window.G.librarypath)) return true;
        }
        if (window.C && (window.C.mode === 'webradio' || window.C.mode === 'webradios')) return true;

        // 3. Check URL hash or query params (e.g. #webradio or ?mode=webradio)
        const hash = (window.location.hash || '').toLowerCase();
        const search = (window.location.search || '').toLowerCase();
        if (hash.includes('webradio') || search.includes('webradio')) return true;

        // 4. Check Breadcrumbs / Path bar in rAudio WebUI (#lib-path, #lib-breadcrumbs, .lipath)
        const pathEl = document.getElementById('lib-path') || 
                       document.getElementById('lib-breadcrumbs') || 
                       document.querySelector('.lipath') ||
                       document.getElementById('lib-title');
        if (pathEl) {
            const text = (pathEl.innerText || pathEl.textContent || '').toUpperCase();
            if (text.includes('WEBRADIO') || text.includes('WEB RADIO') || text.includes('RADIO BROWSER')) {
                return true;
            }
            // Check data attributes in breadcrumb links
            const hasWebRadioData = pathEl.querySelector('[data-path*="webradio" i], [data-dir*="webradio" i], [data-mode="webradio"]');
            if (hasWebRadioData) return true;
        }

        // 5. Check if mode list has WebRadio active or if current listing contains WebRadio stations
        const activeMode = document.querySelector('#mode-webradio.active, [data-mode="webradio"].active, .tab-webradio.active, .lib-mode.active[data-mode="webradio"]');
        if (activeMode) return true;

        // 6. Check items inside #lib-list
        const libList = document.getElementById('lib-list');
        if (libList) {
            const webradioItem = libList.querySelector('li[data-path*="webradio" i], li[data-mode="webradio"], [data-path*="Radio Browser" i]');
            if (webradioItem) return true;
        }

        // 7. Check simulation / testbench container
        if (document.getElementById('webradio-library-host') || document.querySelector('.webradio-page-container')) {
            return true;
        }

        return false;
    }

    // Finds the optimal injection mount point
    // Priority: below the $htmlbar = buttonSet( [ 'library', 'playback', 'playlist' ] ); htmlEnd( $htmlbar ); bar (#bar-bottom)
    function getMountPoint() {
        const barBottom = document.getElementById('bar-bottom') || document.querySelector('.bar-bottom');
        const libList = document.getElementById('lib-list');
        const libContent = document.getElementById('lib-content');
        const libPath = document.getElementById('lib-path') || document.getElementById('lib-breadcrumbs');
        const pageLibrary = document.getElementById('page-library') || document.getElementById('webradio-library-host');

        // Optimal 1: Right below the $htmlbar = buttonSet( [ 'library', 'playback', 'playlist' ] ); htmlEnd( $htmlbar ); bar (#bar-bottom)
        if (barBottom && barBottom.parentNode) {
            return { parent: barBottom.parentNode, before: barBottom.nextSibling, isBarBottom: true, anchor: barBottom };
        }

        // Optimal 2: As preceding sibling right before #lib-list
        if (libList && libList.parentNode) {
            return { parent: libList.parentNode, before: libList, isBarBottom: false, anchor: libList };
        }

        // Optimal 3: Inside #lib-content as first child
        if (libContent) {
            return { parent: libContent, before: libContent.firstChild, isBarBottom: false, anchor: libContent };
        }

        // Optimal 4: Right after #lib-path (as following sibling, NEVER as child)
        if (libPath && libPath.parentNode) {
            return { parent: libPath.parentNode, before: libPath.nextSibling, isBarBottom: false, anchor: libPath };
        }

        // Fallback: inside page-library or body
        if (pageLibrary) {
            return { parent: pageLibrary, before: null, isBarBottom: false, anchor: pageLibrary };
        }

        return { parent: document.body, before: null, isBarBottom: false, anchor: document.body };
    }

    // Injects the search bar and link into Web Radio header
    function injectSearchBar() {
        const shouldShow = isWebRadioView();
        let container = document.getElementById('radiobrowser-search-bar');

        if (!shouldShow) {
            if (container) container.style.display = 'none';
            return;
        }

        // If container already exists and is attached to DOM, ensure it is visible
        if (container && document.body.contains(container)) {
            container.style.display = 'flex';
            return;
        }

        // If it was detached or doesn't exist, create and mount
        const mount = getMountPoint();
        if (!mount || !mount.parent) return;

        if (!container) {
            container = document.createElement('div');
            container.id = 'radiobrowser-search-bar';
            container.innerHTML = `
                <style>
                    #radiobrowser-search-bar {
                        display: flex;
                        flex-direction: column;
                        gap: 10px;
                        padding: 12px 16px;
                        margin: 10px 14px 14px 14px;
                        background: linear-gradient(135deg, rgba(245, 158, 11, 0.14) 0%, rgba(28, 25, 23, 0.95) 100%);
                        border: 1px solid rgba(245, 158, 11, 0.4);
                        border-radius: 14px;
                        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
                        z-index: 99;
                        position: relative;
                        clear: both;
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    }
                    #radiobrowser-search-bar.fixed-bar-dock {
                        position: fixed;
                        bottom: 46px;
                        left: 12px;
                        right: 12px;
                        max-width: 960px;
                        margin: 0 auto;
                        z-index: 1000;
                    }
                    .rb-top-row {
                        display: flex;
                        flex-wrap: wrap;
                        align-items: center;
                        justify-content: space-between;
                        gap: 10px;
                    }
                    .rb-search-left {
                        display: flex;
                        align-items: center;
                        gap: 8px;
                        flex: 1;
                        min-width: 260px;
                    }
                    .rb-badge {
                        background: #f59e0b;
                        color: #000;
                        font-size: 10px;
                        font-weight: 800;
                        padding: 2px 6px;
                        border-radius: 4px;
                        text-transform: uppercase;
                        letter-spacing: 0.5px;
                        white-space: nowrap;
                    }
                    .rb-input-wrap {
                        display: flex;
                        align-items: center;
                        flex: 1;
                        background: #171513;
                        border: 1px solid #44403c;
                        border-radius: 8px;
                        padding: 0 10px;
                        transition: border-color 0.2s, box-shadow 0.2s;
                    }
                    .rb-input-wrap:focus-within {
                        border-color: #f59e0b;
                        box-shadow: 0 0 0 2px rgba(245, 158, 11, 0.2);
                    }
                    .rb-input-field {
                        flex: 1;
                        background: transparent;
                        border: none;
                        padding: 9px 8px;
                        color: #f5f5f4;
                        font-size: 13px;
                        outline: none;
                    }
                    .rb-input-field::placeholder {
                        color: #78716c;
                    }
                    .rb-btn {
                        padding: 8px 14px;
                        border-radius: 8px;
                        font-size: 12px;
                        font-weight: 600;
                        cursor: pointer;
                        display: inline-flex;
                        align-items: center;
                        gap: 6px;
                        text-decoration: none;
                        border: none;
                        transition: all 0.2s;
                        white-space: nowrap;
                    }
                    .rb-btn-search {
                        background: #f59e0b;
                        color: #0c0a09;
                    }
                    .rb-btn-search:hover {
                        background: #d97706;
                        color: #000;
                    }
                    .rb-btn-portal {
                        background: #292524;
                        color: #f5f5f4;
                        border: 1px solid #44403c;
                    }
                    .rb-btn-portal:hover {
                        background: #44403c;
                        color: #fff;
                        border-color: #f59e0b;
                    }
                    .rb-tags-row {
                        display: flex;
                        flex-wrap: wrap;
                        align-items: center;
                        gap: 6px;
                        padding-top: 4px;
                        border-top: 1px dashed rgba(245, 158, 11, 0.2);
                    }
                    .rb-tag-label {
                        font-size: 11px;
                        color: #a8a29e;
                        font-weight: 500;
                        margin-right: 2px;
                    }
                    .rb-tag-pill {
                        background: #262320;
                        border: 1px solid #3c3732;
                        color: #d6d3d1;
                        padding: 3px 8px;
                        border-radius: 12px;
                        font-size: 11px;
                        cursor: pointer;
                        transition: all 0.15s;
                    }
                    .rb-tag-pill:hover {
                        background: rgba(245, 158, 11, 0.2);
                        border-color: #f59e0b;
                        color: #f59e0b;
                    }
                    #rb-quick-results-modal {
                        display: none;
                        position: fixed;
                        top: 0; left: 0; right: 0; bottom: 0;
                        background: rgba(0, 0, 0, 0.82);
                        backdrop-filter: blur(6px);
                        z-index: 99999;
                        align-items: center;
                        justify-content: center;
                        padding: 16px;
                    }
                    .rb-modal-content {
                        background: #171513;
                        border: 1px solid #44403c;
                        border-radius: 16px;
                        width: 100%;
                        max-width: 760px;
                        max-height: 85vh;
                        display: flex;
                        flex-direction: column;
                        overflow: hidden;
                        box-shadow: 0 24px 48px rgba(0, 0, 0, 0.7);
                    }
                    .rb-modal-header {
                        padding: 14px 18px;
                        border-bottom: 1px solid #292524;
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        background: #1f1b18;
                    }
                    .rb-modal-body {
                        padding: 16px;
                        overflow-y: auto;
                        display: flex;
                        flex-direction: column;
                        gap: 10px;
                    }
                    .rb-station-row {
                        display: flex;
                        align-items: center;
                        justify-content: space-between;
                        background: #23201d;
                        border: 1px solid #38332e;
                        padding: 10px 14px;
                        border-radius: 10px;
                        gap: 12px;
                        transition: border-color 0.15s;
                    }
                    .rb-station-row:hover {
                        border-color: #f59e0b;
                    }
                    .rb-station-info {
                        display: flex;
                        align-items: center;
                        gap: 12px;
                        flex: 1;
                        min-width: 0;
                    }
                    .rb-station-name {
                        font-weight: 600;
                        color: #fff;
                        font-size: 13px;
                        white-space: nowrap;
                        overflow: hidden;
                        text-overflow: ellipsis;
                    }
                    .rb-station-sub {
                        font-size: 11px;
                        color: #a8a29e;
                        margin-top: 2px;
                    }
                    .rb-actions-group {
                        display: flex;
                        gap: 6px;
                    }
                    .rb-btn-mini {
                        padding: 6px 12px;
                        font-size: 11px;
                        border-radius: 6px;
                        cursor: pointer;
                        border: none;
                        font-weight: 600;
                        transition: opacity 0.2s;
                    }
                    .rb-btn-mini-play { background: #059669; color: #fff; }
                    .rb-btn-mini-play:hover { background: #10b981; }
                    .rb-btn-mini-save { background: #d97706; color: #fff; }
                    .rb-btn-mini-save:hover { background: #f59e0b; }
                </style>

                <div class="rb-top-row">
                    <div class="rb-search-left" style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
                        <span class="rb-badge">Radio Browser</span>
                        <div class="rb-input-wrap" style="flex: 2; min-width: 180px;">
                            <span style="color:#f59e0b; font-size: 14px; margin-right: 4px;">🔍</span>
                            <input type="text" id="rb-inline-input" class="rb-input-field" placeholder="Station name..." />
                        </div>
                        <div class="rb-input-wrap" style="flex: 1.2; min-width: 120px;">
                            <input type="text" id="rb-inline-tag" class="rb-input-field" placeholder="Tag / Genre..." />
                        </div>
                        <div class="rb-input-wrap" style="width: 75px; min-width: 65px;">
                            <input type="text" id="rb-inline-country" class="rb-input-field" placeholder="Country" maxlength="2" style="text-transform: uppercase;" />
                        </div>
                        <button type="button" id="rb-inline-search-btn" class="rb-btn rb-btn-search">Search</button>
                    </div>
                    <div>
                        <a href="${RB_PORTAL_URL}" class="rb-btn rb-btn-portal" title="Open full Radio Browser Station Manager">
                            <span>🌐 Radio Browser Portal ↗</span>
                        </a>
                    </div>
                </div>

                <div class="rb-tags-row">
                    <span class="rb-tag-label">Quick:</span>
                    <span class="rb-tag-pill" data-tag="flac">Lossless FLAC</span>
                    <span class="rb-tag-pill" data-tag="jazz">Jazz</span>
                    <span class="rb-tag-pill" data-tag="classical">Classical</span>
                    <span class="rb-tag-pill" data-tag="ambient">Lounge & Ambient</span>
                    <span class="rb-tag-pill" data-tag="320k">320k High-Fi</span>
                    <span class="rb-tag-pill" data-tag="electronic">Electronic</span>
                    <span class="rb-tag-pill" data-country="PL">🇵🇱 Poland</span>
                    <span class="rb-tag-pill" data-country="US">🇺🇸 USA</span>
                    <span class="rb-tag-pill" data-country="GB">🇬🇧 UK</span>
                    <span class="rb-tag-pill" data-country="DE">🇩🇪 Germany</span>
                </div>
            `;
        }

        // Mount at determined point (below the buttonSet htmlEnd bar)
        if (mount.before) {
            mount.parent.insertBefore(container, mount.before);
        } else {
            mount.parent.appendChild(container);
        }

        if (mount.isBarBottom && mount.anchor) {
            const barStyle = window.getComputedStyle(mount.anchor);
            if (barStyle && barStyle.position === 'fixed') {
                container.classList.add('fixed-bar-dock');
            } else {
                container.classList.remove('fixed-bar-dock');
            }
        }
        container.style.display = 'flex';

        // Bind search actions
        const input = document.getElementById('rb-inline-input');
        const tagInput = document.getElementById('rb-inline-tag');
        const countryInput = document.getElementById('rb-inline-country');
        const btn = document.getElementById('rb-inline-search-btn');

        const triggerSearch = () => {
            const term = input ? input.value.trim() : '';
            const tag = tagInput ? tagInput.value.trim() : '';
            const country = countryInput ? countryInput.value.trim().toUpperCase() : '';
            doQuickSearch(term, tag, country);
        };

        if (btn) btn.onclick = triggerSearch;
        [input, tagInput, countryInput].forEach(el => {
            if (el) {
                el.onkeypress = (e) => {
                    if (e.key === 'Enter') triggerSearch();
                };
            }
        });

        // Bind quick tag pills
        const pills = container.querySelectorAll('.rb-tag-pill');
        pills.forEach(pill => {
            pill.onclick = () => {
                const tag = pill.getAttribute('data-tag');
                const country = pill.getAttribute('data-country');
                if (tag) {
                    if (tagInput) tagInput.value = tag;
                    doQuickSearch('', tag, countryInput ? countryInput.value : '');
                } else if (country) {
                    if (countryInput) countryInput.value = country;
                    doQuickSearch(input ? input.value : '', tagInput ? tagInput.value : '', country);
                }
            };
        });
    }

    // Modal Results Renderer
    function ensureModal() {
        let modal = document.getElementById('rb-quick-results-modal');
        if (!modal) {
            modal = document.createElement('div');
            modal.id = 'rb-quick-results-modal';
            modal.innerHTML = `
                <div class="rb-modal-content">
                    <div class="rb-modal-header">
                        <div style="font-weight: 700; color: #fff; font-size: 15px; display: flex; align-items: center; gap: 8px;">
                            <span style="color:#f59e0b;">📻</span> Radio-Browser Station Finder
                        </div>
                        <button id="rb-modal-close" style="background: none; border: none; color: #a8a29e; font-size: 20px; cursor: pointer; padding: 4px 8px;">✕</button>
                    </div>
                    <div id="rb-modal-body" class="rb-modal-body">
                        Loading stations...
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
            document.getElementById('rb-modal-close').onclick = () => {
                modal.style.display = 'none';
            };
            modal.onclick = (e) => {
                if (e.target === modal) modal.style.display = 'none';
            };
        }
        return modal;
    }

    async function doQuickSearch(term, tag, country) {
        if (!term && !tag && !country) return;
        const modal = ensureModal();
        modal.style.display = 'flex';
        const body = document.getElementById('rb-modal-body');
        const label = [term, tag, country].filter(Boolean).join(' · ');
        body.innerHTML = '<div style="text-align: center; color: #a8a29e; padding: 30px;"><div style="font-size:24px;margin-bottom:8px;">⏳</div>Querying Radio Browser mirrors for "' + label + '"...</div>';

        try {
            let query = 'limit=25&hidebroken=true&order=votes&reverse=true';
            if (term) query += '&name=' + encodeURIComponent(term);
            if (tag) query += '&tag=' + encodeURIComponent(tag);
            if (country) query += '&countrycode=' + encodeURIComponent(country);

            const resp = await fetch(RB_API_URL + '?action=search&' + query);
            const stations = await resp.json();

            if (!stations || stations.length === 0) {
                body.innerHTML = '<div style="text-align: center; color: #a8a29e; padding: 30px;">No stations found for "' + label + '". <a href="' + RB_PORTAL_URL + '" style="color: #f59e0b; text-decoration: underline;">Open full search portal</a></div>';
                return;
            }

            const EMPTY_ICON = "data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='36' height='36' viewBox='0 0 24 24'%3E%3C/svg%3E";
            function getStationIcon(fav) {
                if (!fav || typeof fav !== 'string') return EMPTY_ICON;
                const trimmed = fav.trim();
                if (!trimmed || 
                    trimmed === 'data:image/svg+xml,<svg xmlns=' || 
                    trimmed.startsWith('data:image/svg+xml,<svg xmlns=') || 
                    trimmed.startsWith('data:image/svg+xml,<svg')) {
                    return EMPTY_ICON;
                }
                return trimmed;
            }

            body.innerHTML = stations.map(s => {
                const icon = getStationIcon(s.favicon);
                const isFlac = (s.codec || '').toUpperCase() === 'FLAC';
                const subfolder = isFlac ? 'FLAC Lossless' : (s.bitrate >= 256 ? 'Audiophile 320k' : 'Web Radio');
                return `
                    <div class="rb-station-row">
                        <div class="rb-station-info">
                            <img src="${icon}" style="width: 36px; height: 36px; border-radius: 6px; object-fit: cover; background: #1c1917;" onerror="this.src='${EMPTY_ICON}'; this.onerror=null;">
                            <div style="min-width: 0; flex: 1;">
                                <div class="rb-station-name" title="${s.name}">${s.name}</div>
                                <div class="rb-station-sub">
                                    <span style="color:${isFlac ? '#10b981' : '#f59e0b'}; font-weight: 600;">${s.codec || 'MP3'}</span>
                                    · ${s.bitrate || 128} kbps · ${s.country || 'Global'}
                                </div>
                            </div>
                        </div>
                        <div class="rb-actions-group">
                            <button class="rb-btn-mini rb-btn-mini-play" onclick="window.rbPlayStation('${s.stationuuid}', '${encodeURIComponent(s.url_resolved || s.url)}')">▶ Play</button>
                            <button class="rb-btn-mini rb-btn-mini-save" onclick="window.rbSaveStation('${encodeURIComponent(s.name)}', '${encodeURIComponent(s.url_resolved || s.url)}', '${encodeURIComponent(icon)}', '${subfolder}')">➕ Add</button>
                        </div>
                    </div>
                `;
            }).join('');
        } catch (e) {
            body.innerHTML = '<div style="text-align: center; color: #ef4444; padding: 30px;">Error connecting to Radio Browser API. Please verify network connectivity.</div>';
        }
    }

    window.rbPlayStation = async function (uuid, encUrl) {
        try {
            const fd = new FormData();
            fd.append('action', 'play');
            fd.append('uuid', uuid);
            fd.append('url', decodeURIComponent(encUrl));
            await fetch(RB_API_URL, { method: 'POST', body: fd });
            if (window.notify) window.notify('Radio Browser', 'Streaming started on rAudio');
            else if (typeof window.banner === 'function') window.banner('Radio Browser', 'Streaming started', 'webradio');
        } catch (e) {
            console.error('[RadioBrowser Hook] Play error:', e);
        }
    };

    window.rbSaveStation = async function (encName, encUrl, encIcon, subfolder) {
        try {
            const fd = new FormData();
            fd.append('action', 'save_webradio');
            fd.append('name', decodeURIComponent(encName));
            fd.append('url', decodeURIComponent(encUrl));
            fd.append('icon', decodeURIComponent(encIcon));
            fd.append('subfolder', subfolder);
            const res = await fetch(RB_API_URL, { method: 'POST', body: fd });
            const json = await res.json();
            if (json.success) {
                alert('Saved "' + decodeURIComponent(encName) + '" to /srv/http/data/webradio/' + subfolder + ' (Directory/data format)!');
                // Trigger rAudio UI refresh if function exists
                if (typeof window.list === 'function') window.list();
                else if (typeof window.renderLibrary === 'function') window.renderLibrary();
                const modal = document.getElementById('rb-quick-results-modal');
                if (modal) modal.style.display = 'none';
            }
        } catch (e) {
            alert('Failed to save station: ' + e.message);
        }
    };

    // Diagnostics helper for testing/debugging
    window.rbDebug = function () {
        const isView = isWebRadioView();
        const mount = getMountPoint();
        const bar = document.getElementById('radiobrowser-search-bar');
        return {
            isWebRadioView: isView,
            mountTarget: mount ? (mount.before ? 'before #' + (mount.before.id || mount.before.tagName) : 'append to #' + (mount.parent.id || mount.parent.tagName)) : null,
            searchBarMounted: !!bar,
            searchBarVisible: bar ? bar.style.display !== 'none' : false,
            gMode: window.G ? window.G.mode : undefined
        };
    };

    // Safeguard AJAX requests to library.php: ensure 'mode' is present when library is 'radio' or 'webradio'
    // Prevents PHP Warning: Undefined variable $MODE in /srv/http/library.php on line 484
    function patchLibraryRequests() {
        if (window.jQuery && !window._rbAjaxPatched) {
            window._rbAjaxPatched = true;
            window.jQuery.ajaxPrefilter(function (options) {
                if (options.url && (options.url === 'library.php' || options.url.endsWith('/library.php'))) {
                    if (typeof options.data === 'string') {
                        if (options.data.includes('library=radio') && !options.data.includes('mode=')) {
                            options.data += '&mode=webradio';
                        }
                    } else if (typeof options.data === 'object' && options.data) {
                        if (options.data.library === 'radio' && !options.data.mode) {
                            options.data.mode = options.data.gmode || 'webradio';
                        }
                    }
                }
            });
        }
        if (typeof window.LIST === 'function' && !window._rbListPatched) {
            window._rbListPatched = true;
            const origList = window.LIST;
            window.LIST = function (query, callback, json) {
                if (query && query.library === 'radio' && !query.mode) {
                    query.mode = query.gmode || 'webradio';
                }
                return origList(query, callback, json);
            };
        }
    }
    patchLibraryRequests();
    window.addEventListener('DOMContentLoaded', patchLibraryRequests);

    // Auto-mount on DOM readiness and observe view mutations
    if (document.readyState === 'loading') {
        window.addEventListener('DOMContentLoaded', injectSearchBar);
    } else {
        injectSearchBar();
    }

    const observer = new MutationObserver(function () {
        injectSearchBar();
    });

    observer.observe(document.body || document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'style', 'data-mode']
    });

    // Handle history/hash navigation
    window.addEventListener('hashchange', injectSearchBar);
    window.addEventListener('popstate', injectSearchBar);

    // Periodic check for rAudio SPA navigation
    setInterval(injectSearchBar, 800);
})();
HOOK_EOF

chmod 644 "$DIR_ASSETS_JS/radiobrowser-webradio-hook.js"
chown http:http "$DIR_ASSETS_JS/radiobrowser-webradio-hook.js" 2>/dev/null || true

# Inject script tag into rAudio WebUI entry points below $htmlbar / htmlEnd bar if present
for file in "/srv/http/index.php" "/srv/http/app/index.php" "/srv/http/index.html" "/srv/http/app/templates/footer.html" "/srv/http/app/templates/head.html" "/srv/http/app/templates/library.html"; do
    if [[ -f "$file" ]] && ! grep -q "radiobrowser-webradio-hook.js" "$file"; then
        if grep -q "htmlEnd" "$file"; then
            sed -i '/htmlEnd/a <script src="/assets/js/radiobrowser-webradio-hook.js?v=1.0.0" defer></script>' "$file" 2>/dev/null || true
        elif grep -q "buttonSet" "$file"; then
            sed -i '/buttonSet/a <script src="/assets/js/radiobrowser-webradio-hook.js?v=1.0.0" defer></script>' "$file" 2>/dev/null || true
        elif grep -q "</body>" "$file"; then
            sed -i 's|</body>|<script src="/assets/js/radiobrowser-webradio-hook.js?v=1.0.0" defer></script>\n</body>|g' "$file"
        elif grep -q "</head>" "$file"; then
            sed -i 's|</head>|<script src="/assets/js/radiobrowser-webradio-hook.js?v=1.0.0" defer></script>\n</head>|g' "$file"
        else
            echo '<script src="/assets/js/radiobrowser-webradio-hook.js?v=1.0.0" defer></script>' >> "$file"
        fi
        echo "    Hooked into $file (below htmlEnd / buttonSet)"
    fi
done

# 5. Deploy rAudio Plugin Configuration (raudio.conf)
echo "==> [5/7] Installing plugin configuration at $DIR_SYSTEM/raudio-radiobrowser.conf..."
cat <<'CONF_EOF' > "$DIR_SYSTEM/raudio-radiobrowser.conf"
[general]
enabled = 1
version = 1.0.0
user_agent = rAudio-RadioBrowser-Addon/1.0.0 (ArchLinuxARM; RaspberryPi)
log_level = info
autostart = 1

[radiobrowser]
default_endpoint = https://de1.api.radio-browser.info
backup_mirrors = https://nl1.api.radio-browser.info,https://at1.api.radio-browser.info,https://all.api.radio-browser.info
api_timeout_sec = 6
cache_ttl = 86400

[audio]
min_bitrate = 192
prefer_lossless = 1
default_codec = AAC

[webradio]
webradio_dir = /srv/http/data/webradio
webradio_img_dir = /srv/http/data/webradio/img
webradio_format = directory_data
data_file_name = data
auto_download_favicons = 1
file_encoding = UTF-8

[mpd]
host = 127.0.0.1
port = 6600

[redis]
notify_channel = notify
webradio_channel = webradio
CONF_EOF

cp -f "$DIR_SYSTEM/raudio-radiobrowser.conf" "$DIR_DATA/radiobrowser/raudio.conf" 2>/dev/null || true
chmod 664 "$DIR_SYSTEM/raudio-radiobrowser.conf" "$DIR_DATA/radiobrowser/raudio.conf" 2>/dev/null || true
chown http:http "$DIR_SYSTEM/raudio-radiobrowser.conf" "$DIR_DATA/radiobrowser/raudio.conf" 2>/dev/null || true

# 6. Seed curated presets in new Directory/data format
echo "==> [6/7] Pre-seeding curated audiophile stations into $DIR_RB_ROOT in Directory/data format..."
bash "$DIR_BASH/radiobrowser.sh" presets

# 7. Register uninstaller
echo "==> [7/7] Registering addon uninstaller at $UNINSTALL_BIN..."
cat <<'UNINST_EOF' > "$UNINSTALL_BIN"
#!/bin/bash
echo "==> [rAudio Addon] Removing Radio Browser Plugin..."
rm -f /srv/http/bash/radiobrowser.sh
rm -f /srv/http/app/radiobrowser.php
rm -f /srv/http/assets/js/radiobrowser-webradio-hook.js
rm -rf /srv/http/radiobrowser
rm -rf /srv/http/data/radiobrowser
rm -f /srv/http/data/system/raudio-radiobrowser.conf
rm -f /usr/local/bin/uninstall_radiobrowser.sh

# Remove script injection from entry points
for file in "/srv/http/index.php" "/srv/http/app/index.php" "/srv/http/index.html" "/srv/http/app/templates/footer.html" "/srv/http/app/templates/head.html" "/srv/http/app/templates/library.html"; do
    if [[ -f "$file" ]]; then
        sed -i '/radiobrowser-webradio-hook.js/d' "$file" 2>/dev/null || true
    fi
done

command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
echo "==> [rAudio Addon] Radio Browser Plugin successfully uninstalled."
exit 0
UNINST_EOF

chmod 755 "$UNINSTALL_BIN"

# Sync with rAudio Redis & MPD
command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
command -v redis-cli &>/dev/null && redis-cli publish notify '{"title":"Radio Browser","text":"Web Radio updated with Search bar & Directory/data format"}' &>/dev/null || true
[[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true
command -v mpc &>/dev/null && mpc update Webradio &>/dev/null || true

echo "========================================================================"
echo "==> [rAudio Addon] Radio-Browser.info Installed Successfully!"
echo "========================================================================"
echo " ==> NEW WEBRADIO DIRECTORY FORMAT:"
echo "     Base Path: /srv/http/data/webradio/"
echo "     Structure: <Station Directory>/data (contains stream hyperlink)"
echo "     Cover Art: <Station Directory>/coverart.jpg"
echo ""
echo " ==> ACCESS IN RAUDIO WEBUI:"
echo "     1. Tap [Library] -> [Web Radio]"
echo "     2. Notice the new [ 🔍 Search Radio-Browser ] field & [ 🌐 Portal ] link"
echo "        injected directly into the Web Radio header!"
echo "     3. Open the folder: [Radio Browser] to view curated lossless categories:"
echo "        * FLAC Lossless"
echo "        * Audiophile 320k"
echo "        * Jazz & Classical"
echo "        * Lounge & Ambient"
echo ""
echo " ==> STANDALONE SEARCH PORTAL:"
echo "     Open: http://<raudio-ip>/radiobrowser/ or /app/radiobrowser.php"
echo ""
echo " ==> CLI SEARCH:"
echo "     /srv/http/bash/radiobrowser.sh search 'FLAC'"
echo "========================================================================"
exit 0
