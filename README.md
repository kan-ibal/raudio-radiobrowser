# rAudio Radio Browser Native Addon & Plugin

Radio Browser integration for **rAudio** (Arch Linux ARM / Raspberry Pi), built on top of [radio-browser.info](https://www.radio-browser.info) and compatible with [rAudio Addons Manager](https://github.com/rern/rAudio/blob/main/srv/http/settings/addonsprogress.php).

---

## What's New in Version 1.0.0

1. **Saves streams in rAudio standard**:
     ```
     /srv/http/data/webradio/<Category>/<Station Name>/data
     ```
     where `data` is a file containing the direct stream hyperlink (e.g. `https://stream.radioparadise.com/flac\n`), with station cover art stored as `coverart.jpg` in the same directory.
   
2. **[Library] -> [Web Radio] Search Bar & Portal Link**:
   - Injects a sleek search field directly into rAudio's `[Library] -> [Web Radio]` header.
   - Allows instant search across stations directly from the Web Radio screen.
   - Includes a direct link button: **`[ 🌐 Radio Browser Portal ↗ ]`** to open the full station manager at `/radiobrowser/`.

---

## Files in this Directory

| File | Purpose | Target Path on rAudio |
| :--- | :--- | :--- |
| `install.sh` | Main installer called by `addonsprogress.php` or SSH | Temporary execution (`bash install.sh`) |
| `radiobrowser.sh` | Native Bash CLI engine (`search`, `play`, `save`, `convert`, `presets`) | `/srv/http/bash/radiobrowser.sh` |
| `radiobrowser.php` | Lightweight PHP WebUI bridge for search, play, convert, and Redis reload | `/srv/http/app/radiobrowser.php` |
| `radiobrowser-webradio-hook.js` | Web Radio header hook for search field & portal link | `/srv/http/assets/js/radiobrowser-webradio-hook.js` |
| `index.html` | Standalone WebUI Portal for station search, auditioning & 1-click saving | `/srv/http/radiobrowser/index.html` |
| `uninstall.sh` | Clean uninstaller required by rAudio's Addon Manager | `/usr/local/bin/uninstall_radiobrowser.sh` |
| `addon.json` | Manifest catalog entry for `/srv/http/data/addons/addons-list.json` | Addons registry |
| `raudio.conf` | Configuration for rAudio Radio Browser native plugin & audiophile tuning | `/srv/http/data/system/raudio-radiobrowser.conf` |

---

## Accessing Radio Browser on rAudio

### 1. In rAudio WebUI Library
- Go to **Library** (music note icon).
- Tap **Web Radio**.
- You will see the **Search Field** and **[ 🌐 Radio Browser Portal ↗ ]** link right above the folder list!
- Open the **`[Radio Browser]`** folder to view example categories:
  - `FLAC Lossless` (Radio Paradise, Mother Earth, Chill Out Zone)
  - `Audiophile 320k` (Linn Classical, Linn Jazz, Naim Radio)
  - `Jazz & Classical` (Swiss Classic, ABC Classic)
  - `Lounge & Ambient` (SomaFM Groove Salad, Drone Zone)
- Each station folder contains `data` (stream URL) and `coverart.jpg`.

### 2. Standalone WebUI Portal
- Navigate in any browser to:
  - `http://<your-raudio-ip>/radiobrowser/` or
  - `http://<your-raudio-ip>/app/radiobrowser.php`
- Provides real-time search across 50,000+ stations, FLAC/AAC/MP3 bitrate filters, instant auditioning via MPD, 1-click saving to `<Directory>/data`, and a **Run Legacy Migration** button.

### 3. Command Line Interface (SSH)
- Run `/srv/http/bash/radiobrowser.sh convert` (migrates any legacy files)
- Run `/srv/http/bash/radiobrowser.sh search "FLAC"`
- Run `/srv/http/bash/radiobrowser.sh play "<stream-url-or-uuid>"`
- Run `/srv/http/bash/radiobrowser.sh save "Name" "URL" "IconURL" "Category"`

---

## Installation Methods

### Method 1: Direct SSH One-Liner (Self-Contained)
Run directly on your Raspberry Pi:

```bash
bash -c "$(cat << 'EOF'
#!/bin/bash
set -e
DIR_APP="/srv/http/app"
DIR_BASH="/srv/http/bash"
DIR_DATA="/srv/http/data"
DIR_WEBRADIO="$DIR_DATA/webradio"
DIR_RB_ROOT="$DIR_WEBRADIO/Radio Browser"
DIR_RADIOBROWSER_WEB="/srv/http/radiobrowser"
DIR_ADDONS="$DIR_DATA/addons"
DIR_ASSETS_JS="/srv/http/assets/js"
UNINSTALL_BIN="/usr/local/bin/uninstall_radiobrowser.sh"

echo "==> [rAudio Addon] Installing Radio Browser Native Plugin..."
mkdir -p "$DIR_APP" "$DIR_BASH" "$DIR_WEBRADIO" "$DIR_DATA/radiobrowser" "$DIR_ADDONS" "$DIR_RADIOBROWSER_WEB" "$DIR_ASSETS_JS"
mkdir -p "$DIR_RB_ROOT/FLAC Lossless" "$DIR_RB_ROOT/Audiophile 320k" "$DIR_RB_ROOT/Jazz & Classical" "$DIR_RB_ROOT/Lounge & Ambient"

cat << 'ENGINE' > "$DIR_BASH/radiobrowser.sh"
#!/bin/bash
DIR_DATA="/srv/http/data"
DIR_WEBRADIO="$DIR_DATA/webradio"
DIR_RB_ROOT="$DIR_WEBRADIO/Radio Browser"
USER_AGENT="rAudio-RadioBrowser-Bash/1.0.0 (https://github.com/kan-ibal/raudio-radiobrowser)"
MIRRORS=("https://de1.api.radio-browser.info" "https://nl1.api.radio-browser.info" "https://at1.api.radio-browser.info" "https://all.api.radio-browser.info")

query_rb() {
    local endpoint="$1" params="$2"
    for mirror in "${MIRRORS[@]}"; do
        local url="${mirror}${endpoint}"
        [[ -n "$params" ]] && url="${url}?${params}"
        local resp
        resp=$(curl -s --max-time 6 -H "User-Agent: $USER_AGENT" -H "Accept: application/json" "$url" 2>/dev/null)
        if [[ $? -eq 0 && -n "$resp" && "$resp" != "[]" ]]; then
            echo "$resp"; return 0
        fi
    done
    echo "[]"; return 1
}

cmd_search() {
    local name="$1" tag="$2" codec="$3" bitrate="${4:-0}" limit="${5:-20}"
    local query="hidebroken=true&order=votes&reverse=true&limit=${limit}"
    [[ -n "$name" ]] && query="${query}&name=$(curl -so /dev/null -w %{url_effective} --get --data-urlencode "name=$name" '' | cut -c3-)"
    [[ -n "$tag" ]] && query="${query}&tag=$(curl -so /dev/null -w %{url_effective} --get --data-urlencode "tag=$tag" '' | cut -c3-)"
    [[ -n "$codec" && "$codec" != "ALL" ]] && query="${query}&codec=${codec}"
    [[ "$bitrate" -gt 0 ]] && query="${query}&bitrateMin=${bitrate}"
    query_rb "/json/stations/search" "$query"
}

cmd_play() {
    local target="$1" resolved_url="$target"
    if [[ "$target" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        local res=$(query_rb "/json/url/$target")
        resolved_url=$(echo "$res" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
        [[ -z "$resolved_url" ]] && resolved_url="$target"
    fi
    if command -v mpc &>/dev/null; then
        mpc add "$resolved_url"
        local pos=$(mpc playlist | wc -l)
        mpc play "$pos"
        command -v redis-cli &>/dev/null && redis-cli publish notify '{"title":"Radio Browser","text":"Streaming started"}' &>/dev/null
        echo "{\"success\":true,\"url\":\"$resolved_url\",\"position\":$pos}"
    else
        echo "{\"success\":false,\"error\":\"mpc not found\"}"
    fi
}

cmd_save() {
    local name="$1" url="$2" icon="$3" subfolder="$4"
    [[ -z "$name" || -z "$url" ]] && exit 1
    local target_parent="$DIR_RB_ROOT"
    [[ -n "$subfolder" && "$subfolder" != "." ]] && target_parent="$DIR_RB_ROOT/$subfolder"
    mkdir -p "$DIR_WEBRADIO" "$DIR_RB_ROOT" "$target_parent"

    local clean_name=$(echo "$name" | tr -d '/\\:*?"<>|' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
    [[ -z "$clean_name" ]] && clean_name="Station_$(date +%s)"

    # Format: Station directory containing a 'data' file with the stream hyperlink
    local station_dir="$target_parent/$clean_name"
    mkdir -p "$station_dir"
    printf "%s\n" "$url" > "$station_dir/data"
    chmod 664 "$station_dir/data" 2>/dev/null || true

    if [[ -n "$icon" ]]; then
        curl -sL --max-time 6 "$icon" -o "$station_dir/coverart.jpg" 2>/dev/null || true
        [[ -s "$station_dir/coverart.jpg" ]] && chmod 664 "$station_dir/coverart.jpg" 2>/dev/null || true
    fi

    chmod 775 "$station_dir" 2>/dev/null || true
    chown -R http:http "$station_dir" 2>/dev/null || true
    command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
    echo "{\"success\":true,\"saved\":\"$clean_name\",\"path\":\"$station_dir/data\"}"
}

cmd_convert() {
    local count=0
    while IFS= read -r -d '' legacy_file; do
        [[ ! -f "$legacy_file" ]] && continue
        local parent_dir=$(dirname "$legacy_file")
        local base_name=$(basename "$legacy_file")
        local stream_url="${base_name//|//}"
        local station_name=$(head -n 1 "$legacy_file" 2>/dev/null | tr -d '\r\n')
        [[ -z "$station_name" ]] && station_name="Web_Station_$((count+1))"
        local clean_name=$(echo "$station_name" | tr -d '/\\:*?"<>|' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
        local station_dir="$parent_dir/$clean_name"
        mkdir -p "$station_dir"
        printf "%s\n" "$stream_url" > "$station_dir/data"
        chmod 664 "$station_dir/data" 2>/dev/null || true
        chmod 775 "$station_dir" 2>/dev/null || true
        chown -R http:http "$station_dir" 2>/dev/null || true
        rm -f "$legacy_file"
        count=$((count+1))
    done < <(find "$DIR_WEBRADIO" -maxdepth 4 -type f -name "*||*" -print0 2>/dev/null)
    echo "Converted $count legacy stations."
}

cmd_presets() {
    cmd_save "Radio Paradise (Main FLAC)" "https://stream.radioparadise.com/flac" "https://radioparadise.com/favicon-32x32.png" "FLAC Lossless"
    cmd_save "Radio Paradise (Mellow FLAC)" "https://stream.radioparadise.com/mellow-flac" "https://radioparadise.com/favicon-32x32.png" "FLAC Lossless"
    cmd_save "Mother Earth Radio (Hi-Res)" "https://motherearth.streamserver24.com/listen/motherearth/motherearth" "https://motherearthradio.de/favicon.ico" "FLAC Lossless"
    cmd_save "Linn Classical (320k)" "http://radio.linn.co.uk:8004/autodj" "https://www.linn.co.uk/favicon.ico" "Audiophile 320k"
    cmd_save "Linn Jazz (320k)" "http://radio.linn.co.uk:8000/autodj" "https://www.linn.co.uk/favicon.ico" "Audiophile 320k"
    cmd_save "Swiss Classic (HQ)" "https://stream.srg-ssr.ch/m/rsc_de/mp3_128" "https://www.radioswissclassic.ch/favicon.ico" "Jazz & Classical"
    cmd_save "SomaFM Groove Salad" "https://ice2.somafm.com/groovesalad-256-mp3" "https://somafm.com/img3/groovesalad-120.png" "Lounge & Ambient"
    cmd_save "★ Radio Paradise (Main FLAC)" "https://stream.radioparadise.com/flac" "https://radioparadise.com/favicon-32x32.png" ""
}

case "$1" in
    search)   cmd_search "$2" "$3" "$4" "$5" "$6" ;;
    play)     cmd_play "$2" ;;
    save)     cmd_save "$2" "$3" "$4" "$5" ;;
    convert)  cmd_convert ;;
    presets)  cmd_presets ;;
    *) echo "Usage: $0 {search|play|save|convert|presets}" ; exit 1 ;;
esac
ENGINE

chmod 755 "$DIR_BASH/radiobrowser.sh"
chown http:http "$DIR_BASH/radiobrowser.sh" 2>/dev/null || true
bash "$DIR_BASH/radiobrowser.sh" convert 2>/dev/null || true

cat << 'PHP_EOF' > "$DIR_APP/radiobrowser.php"
<?php
$action = $_GET['action'] ?? $_POST['action'] ?? '';
if (empty($action) || $action === 'ui' || isset($_GET['ui'])) {
    if (file_exists('/srv/http/radiobrowser/index.html')) {
        header('Content-Type: text/html; charset=utf-8');
        include '/srv/http/radiobrowser/index.html';
        exit;
    }
}
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
if ($action === 'search') {
    $res = @file_get_contents('https://de1.api.radio-browser.info/json/stations/search?' . http_build_query($_GET));
    echo $res ?: '[]';
} elseif ($action === 'play') {
    $url = $_POST['url'] ?? $_GET['url'] ?? '';
    if ($url) {
        exec('/srv/http/bash/radiobrowser.sh play ' . escapeshellarg($url), $out, $st);
        echo json_encode(['success' => $st === 0, 'url' => $url]);
    }
} elseif ($action === 'save_webradio') {
    $name = $_POST['name'] ?? $_GET['name'] ?? '';
    $url = $_POST['url'] ?? $_GET['url'] ?? '';
    $icon = $_POST['icon'] ?? $_GET['icon'] ?? '';
    $subfolder = $_POST['subfolder'] ?? $_GET['subfolder'] ?? '';
    exec(sprintf('/srv/http/bash/radiobrowser.sh save %s %s %s %s', escapeshellarg($name), escapeshellarg($url), escapeshellarg($icon), escapeshellarg($subfolder)), $out, $st);
    echo json_encode(['success' => $st === 0]);
} elseif ($action === 'convert') {
    exec('/srv/http/bash/radiobrowser.sh convert', $out, $st);
    echo json_encode(['success' => $st === 0]);
} elseif ($action === 'presets') {
    exec('/srv/http/bash/radiobrowser.sh presets', $out, $st);
    echo json_encode(['success' => $st === 0]);
}
PHP_EOF

chmod 755 "$DIR_APP/radiobrowser.php"
chown http:http "$DIR_APP/radiobrowser.php" 2>/dev/null || true

# Inject Web Radio hook for search field and link
cat << 'HOOK_EOF' > "$DIR_ASSETS_JS/radiobrowser-webradio-hook.js"
(function () {
    function injectBar() {
        const pathEl = document.getElementById('lib-path') || document.querySelector('.lipath');
        const text = pathEl ? (pathEl.innerText || '') : '';
        if (!text.toUpperCase().includes('WEBRADIO') && !text.toUpperCase().includes('WEB RADIO')) {
            const bar = document.getElementById('radiobrowser-search-bar');
            if (bar) bar.style.display = 'none';
            return;
        }
        let bar = document.getElementById('radiobrowser-search-bar');
        if (bar) { bar.style.display = 'flex'; return; }
        const target = document.getElementById('lib-list') || document.getElementById('page-library') || document.body;
        bar = document.createElement('div');
        bar.id = 'radiobrowser-search-bar';
        bar.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 14px;margin:8px 12px;background:rgba(245,158,11,0.12);border:1px solid rgba(245,158,11,0.35);border-radius:12px;';
        bar.innerHTML = '<div style="display:flex;align-items:center;gap:8px;flex:1;"><span style="font-size:16px;">🔍</span><input type="text" id="rb-inline-input" placeholder="Search Radio-Browser (50,000+ stations)..." style="flex:1;background:#1c1917;border:1px solid #44403c;border-radius:8px;padding:7px 12px;color:#f5f5f4;font-size:13px;outline:none;" /><button id="rb-inline-btn" style="background:#f59e0b;color:#000;border:none;padding:7px 14px;border-radius:8px;font-weight:600;font-size:12px;cursor:pointer;">Search</button></div><div><a href="/radiobrowser/" style="background:#292524;color:#f5f5f4;border:1px solid #44403c;padding:7px 14px;border-radius:8px;font-size:12px;font-weight:600;text-decoration:none;">🌐 Portal ↗</a></div>';
        if (target.id === 'lib-list') target.parentNode.insertBefore(bar, target); else target.appendChild(bar);
        const inp = document.getElementById('rb-inline-input');
        const btn = document.getElementById('rb-inline-btn');
        if (inp && btn) {
            btn.onclick = () => { if (inp.value.trim()) window.location.href = '/radiobrowser/?q=' + encodeURIComponent(inp.value.trim()); };
            inp.onkeypress = (e) => { if (e.key === 'Enter' && inp.value.trim()) window.location.href = '/radiobrowser/?q=' + encodeURIComponent(inp.value.trim()); };
        }
    }
    const obs = new MutationObserver(injectBar);
    window.addEventListener('DOMContentLoaded', () => { injectBar(); obs.observe(document.body, { childList: true, subtree: true }); });
    setInterval(injectBar, 1500);
})();
HOOK_EOF

chmod 644 "$DIR_ASSETS_JS/radiobrowser-webradio-hook.js"
for file in "/srv/http/app/index.php" "/srv/http/index.html"; do
    if [[ -f "$file" ]] && ! grep -q "radiobrowser-webradio-hook.js" "$file"; then
        sed -i 's|</body>|<script src="/assets/js/radiobrowser-webradio-hook.js?v=2.4"></script>\n</body>|g' "$file" 2>/dev/null || true
    fi
done

bash "$DIR_BASH/radiobrowser.sh" presets
command -v redis-cli &>/dev/null && redis-cli publish webradio reload &>/dev/null || true
[[ -x "/srv/http/bash/cmd.sh" ]] && /srv/http/bash/cmd.sh webradiocount &>/dev/null || true

echo "==> [rAudio Addon] Radio Browser Plugin installed successfully!"
echo "==> Web Radio Format: /srv/http/data/webradio/<Station Directory>/data"
echo "==> WebUI: Open Library -> Web Radio (see injected search field & portal link)"
EOF
)"
```

### Method 2: Via rAudio Addons Manager (`addonsprogress.php`)
1. Place `addon.json` entry into `/srv/http/data/addons/addons-list.json`.
2. In rAudio WebUI navigate to: **Settings -> Addons -> Radio-Browser.info -> Install**.
3. `addonsprogress.php` executes `install.sh` and streams execution output live to the browser modal.
4. On completion, the uninstaller `/usr/local/bin/uninstall_radiobrowser.sh` is automatically linked to the **Uninstall** button.
