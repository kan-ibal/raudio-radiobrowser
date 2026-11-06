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

USER_AGENT="rAudio-RadioBrowser-NativeBash/1.0.0 (https://github.com/kan-ibal/raudio-radiobrowser)"
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
