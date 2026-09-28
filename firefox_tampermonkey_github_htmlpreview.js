// ==UserScript==
// @name         GitHub HTML Preview + Raw Image Button
// @namespace    https://github.com/igiteam
// @version      1.4
// @description  Adds an "HTML" preview button for .html files and a "Raw" button for image files on GitHub. Inserted before the "..." menu button.
// @author       You
// @match        https://github.com/*/blob/*/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=github.com
// @grant        none
// ==/UserScript==

(function () {
  "use strict";

  const LOG = (...a) => console.log("[gh-html-raw]", ...a);

  function getRawUrl() {
    const url = window.location.href;
    return url
      .replace("https://github.com/", "https://raw.githubusercontent.com/")
      .replace("/blob/", "/")
      .split("?")[0];
  }

  function isHtmlFile() {
    return /\/blob\/.*\.html(\?.*)?$/i.test(window.location.href);
  }

  function isImageFile() {
    return /\/blob\/.*\.(png|jpe?g|gif|webp|svg|bmp|ico|avif)(\?.*)?$/i.test(
      window.location.href,
    );
  }

  function styleButton(btn) {
    btn.className = "btn btn-sm";
    btn.style.cssText = `
      display: inline-flex;
      align-items: center;
      gap: 6px;
      margin-right: 8px;
      padding: 3px 12px;
      font-size: 12px;
      font-weight: 600;
      line-height: 20px;
      white-space: nowrap;
      cursor: pointer;
      user-select: none;
      border: 1px solid var(--button-default-borderColor-rest, rgba(31,35,40,0.15));
      border-radius: 6px;
      background-color: var(--button-default-bgColor-rest, #f6f8fa);
      color: var(--fgColor-default, #24292f);
      text-decoration: none;
    `;
    btn.onmouseover = () =>
      (btn.style.backgroundColor =
        "var(--button-default-bgColor-hover, #f3f4f6)");
    btn.onmouseout = () =>
      (btn.style.backgroundColor =
        "var(--button-default-bgColor-rest, #f6f8fa)");
  }

  function makeSvg(pathData) {
    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("width", "16");
    svg.setAttribute("height", "16");
    svg.setAttribute("fill", "currentColor");
    svg.style.verticalAlign = "text-bottom";
    const path = document.createElementNS(svgNS, "path");
    path.setAttribute("d", pathData);
    svg.appendChild(path);
    return svg;
  }

  function createHtmlPreviewButton(rawUrl) {
    const previewUrl = "https://htmlpreview.github.io/?" + rawUrl;
    const btn = document.createElement("a");
    btn.href = previewUrl;
    btn.target = "_blank";
    btn.rel = "noopener noreferrer";
    btn.setAttribute("data-testid", "html-preview-button");
    styleButton(btn);
    btn.appendChild(
      makeSvg(
        "M8 2c3.5 0 6.5 2.5 7.7 5.3.2.4.2.9 0 1.3C14.5 11.5 11.5 14 8 14s-6.5-2.5-7.7-5.3a1.7 1.7 0 0 1 0-1.3C1.5 4.5 4.5 2 8 2Zm0 1.5A6.8 6.8 0 0 0 1.8 8 6.8 6.8 0 0 0 8 12.5 6.8 6.8 0 0 0 14.2 8 6.8 6.8 0 0 0 8 3.5Zm0 1.75a2.75 2.75 0 1 1 0 5.5 2.75 2.75 0 0 1 0-5.5Zm0 1.5a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5Z",
      ),
    );
    const label = document.createElement("span");
    label.textContent = "HTML";
    btn.appendChild(label);
    return btn;
  }

  function createRawButton(rawUrl) {
    const btn = document.createElement("a");
    btn.href = rawUrl;
    btn.target = "_blank";
    btn.rel = "noopener noreferrer";
    btn.setAttribute("data-testid", "raw-image-button");
    btn.title = "Raw";
    styleButton(btn);
    btn.appendChild(
      makeSvg(
        "M2.75 14A1.75 1.75 0 0 1 1 12.25v-2.5a.75.75 0 0 1 1.5 0v2.5c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 1.5 0v2.5A1.75 1.75 0 0 1 13.25 14Zm5.5-6.25V2.75a.75.75 0 0 1 1.5 0v5l1.22-1.22a.75.75 0 1 1 1.06 1.06l-2.5 2.5a.75.75 0 0 1-1.06 0l-2.5-2.5a.75.75 0 1 1 1.06-1.06Z",
      ),
    );
    const label = document.createElement("span");
    label.textContent = "Raw";
    btn.appendChild(label);
    return btn;
  }

  // Try multiple selectors for the "..." menu button
  function findKebabButton() {
    return (
      document.querySelector(
        'button[data-testid^="more-file-actions-button"]',
      ) ||
      document.querySelector(
        'button[data-testid="more-file-actions-button-nav-menu-wide"]',
      ) ||
      document.querySelector(
        'button[data-testid="more-file-actions-button-nav-menu-narrow"]',
      ) ||
      // Fallback: any button whose aria-labelledby contains "More file actions"
      Array.from(document.querySelectorAll("button")).find((b) =>
        /more file actions/i.test(b.getAttribute("aria-label") || ""),
      )
    );
  }

  function injectButtons() {
    const rawUrl = getRawUrl();
    const wantHtml = isHtmlFile();
    const wantRaw = isImageFile();

    LOG("page", window.location.href, { wantHtml, wantRaw });

    if (!wantHtml && !wantRaw) return;

    const haveHtml = !!document.querySelector(
      '[data-testid="html-preview-button"]',
    );
    const haveRaw = !!document.querySelector(
      '[data-testid="raw-image-button"]',
    );
    if ((wantHtml && haveHtml) || (wantRaw && haveRaw)) return;

    const kebab = findKebabButton();
    LOG("kebab?", kebab);

    const parent =
      (kebab && kebab.parentElement) ||
      document.querySelector(
        ".react-code-view-header-element--wide .CodeViewHeader-module__Box_7___0R6c .d-flex",
      ) ||
      document.querySelector(
        ".react-code-view-header-element--narrow .CodeViewHeader-module__Box_7___0R6c .d-flex",
      );

    if (!parent) {
      LOG("no parent found yet");
      return;
    }

    if (wantHtml && !haveHtml) {
      const b = createHtmlPreviewButton(rawUrl);
      kebab ? parent.insertBefore(b, kebab) : parent.appendChild(b);
      LOG("inserted HTML button");
    }

    if (wantRaw && !haveRaw) {
      const b = createRawButton(rawUrl);
      kebab ? parent.insertBefore(b, kebab) : parent.appendChild(b);
      LOG("inserted Raw button");
    }
  }

  // --- Retry loop ---
  let attempts = 0;
  const maxAttempts = 40;

  function tryInject() {
    injectButtons();
    attempts++;
    const wantHtml = isHtmlFile();
    const wantRaw = isImageFile();
    const haveHtml = !!document.querySelector(
      '[data-testid="html-preview-button"]',
    );
    const haveRaw = !!document.querySelector(
      '[data-testid="raw-image-button"]',
    );
    const satisfied = (!wantHtml || haveHtml) && (!wantRaw || haveRaw);
    if (!satisfied && attempts < maxAttempts) {
      setTimeout(tryInject, 500);
    }
  }

  tryInject();

  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      attempts = 0;
      setTimeout(tryInject, 400);
    } else {
      injectButtons();
    }
  }).observe(document.body, { childList: true, subtree: true });
})();
