// ==UserScript==
// @name         DuckDuckGo Image Un-wrapper (auto-redirect to real image)
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Detects DuckDuckGo / Bing image proxy URLs (external-content.duckduckgo.com/iu/?u=...) and redirects straight to the real image. Also redirects to .png/.jpg/.jpeg/.webp/.gif when a page is just a wrapper around one.
// @author       You
// @match        *://*/*
// @grant        none
// @run-at       document-start
// ==/UserScript==

(function () {
  "use strict";

  // ============================================================
  // CONFIG
  // ============================================================

  // Hosts whose `/iu/?u=...` style proxies we know how to unwrap.
  const PROXY_HOSTS = [
    "external-content.duckduckgo.com",
    "external-content.duckduckgo.com.", // paranoid: trailing dot
  ];

  // Query params (in order of preference) that may contain the real URL.
  const URL_PARAMS = ["u", "url", "imgurl", "mediaurl", "src"];

  // Image extensions we consider "direct image links".
  const IMAGE_EXT_RE = /\.(png|jpe?g|gif|webp|avif|bmp|svg|tiff?)(\?.*)?$/i;

  // If true, also redirect pages whose *only* meaningful content is
  // a single image (e.g. some viewer/embed pages). Off by default
  // because it's easy to misfire on real sites.
  const REDIRECT_SINGLE_IMAGE_PAGES = false;

  // ============================================================
  // HELPERS
  // ============================================================

  const isHttp = (u) => /^https?:\/\//i.test(u || "");

  const currentHost = location.hostname.toLowerCase();

  const isProxyHost = (host) => {
    const h = host.replace(/\.$/, "").toLowerCase();
    return PROXY_HOSTS.some(
      (p) =>
        h === p.replace(/\.$/, "") || h.endsWith("." + p.replace(/\.$/, "")),
    );
  };

  const looksLikeImageUrl = (u) => isHttp(u) && IMAGE_EXT_RE.test(u);

  // Extract the real URL from a proxy link, if we can.
  // Returns a string URL or null.
  const extractRealUrl = (rawUrl) => {
    let u;
    try {
      u = new URL(rawUrl);
    } catch {
      return null;
    }

    if (!isProxyHost(u.hostname)) return null;

    for (const key of URL_PARAMS) {
      const val = u.searchParams.get(key);
      if (!val) continue;

      let decoded = val;
      // DDG double-encodes sometimes; try a second pass.
      try {
        decoded = decodeURIComponent(decoded);
      } catch (_) {}
      try {
        decoded = decodeURIComponent(decoded);
      } catch (_) {}

      if (isHttp(decoded)) return decoded;
    }
    return null;
  };

  // ============================================================
  // MAIN REDIRECT LOGIC
  // ============================================================

  const redirect = (target) => {
    if (!target) return;
    if (target === location.href) return;
    console.info("[DDG-Unwrapper] Redirecting to:", target);
    // replace() so the proxy page doesn't sit in history
    location.replace(target);
  };

  const run = () => {
    const real = extractRealUrl(location.href);
    if (real) {
      // If the extracted URL is itself another proxy, keep unwrapping.
      let next = real;
      let hops = 0;
      while (hops++ < 5) {
        const inner = extractRealUrl(next);
        if (!inner || inner === next) break;
        next = inner;
      }
      redirect(next);
      return;
    }

    // Optional: single-image viewer pages -> redirect to the image.
    if (REDIRECT_SINGLE_IMAGE_PAGES) {
      try {
        const imgs = document.querySelectorAll("img");
        if (imgs.length === 1) {
          const src = imgs[0].currentSrc || imgs[0].src || "";
          if (looksLikeImageUrl(src)) {
            redirect(src);
          }
        }
      } catch (_) {}
    }
  };

  // Run at document-start; if DOM not ready yet, re-run on DOMContentLoaded
  // so the optional single-image check has something to look at.
  run();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once: true });
  }

  // Also catch SPA navigations / late redirects.
  window.addEventListener("popstate", run);
  window.addEventListener("hashchange", run);

  ["pushState", "replaceState"].forEach((fn) => {
    const orig = history[fn];
    history[fn] = function (...args) {
      const r = orig.apply(this, args);
      run();
      return r;
    };
  });
})();
