// ==UserScript==
// @name         OldGamesDownload Auto Load More
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  Automatically clicks "Load more games" button
// @author       You
// @match        https://oldgamesdownload.com/*
// @icon         https://favicool.com/api/icon?domain=oldgamesdownload.com&sz=128
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function() {
    'use strict';

    const LOG = (...a) => console.log('%c[AutoLoad]', 'color:#0af;font-weight:bold', ...a);
    const COOLDOWN_MS = 1500;
    let lastClick = 0;
    let clickedCount = 0;

    LOG('Script started');

    function findLoadMoreButton() {
        // Strategy 1: exact container class match
        let containers = document.querySelectorAll('.masonry-load-more.load-more');
        for (const c of containers) {
            const a = c.querySelector('a.button');
            if (a && /load\s*more/i.test(a.textContent)) return a;
        }

        // Strategy 2: any anchor whose text contains "load more" (games)
        const anchors = document.querySelectorAll('a.button, a');
        for (const a of anchors) {
            const t = (a.textContent || '').trim();
            if (/load\s*more\s*games/i.test(t)) return a;
        }
        return null;
    }

    function clickButton(btn) {
        const now = Date.now();
        if (now - lastClick < COOLDOWN_MS) return;
        lastClick = now;
        clickedCount++;

        LOG(`Clicking (#${clickedCount}):`, btn);

        // Dispatch a full synthetic mouse event sequence — some themes
        // rely on mousedown/mouseup, not just click().
        const rect = btn.getBoundingClientRect();
        const opts = {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
            button: 0
        };

        try {
            btn.dispatchEvent(new MouseEvent('mousedown', opts));
            btn.dispatchEvent(new MouseEvent('mouseup', opts));
            btn.dispatchEvent(new MouseEvent('click', opts));
        } catch (e) {
            LOG('MouseEvent failed, falling back to .click()', e);
        }

        // Also call native click as a fallback (harmless if already clicked)
        try { btn.click(); } catch (e) {}
    }

    function isVisible(el) {
        if (!el || !el.isConnected) return false;
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;
        const style = getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
        return true;
    }

    // Main loop: check every 400ms whether the button is on screen.
    // Simpler and more reliable than MutationObserver for this use case.
    setInterval(() => {
        const btn = findLoadMoreButton();
        if (!btn) return;

        if (!isVisible(btn)) return;

        // Is it within the viewport (with a bit of margin)?
        const rect = btn.getBoundingClientRect();
        const vh = window.innerHeight || document.documentElement.clientHeight;
        const inView = rect.top < vh + 200 && rect.bottom > -200;

        if (inView) {
            clickButton(btn);
        }
    }, 400);

    LOG('Watcher installed');
})();