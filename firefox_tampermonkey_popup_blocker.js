// ==UserScript==
// @name         Auto-Close Popup / Ad Tabs
// @namespace    http://tampermonkey.net/
// @version      1.1
// @description  Closes tabs whose domain matches a block list. Runs every second until disabled in the Tampermonkey dashboard.
// @author       You
// @match        *://*/*
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @run-at       document-start
// @icon         https://logodix.com/logo/49412.png
// ==/UserScript==

(function () {
  "use strict";

  // ============================================================
  // CONFIG — edit these
  // ============================================================

  // Exact domains to block. Subdomains are matched too.
  // "ads.example.com" also blocks "x.ads.example.com".
  // Write bare hostnames — no scheme, no trailing slash.
  const BLOCKED_DOMAINS = ["ultimatesurferprotector.com"];

  // Regexes tested against the *hostname* (not the full URL).
  const BLOCKED_REGEXES = [
    // Single random-looking label on a cheap TLD, e.g. "a1b2c3d4.xyz"
    /^[a-z0-9]{6,}\.(xyz|top|club|online|site|live|icu|buzz|click|link|cfd|sbs|rest)$/i,
    // Known ad / popup networks
    /(^|\.)(popads|popcash|propellerads|adcash|exoclick|trafficjunky|onclickads|clickadu|adsterra|revcontent|mgid|taboola|outbrain)\./i,
    // "tracker" style hosts
    /(^|\.)track(er)?\./i,
  ];

  // Flag subdomain labels that look like random codes.
  // This runs only on labels *above* the registrable domain, so
  // "chat.deepseek.com" (label "chat") is safe, but
  // "a1b2c3.tracker.xyz" (label "a1b2c3") is flagged.
  const RANDOM_LABEL_MIN_LEN = 5;

  // How often to sweep, in milliseconds.
  const INTERVAL_MS = 1000;

  // ============================================================
  // INTERNALS
  // ============================================================

  let enabled = GM_getValue("enabled", true);

  // ---------- Hostname normalization ----------

  const normalizeHost = (s) => {
    if (!s) return "";
    try {
      if (/^[a-z]+:\/\//i.test(s)) return new URL(s).hostname.toLowerCase();
      return s.replace(/^\/+|\/+$/g, "").toLowerCase();
    } catch {
      return "";
    }
  };

  const blockedHosts = BLOCKED_DOMAINS.map(normalizeHost).filter(Boolean);

  const hostMatchesList = (hostname) => {
    const h = hostname.toLowerCase();
    return blockedHosts.some((b) => h === b || h.endsWith("." + b));
  };

  // ---------- Randomness heuristic ----------

  // A label is "random-looking" if it's mostly alphanumeric noise:
  //   - long string with no vowels (consonant soup), OR
  //   - mixed letters+digits with at least 2 digits and length >= 5
  // Real subdomains like "chat", "mail", "docs", "api", "static"
  // do not match either rule.
  const looksRandom = (label) => {
    if (!label) return false;
    if (label.length < RANDOM_LABEL_MIN_LEN) return false;

    // Consonant soup: >= 6 chars, no vowels
    if (/^[bcdfghjklmnpqrstvwxz]{6,}$/i.test(label)) return true;

    // Mixed letters+digits with >= 2 digits
    if (/^[a-z0-9]+$/i.test(label)) {
      const digits = (label.match(/\d/g) || []).length;
      const letters = (label.match(/[a-z]/gi) || []).length;
      if (digits >= 2 && letters >= 1) return true;
    }
    return false;
  };

  // Returns true if any subdomain label (i.e. any label above the
  // last two labels) looks random. This avoids flagging the actual
  // registrable domain, only its subdomains.
  const hostnameHasRandomSubdomain = (hostname) => {
    const parts = hostname.split(".");
    if (parts.length < 3) return false;
    const subLabels = parts.slice(0, -2);
    return subLabels.some(looksRandom);
  };

  // ---------- Block decision ----------

  const shouldBlock = (url) => {
    if (!url) return false;
    if (!/^https?:\/\//i.test(url)) return false;

    let hostname;
    try {
      hostname = new URL(url).hostname;
    } catch {
      return false;
    }

    if (hostMatchesList(hostname)) return true;
    if (BLOCKED_REGEXES.some((re) => re.test(hostname))) return true;
    if (hostnameHasRandomSubdomain(hostname)) return true;

    return false;
  };

  // ---------- Closing ----------

  const closeSelfIfBlocked = () => {
    if (!enabled) return;
    if (!shouldBlock(location.href)) return;

    console.warn("[AutoClose] Closing blocked tab:", location.href);

    try {
      window.close();
    } catch (_) {
      /* ignored if not script-opened */
    }

    // Fallback for tabs the browser refuses to close: blank the page.
    setTimeout(() => {
      try {
        document.documentElement.innerHTML = "";
        window.open("", "_self");
        window.close();
      } catch (_) {
        /* ignore */
      }
    }, 50);
  };

  // ---------- window.open interception ----------

  const originalOpen = window.open;
  window.open = function (...args) {
    const child = originalOpen.apply(this, args);
    if (!child || child.closed) return child;

    // Immediate check (works if same-origin or already navigated)
    try {
      const href = child.location && child.location.href;
      if (href && shouldBlock(href)) {
        console.warn("[AutoClose] Closing blocked popup:", href);
        child.close();
        return child;
      }
    } catch (_) {
      /* cross-origin, fall through to polling */
    }

    // Deferred check for cross-origin popups whose URL isn't readable yet
    const start = Date.now();
    const poll = setInterval(() => {
      try {
        if (child.closed || Date.now() - start > 5000) {
          clearInterval(poll);
          return;
        }
        const href = child.location && child.location.href;
        if (href && shouldBlock(href)) {
          console.warn("[AutoClose] Closing blocked popup (deferred):", href);
          child.close();
          clearInterval(poll);
        }
      } catch (_) {
        // Cross-origin: we can never read .location. Give up.
        clearInterval(poll);
      }
    }, 200);

    return child;
  };

  // ---------- Periodic sweep + navigation hooks ----------

  setInterval(closeSelfIfBlocked, INTERVAL_MS);

  closeSelfIfBlocked();
  window.addEventListener("popstate", closeSelfIfBlocked);
  window.addEventListener("hashchange", closeSelfIfBlocked);

  ["pushState", "replaceState"].forEach((fn) => {
    const orig = history[fn];
    history[fn] = function (...args) {
      const r = orig.apply(this, args);
      closeSelfIfBlocked();
      return r;
    };
  });

  // ---------- Dashboard menu toggle ----------

  const refreshMenuLabel = () => {
    GM_registerMenuCommand(
      enabled
        ? "🟢 Auto-Close: ON (click to disable)"
        : "🔴 Auto-Close: OFF (click to enable)",
      () => {
        enabled = !enabled;
        GM_setValue("enabled", enabled);
        // Reload so the menu label refreshes and any already-blanked
        // page gets a fresh chance to load.
        location.reload();
      },
    );
  };

  refreshMenuLabel();

  console.log(
    "[AutoClose] Active. enabled=%s, blockedHosts=%o, regexes=%d",
    enabled,
    blockedHosts,
    BLOCKED_REGEXES.length,
  );
})();
