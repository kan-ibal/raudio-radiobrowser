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
