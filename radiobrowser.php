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
