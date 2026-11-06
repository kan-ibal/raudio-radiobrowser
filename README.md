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
- Run `/srv/http/bash/radiobrowser.sh search "FLAC"`
- Run `/srv/http/bash/radiobrowser.sh play "<stream-url-or-uuid>"`
- Run `/srv/http/bash/radiobrowser.sh save "Name" "URL" "IconURL" "Category"`

---

## Installation Methods

- Install `curl -sL https://raw.githubusercontent.com/kan-ibal/raudio-radiobrowser/refs/heads/main/install.sh | bash`
- Uninstall `curl -sL https://raw.githubusercontent.com/kan-ibal/raudio-radiobrowser/refs/heads/main/uninstall.sh | bash`