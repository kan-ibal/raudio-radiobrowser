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
