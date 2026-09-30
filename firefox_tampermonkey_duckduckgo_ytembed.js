// ==UserScript==
// @name         YouTube Link Rewriter (DuckDuckGo → ytembed.macosxjs.com)
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Rewrites YouTube search result links to ytembed.macosxjs.com with encoded video ID
// @author       You
// @icon         https://www.google.com/s2/favicons?domain=duckduckgo.com&sz=64
// @match        *://*/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function () {
  "use strict";

  // ---- Your provided helper functions ----

  function extractYouTubeId(url) {
    const patterns = [
      /(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)/,
      /youtube\.com\/embed\/([^&\n?#]+)/,
      /youtube\.com\/v\/([^&\n?#]+)/,
    ];

    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match && match[1]) {
        return match[1];
      }
    }
    return null;
  }

  function encodeYouTubeUrl(youtubeUrl) {
    const videoId = extractYouTubeId(youtubeUrl);
    if (!videoId) return null;
    return btoa(videoId)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
  }

  // ---- Core rewriting logic ----

  /**
   * Process a single <a> element: if its href is a YouTube link,
   * rewrite it to https://ytembed.macosxjs.com?<encodedId>.
   * Preserves other attributes and the inner text.
   */
  function rewriteYouTubeLink(anchor) {
    const href = anchor.getAttribute("href");
    if (!href) return;

    const encoded = encodeYouTubeUrl(href);
    if (!encoded) return;

    anchor.setAttribute("href", `https://ytembed.macosxjs.com?${encoded}`);
    // Optionally add data attributes for debugging / styling
    anchor.setAttribute("data-original-youtube-href", href);
    anchor.setAttribute("target", "_blank");
    anchor.setAttribute("data-ytembed-rewritten", "true");
  }

  /**
   * Scan a container (document or element) for all YouTube links
   * and rewrite them.
   */
  function rewriteAllYouTubeLinks(root = document) {
    const anchors = root.querySelectorAll(
      'a[href*="youtube.com"], a[href*="youtu.be"]',
    );
    for (const a of anchors) {
      // Skip if already rewritten
      if (a.hasAttribute("data-ytembd-rewritten")) continue;
      rewriteYouTubeLink(a);
    }
  }

  // ---- Observe DOM for dynamically added results ----

  function observeAndRewrite() {
    // Initial pass
    rewriteAllYouTubeLinks(document);

    // Watch for new nodes (search results load dynamically on DDG, Google, etc.)
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue;

          // Check if the added node itself is a YouTube link
          if (
            node.matches &&
            node.matches('a[href*="youtube.com"], a[href*="youtu.be"]')
          ) {
            rewriteYouTubeLink(node);
          }

          // Check descendants
          if (node.querySelectorAll) {
            rewriteAllYouTubeLinks(node);
          }
        }
      }
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  // ---- Start ----

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", observeAndRewrite);
  } else {
    observeAndRewrite();
  }
})();
