// ==UserScript==
// @name         DeepSeek Chat → Save as PDF / HTML / Text
// @namespace    https://github.com/your-name/deepseek-export
// @version      2.2.0
// @description  Export DeepSeek chat as PDF / HTML / Text. Scrolls top to bottom to load the whole virtual list.
// @author       You
// @match        https://chat.deepseek.com/*
// @grant        none
// @run-at       document-end
// @icon         https://www.google.com/s2/favicons?sz=64&domain=deepseek.com
// ==/UserScript==

(function () {
  "use strict";

  const SCROLL_STEP_PX = 500;
  const SCROLL_STEP_DELAY = 250;
  const SCROLL_SETTLE_DELAY = 700;
  const MAX_SCROLL_STEPS = 600;

  // ============================================================
  //  UI
  // ============================================================
  function addPanel() {
    if (document.getElementById("ds-export-panel")) return;

    const panel = document.createElement("div");
    panel.id = "ds-export-panel";
    panel.style.cssText = `
            position: fixed; bottom: 24px; right: 24px; z-index: 99999;
            display: flex; flex-direction: column; gap: 8px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        `;

    const makeBtn = (label, color, hover, handler) => {
      const btn = document.createElement("button");
      btn.textContent = label;
      btn.style.cssText = `
                padding: 10px 18px; background: ${color}; color: #fff;
                border: none; border-radius: 8px; font-size: 13px;
                font-weight: 600; cursor: pointer;
                box-shadow: 0 4px 12px rgba(0,0,0,0.25);
                transition: background 0.2s, transform 0.1s;
                white-space: nowrap;
            `;
      btn.addEventListener("mouseenter", () => (btn.style.background = hover));
      btn.addEventListener("mouseleave", () => (btn.style.background = color));
      btn.addEventListener(
        "mousedown",
        () => (btn.style.transform = "scale(0.96)"),
      );
      btn.addEventListener("mouseup", () => (btn.style.transform = "scale(1)"));
      btn.addEventListener("click", handler);
      return btn;
    };

    const status = document.createElement("div");
    status.id = "ds-export-status";
    status.style.cssText = `
            font-size: 11px; color: #6b7280; text-align: right;
            padding-right: 2px; min-height: 14px;
        `;

    panel.appendChild(
      makeBtn("📄 Save as PDF", "#4f46e5", "#4338ca", () => runExport("pdf")),
    );
    panel.appendChild(
      makeBtn("🌐 Save as HTML", "#0891b2", "#0e7490", () => runExport("html")),
    );
    panel.appendChild(
      makeBtn("📝 Save as Text", "#059669", "#047857", () => runExport("text")),
    );
    panel.appendChild(status);

    document.body.appendChild(panel);
  }

  function setStatus(msg, isError = false) {
    const el = document.getElementById("ds-export-status");
    if (!el) return;
    el.textContent = msg;
    el.style.color = isError ? "#dc2626" : "#6b7280";
  }

  // ============================================================
  //  SCROLLER — same selector as v2.0 (this one worked)
  // ============================================================
  function getScroller() {
    return (
      document.querySelector(".ds-virtual-list.ds-scroll-area") ||
      document.querySelector(".ds-virtual-list") ||
      document.querySelector(".ds-scroll-area")
    );
  }

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  function getMessageCount() {
    const c = document.querySelector(".ds-virtual-list-items");
    if (!c) return 0;
    return c.querySelectorAll("[data-virtual-list-item-key]").length;
  }

  // ============================================================
  //  SCROLL TOP → BOTTOM
  // ============================================================
  async function scrollTopToBottom(onProgress) {
    const scroller = getScroller();
    if (!scroller) {
      console.warn("[Export] No scroller.");
      return;
    }

    // 1. Jump to top
    scroller.scrollTop = 0;
    await sleep(SCROLL_SETTLE_DELAY);

    // 2. Step down
    let steps = 0;
    let lastTop = -1;
    let noMoveRounds = 0;

    while (steps < MAX_SCROLL_STEPS) {
      steps++;

      const top = scroller.scrollTop;
      const maxTop = scroller.scrollHeight - scroller.clientHeight;
      const count = getMessageCount();
      const atBottom = top >= maxTop - 2;

      if (onProgress) onProgress(count);

      // No movement for 3 rounds → give up
      if (top === lastTop) {
        noMoveRounds++;
        if (noMoveRounds >= 3) break;
      } else {
        noMoveRounds = 0;
        lastTop = top;
      }

      if (atBottom) {
        // wait a little so the last items render
        await sleep(SCROLL_STEP_DELAY * 2);
        break;
      }

      // scroll down one step
      const next = Math.min(top + SCROLL_STEP_PX, maxTop);
      scroller.scrollTop = next;

      // Some frameworks need a native scroll event to update
      scroller.dispatchEvent(new Event("scroll", { bubbles: true }));

      await sleep(SCROLL_STEP_DELAY);
    }

    // 3. Final settle
    await sleep(SCROLL_SETTLE_DELAY);
    if (onProgress) onProgress(getMessageCount());
  }

  // ============================================================
  //  COLLECT
  // ============================================================
  function collectMessages() {
    const container = document.querySelector(".ds-virtual-list-items");
    if (!container) return [];

    const items = container.querySelectorAll("[data-virtual-list-item-key]");
    const messages = [];

    items.forEach((item) => {
      const key = item.getAttribute("data-virtual-list-item-key");
      const msgEl = item.querySelector(".ds-message");
      if (!msgEl) return;

      let role = "unknown";
      if (msgEl.querySelector(".ds-assistant-message-main-content")) {
        role = "assistant";
      } else if (
        msgEl.querySelector(".fbb737a4") ||
        msgEl.querySelector(".d29f3d7d")
      ) {
        role = "user";
      } else if (msgEl.querySelector(".ds-markdown")) {
        role = "assistant";
      } else {
        role = "user";
      }

      const clone = msgEl.cloneNode(true);

      clone
        .querySelectorAll(
          'button, [role="button"], svg, .ds-button, .ds-flex, ' +
            ".ds-scroll-area__gutters, ._11d6b3a, ._425ea0b, ._78e0558, " +
            "._0a3d93b, ._965abe9, .db183363, .d4910adc, .f79352dc, " +
            ".ds-toggle-button, ._58b31c9, .bf38813a, .f02f0e25, " +
            ".md-code-block-banner-wrap, .md-code-block-banner, " +
            "._121d384, .d2a24f03, .efa13877, ._64bb515",
        )
        .forEach((el) => el.remove());

      clone.querySelectorAll("svg").forEach((el) => el.remove());
      clone.querySelectorAll("div:empty").forEach((el) => {
        const cls = el.className;
        if (typeof cls === "string" && cls.includes("button")) el.remove();
      });

      let contentHtml = clone.innerHTML;
      let contentText = clone.innerText || clone.textContent || "";

      if (role === "user") {
        const u = clone.querySelector(
          ".fbb737a4, .ds-collapsible-text, .d29f3d7d",
        );
        if (u) {
          contentHtml = u.innerHTML;
          contentText = u.innerText || u.textContent || "";
        }
      }
      if (role === "assistant") {
        const m = clone.querySelector(".ds-markdown");
        if (m) {
          contentHtml = m.innerHTML;
          contentText = m.innerText || m.textContent || "";
        }
      }

      messages.push({ key, role, html: contentHtml, text: contentText.trim() });
    });

    // dedupe by key
    const seen = new Set();
    const unique = [];
    messages.forEach((m) => {
      if (seen.has(m.key)) return;
      seen.add(m.key);
      unique.push(m);
    });

    unique.sort((a, b) => {
      const ka = parseInt(a.key, 10);
      const kb = parseInt(b.key, 10);
      if (!isNaN(ka) && !isNaN(kb)) return ka - kb;
      return String(a.key).localeCompare(String(b.key));
    });

    return unique;
  }

  // ============================================================
  //  OUTPUT
  // ============================================================
  const SHARED_STYLE = `
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                font-size: 14px; line-height: 1.6; color: #1a1a1a;
                background: #fff; margin: 0; padding: 20px 24px;
                max-width: 900px; margin-left: auto; margin-right: auto;
            }
            .header { text-align: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 2px solid #e5e7eb; }
            .header h1 { font-size: 20px; margin: 0 0 4px 0; color: #111; }
            .header .meta { font-size: 12px; color: #6b7280; }
            .message { margin-bottom: 20px; page-break-inside: avoid; }
            .message.user { padding-left: 12px; border-left: 4px solid #4f46e5; }
            .message.assistant { padding-left: 12px; border-left: 4px solid #10b981; }
            .message .role-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; }
            .message.user .role-label { color: #4f46e5; }
            .message.assistant .role-label { color: #10b981; }
            .message .content { word-wrap: break-word; overflow-wrap: break-word; }
            .message .content p { margin: 0 0 8px 0; }
            .message .content p:last-child { margin-bottom: 0; }
            .message .content ul, .message .content ol { margin: 4px 0 8px 0; padding-left: 24px; }
            .message .content li { margin-bottom: 2px; }
            .message .content code {
                background: #f3f4f6; padding: 1px 5px; border-radius: 4px;
                font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                font-size: 12.5px; color: #1f2937;
            }
            .message .content pre {
                background: #f8f9fa; border: 1px solid #e5e7eb; border-radius: 6px;
                padding: 12px 14px; overflow-x: auto;
                font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                font-size: 12.5px; line-height: 1.5;
                white-space: pre-wrap; word-break: break-word; margin: 8px 0;
            }
            .message .content pre code { background: none; padding: 0; font-size: inherit; }
            .message .content blockquote { border-left: 3px solid #d1d5db; margin: 8px 0; padding: 4px 12px; color: #4b5563; }
            .message .content table { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 13px; }
            .message .content th, .message .content td { border: 1px solid #d1d5db; padding: 6px 10px; text-align: left; }
            .message .content th { background: #f3f4f6; font-weight: 600; }
            .message .content img { max-width: 100%; height: auto; }
            .message .content hr { border: none; border-top: 1px solid #e5e7eb; margin: 12px 0; }
            @media print {
                body { padding: 0; }
                .message { page-break-inside: avoid; }
                .message .content pre { border-color: #ccc; background: #fafafa; }
                .message .content code { background: #eee; }
            }
        </style>
    `;

  function buildHeader(messages) {
    const now = new Date();
    const dateStr = now.toLocaleDateString("en-GB", {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
    return `<div class="header"><h1>DeepSeek Chat Export</h1>
                <div class="meta">${dateStr} · ${messages.length} messages</div></div>`;
  }

  function buildHtml(messages) {
    let body = "";
    messages.forEach((msg) => {
      const roleLabel =
        msg.role === "user"
          ? "You"
          : msg.role === "assistant"
            ? "DeepSeek"
            : "Message";
      const roleClass = msg.role === "user" ? "user" : "assistant";
      let content = msg.html;
      if (!content && msg.text)
        content = `<p>${escapeHtml(msg.text).replace(/\n/g, "<br>")}</p>`;
      body += `<div class="message ${roleClass}">
                        <div class="role-label">${roleLabel}</div>
                        <div class="content">${content}</div>
                     </div>`;
    });
    return `<!DOCTYPE html><html><head><meta charset="utf-8">
                <title>DeepSeek Chat Export</title>${SHARED_STYLE}</head>
                <body>${buildHeader(messages)}${body}</body></html>`;
  }

  function buildText(messages) {
    const now = new Date();
    const dateStr = now.toLocaleDateString("en-GB", {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
    let out = `DeepSeek Chat Export\n${dateStr} · ${messages.length} messages\n`;
    out += "=".repeat(60) + "\n\n";
    messages.forEach((msg) => {
      const roleLabel =
        msg.role === "user"
          ? "You"
          : msg.role === "assistant"
            ? "DeepSeek"
            : "Message";
      out += `--- ${roleLabel} ---\n${msg.text || "(empty)"}\n\n`;
    });
    return out;
  }

  function escapeHtml(text) {
    const d = document.createElement("div");
    d.textContent = text;
    return d.innerHTML;
  }

  // ============================================================
  //  DOWNLOAD
  // ============================================================
  function downloadBlob(content, filename, mime) {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  }

  function timestamp() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, "0");
    return (
      d.getFullYear() +
      pad(d.getMonth() + 1) +
      pad(d.getDate()) +
      "-" +
      pad(d.getHours()) +
      pad(d.getMinutes()) +
      pad(d.getSeconds())
    );
  }

  // ============================================================
  //  MAIN EXPORT
  // ============================================================
  let busy = false;

  async function runExport(format) {
    if (busy) return;
    busy = true;

    try {
      setStatus("Scrolling to top…");
      await scrollTopToBottom((count) =>
        setStatus(`Scrolling… (${count} messages rendered)`),
      );

      setStatus("Collecting messages…");
      const messages = collectMessages();

      if (!messages.length) {
        setStatus("No messages found.", true);
        alert("No messages found to export.");
        return;
      }

      setStatus(`Exporting ${messages.length} messages…`);

      if (format === "html") {
        downloadBlob(
          buildHtml(messages),
          `deepseek-chat-${timestamp()}.html`,
          "text/html;charset=utf-8",
        );
        setStatus(`Saved HTML (${messages.length} messages)`);
        setTimeout(() => setStatus(""), 4000);
      } else if (format === "text") {
        downloadBlob(
          buildText(messages),
          `deepseek-chat-${timestamp()}.txt`,
          "text/plain;charset=utf-8",
        );
        setStatus(`Saved text (${messages.length} messages)`);
        setTimeout(() => setStatus(""), 4000);
      } else if (format === "pdf") {
        const printWindow = window.open(
          "",
          "_blank",
          "width=900,height=700,menubar=yes,scrollbars=yes",
        );
        if (!printWindow) {
          setStatus("Pop-up blocked.", true);
          alert("Please allow pop-ups for this site to export as PDF.");
          return;
        }
        printWindow.document.open();
        printWindow.document.write(buildHtml(messages));
        printWindow.document.close();

        const triggerPrint = () => {
          try {
            printWindow.focus();
            printWindow.print();
          } catch (e) {
            console.warn("[Export] print error:", e);
          }
        };
        printWindow.onload = () => setTimeout(triggerPrint, 700);
        setTimeout(triggerPrint, 1500);

        setStatus('Print dialog opened — choose "Save as PDF".');
        setTimeout(() => setStatus(""), 5000);
      }
    } catch (err) {
      console.error("[Export] error:", err);
      setStatus("Export failed — see console.", true);
    } finally {
      busy = false;
    }
  }

  // ============================================================
  //  SPA OBSERVER
  // ============================================================
  function observePageChanges() {
    const observer = new MutationObserver(() => {
      if (document.querySelector(".ds-virtual-list-items")) addPanel();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    setTimeout(addPanel, 1500);
  }

  function init() {
    if (
      document.readyState === "complete" ||
      document.readyState === "interactive"
    ) {
      setTimeout(observePageChanges, 800);
    } else {
      window.addEventListener("DOMContentLoaded", () =>
        setTimeout(observePageChanges, 800),
      );
    }
  }

  init();
})();
