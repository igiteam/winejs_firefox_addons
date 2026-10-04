// =====================================================
// Treeview for GitHub — content script
// =====================================================
// Full-screen overlay. White GitHub theme.
// Tree rendered as a single <pre> string.
// Two modes:
//   "text"  — plain text, one <pre>, fully selectable & copyable
//   "links" — same layout, each row is an <a> pointing to GitHub
//
// Correct ├─ / └─ / │ glyphs via nested-tree recursion.

(function () {
  const PANEL_ID = "github-treeview-panel";

  const state = {
    open: false,
    owner: null,
    repo: null,
    branch: null,
    files: [],
    cached: false,
    loading: false,
    error: null,
    filter: "",
    collapsed: new Set(),
    selected: new Set(),
    mode: "text"     // "text" | "links"
  };

  // -----------------------------------------------------------
  // Utilities
  // -----------------------------------------------------------
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function fmtSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB";
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GB";
  }

  function githubBlobUrl(f) {
    return `https://github.com/${state.owner}/${state.repo}/blob/${state.branch}/${f.path}`;
  }

  function githubTreeUrl(path) {
    return `https://github.com/${state.owner}/${state.repo}/tree/${state.branch}/${path}`;
  }

  // -----------------------------------------------------------
  // Build a nested tree from the flat file list
  // -----------------------------------------------------------
  function buildTree() {
    const root = { name: "", path: "", isDir: true, children: [] };

    const sorted = [...state.files].sort((a, b) => a.path.localeCompare(b.path));

    for (const f of sorted) {
      const parts = f.path.split("/");
      let node = root;

      for (let i = 0; i < parts.length; i++) {
        const isLast = i === parts.length - 1;
        const name = parts[i];
        const path = parts.slice(0, i + 1).join("/");

        let child = node.children.find(c => c.name === name);
        if (!child) {
          child = {
            name,
            path,
            isDir: !isLast,
            children: [],
            size: isLast ? f.size : 0,
            file: isLast ? f : null
          };
          node.children.push(child);
        }
        node = child;
      }
    }

    return root;
  }

  // -----------------------------------------------------------
  // Flatten the tree to rows with correct ├─/└─/│ glyphs
  // -----------------------------------------------------------
  function flattenRows() {
    const root = buildTree();
    const q = state.filter;
    const rows = [];

    function matchesFilter(n) {
      if (!q) return true;
      if (!n.isDir && n.name.toLowerCase().includes(q)) return true;
      if (n.path.toLowerCase().includes(q)) return true;
      return n.children.some(matchesFilter);
    }

    function visit(node, prefix, isLast, depth) {
      if (q && !matchesFilter(node)) return;

      if (depth >= 0) {
        const branchGlyph = isLast ? "└── " : "├── ";

        rows.push({
          depth,
          name: node.name,
          path: node.path,
          isDir: node.isDir,
          isLast,
          glyphs: prefix + branchGlyph,
          size: node.isDir ? "" : fmtSize(node.size),
          file: node.file,
          collapsed: node.isDir && state.collapsed.has(node.path)
        });
      }

      // If collapsed, don't recurse
      if (node.isDir && state.collapsed.has(node.path) && depth >= 0) {
        return;
      }

      const childPrefix = depth < 0 ? "" : (prefix + (isLast ? "    " : "│   "));
      const children = node.children;
      for (let i = 0; i < children.length; i++) {
        visit(children[i], childPrefix, i === children.length - 1, depth + 1);
      }
    }

    const children = root.children;
    for (let i = 0; i < children.length; i++) {
      visit(children[i], "", i === children.length - 1, 0);
    }

    return rows;
  }

  function badgeString(file) {
    if (!file) return "";
    const parts = [];
    if (file.hasAiTxt)   parts.push("📄");
    if (file.hasPatch)   parts.push("🔧");
    if (file.hasPatchAi) parts.push("✏️");
    return parts.join(" ");
  }

  // -----------------------------------------------------------
  // Render body
  // -----------------------------------------------------------
  function renderBody() {
    const p = getPanel();
    if (!p) return;
    const body = p.querySelector(".gtv-body");

    if (state.loading) {
      body.innerHTML = `<div class="gtv-loading">Loading tree…</div>`;
      return;
    }
    if (state.error) {
      body.innerHTML = `<div class="gtv-error">${escapeHtml(state.error)}</div>`;
      return;
    }
    if (!state.files.length) {
      body.innerHTML = `<div class="gtv-empty">No files</div>`;
      return;
    }

    const rows = flattenRows();
    if (!rows.length) {
      body.innerHTML = `<div class="gtv-empty">No matches</div>`;
      return;
    }

    // Compute padding so the size column aligns
    let maxLen = 0;
    const prepared = rows.map(row => {
      const nameWithSlash = row.isDir ? row.name + "/" : row.name;
      const badges = row.isDir ? "" : badgeString(row.file);
      const leftText = row.glyphs + nameWithSlash + (badges ? "  " + badges : "");
      if (leftText.length > maxLen) maxLen = leftText.length;
      return { row, nameWithSlash, badges, leftText };
    });

    const linesHtml = prepared.map(({ row, nameWithSlash, badges, leftText }) => {
      const pad = " ".repeat(maxLen - leftText.length + 4);
      const sizeText = row.size ? pad + row.size : "";

      const glyphHtml = `<span class="gtv-glyph">${escapeHtml(row.glyphs)}</span>`;
      const nameHtml = row.isDir
        ? `<span class="gtv-dirname">${escapeHtml(nameWithSlash)}</span>`
        : `<span class="gtv-name">${escapeHtml(nameWithSlash)}</span>`;
      const badgeHtml = badges
        ? `  <span class="gtv-badge">${escapeHtml(badges)}</span>`
        : "";
      const sizeHtml = sizeText
        ? `<span class="gtv-size">${escapeHtml(sizeText)}</span>`
        : "";

      const inner = glyphHtml + nameHtml + badgeHtml + sizeHtml;

      if (state.mode === "links") {
        const href = row.isDir ? githubTreeUrl(row.path) : githubBlobUrl(row.file);
        return `<a class="gtv-line" ` +
          `href="${escapeHtml(href)}" ` +
          `data-path="${escapeHtml(row.path)}" ` +
          `data-kind="${row.isDir ? "dir" : "file"}" ` +
          (row.isDir ? `` : `target="_blank" rel="noopener noreferrer"`) +
          `>${inner}</a>`;
      } else {
        return `<span class="gtv-line" ` +
          `data-path="${escapeHtml(row.path)}" ` +
          `data-kind="${row.isDir ? "dir" : "file"}"` +
          `>${inner}</span>`;
      }
    });

    body.innerHTML = `<pre class="gtv-pre">${linesHtml.join("\n")}</pre>`;

    // Wire interactions
    body.querySelectorAll(".gtv-line").forEach(el => {
      const kind = el.dataset.kind;
      const path = el.dataset.path;

      if (kind === "dir") {
        el.addEventListener("click", (e) => {
          e.preventDefault();
          if (state.collapsed.has(path)) state.collapsed.delete(path);
          else state.collapsed.add(path);
          renderBody();
        });
      } else {
        el.addEventListener("click", (e) => {
          if (e.ctrlKey || e.metaKey) {
            e.preventDefault();
            if (state.selected.has(path)) state.selected.delete(path);
            else state.selected.add(path);
            renderBody();
            renderFooter();
          }
        });

        el.addEventListener("contextmenu", (e) => {
          e.preventDefault();
          copyToClipboard(path);
          flashRow(el, "path copied");
        });
      }
    });
  }

  // -----------------------------------------------------------
  // Panel
  // -----------------------------------------------------------
  function buildPanel() {
    const panel = document.createElement("div");
    panel.id = PANEL_ID;
    panel.innerHTML = `
      <div class="gtv-header">
        <span class="gtv-icon">🌲</span>
        <span class="gtv-title">repo tree</span>
        <span class="gtv-stats"></span>
        <span class="gtv-spacer"></span>
        <button class="gtv-btn" data-act="refresh" title="Re-fetch tree">↻</button>
        <button class="gtv-btn" data-act="close" title="Close (Esc)">×</button>
      </div>
      <div class="gtv-toolbar">
        <input type="text" class="gtv-filter" placeholder="filter paths..." spellcheck="false">
        <button class="gtv-btn gtv-btn-txt" data-act="expand-all" title="Expand all">⤢ expand</button>
        <button class="gtv-btn gtv-btn-txt" data-act="collapse-all" title="Collapse all">⤡ collapse</button>
        <span class="gtv-spacer"></span>
        <button class="gtv-btn gtv-btn-txt gtv-btn-active" data-act="mode-text" title="Plain string, copyable">📄 string</button>
        <button class="gtv-btn gtv-btn-txt" data-act="mode-links" title="Same layout, clickable rows">🔗 links</button>
      </div>
      <div class="gtv-body">
        <div class="gtv-loading">Loading tree…</div>
      </div>
      <div class="gtv-footer">
        <span class="gtv-sel-info">0 selected</span>
        <span class="gtv-spacer"></span>
        <button class="gtv-btn gtv-btn-txt" data-act="copy-rag" disabled>🔗 RAG link</button>
        <button class="gtv-btn gtv-btn-txt" data-act="copy-paths" disabled>📋 Copy paths</button>
        <button class="gtv-btn gtv-btn-txt" data-act="copy-tree" title="Copy the tree as plain text">📄 Copy tree</button>
        <button class="gtv-btn gtv-btn-txt" data-act="save-json" disabled>💾 JSON</button>
      </div>
    `;
    document.body.appendChild(panel);

    panel.querySelector(".gtv-filter").addEventListener("input", (e) => {
      state.filter = e.target.value.trim().toLowerCase();
      renderBody();
    });

    panel.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-act]");
      if (!btn) return;
      const act = btn.dataset.act;
      if (act === "close") return closePanel();
      if (act === "refresh") return refresh(true);
      if (act === "expand-all") { state.collapsed.clear(); renderBody(); return; }
      if (act === "collapse-all") { collapseAll(); renderBody(); return; }
      if (act === "mode-text") { state.mode = "text"; renderModeButtons(); renderBody(); return; }
      if (act === "mode-links") { state.mode = "links"; renderModeButtons(); renderBody(); return; }
      if (act === "copy-rag") return copyRagLink();
      if (act === "copy-paths") return copySelectedPaths();
      if (act === "copy-tree") return copyTreeAsText();
      if (act === "save-json") return saveJson();
    });

    return panel;
  }

  function renderModeButtons() {
    const p = getPanel();
    if (!p) return;
    const textBtn  = p.querySelector('[data-act="mode-text"]');
    const linksBtn = p.querySelector('[data-act="mode-links"]');
    if (state.mode === "text") {
      textBtn.classList.add("gtv-btn-active");
      linksBtn.classList.remove("gtv-btn-active");
    } else {
      linksBtn.classList.add("gtv-btn-active");
      textBtn.classList.remove("gtv-btn-active");
    }
  }

  function collapseAll() {
    const dirs = new Set();
    for (const f of state.files) {
      const parts = f.path.split("/");
      let acc = "";
      for (let i = 0; i < parts.length - 1; i++) {
        acc = acc ? acc + "/" + parts[i] : parts[i];
        dirs.add(acc);
      }
    }
    state.collapsed = dirs;
  }

  function getPanel() { return document.getElementById(PANEL_ID); }

  function closePanel() {
    const p = getPanel();
    if (p) p.remove();
    state.open = false;
  }

  function renderHeader() {
    const p = getPanel();
    if (!p) return;
    const stats = p.querySelector(".gtv-stats");
    const title = p.querySelector(".gtv-title");
    if (!state.owner) {
      stats.textContent = "";
      title.textContent = "repo tree";
      return;
    }
    title.textContent = `${state.owner}/${state.repo}@${state.branch}`;
    const total = state.files.length;
    const ai = state.files.filter(f => f.hasAiTxt).length;
    const patch = state.files.filter(f => f.hasPatch).length;
    stats.textContent = ` · ${total} files · 📄 ${ai} · 🔧 ${patch}` + (state.cached ? " · cached" : "");
  }

  function renderFooter() {
    const p = getPanel();
    if (!p) return;
    const info = p.querySelector(".gtv-sel-info");
    const n = state.selected.size;
    info.textContent = n + " selected";
    p.querySelector('[data-act="copy-rag"]').disabled = n === 0;
    p.querySelector('[data-act="copy-paths"]').disabled = n === 0;
    p.querySelector('[data-act="save-json"]').disabled = state.files.length === 0;
    const ct = p.querySelector('[data-act="copy-tree"]');
    if (ct) ct.disabled = state.files.length === 0;
  }

  function flashRow(el, msg) {
    const note = document.createElement("span");
    note.className = "gtv-flash";
    note.textContent = " " + msg;
    el.appendChild(note);
    setTimeout(() => note.remove(), 900);
  }

  // -----------------------------------------------------------
  // Clipboard / export
  // -----------------------------------------------------------
  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const ta = document.createElement("textarea");
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      ta.remove();
    }
  }

  async function copySelectedPaths() {
    const paths = [...state.selected].sort().join("\n");
    await copyToClipboard(paths);
    showToast(`Copied ${state.selected.size} paths`);
  }

  async function copyRagLink() {
    const base = "https://rag.songdrop.band/?";
    const params = [];
    for (const path of state.selected) {
      const f = state.files.find(x => x.path === path);
      if (!f) continue;
      const targetPath = f.hasAiTxt ? path + "-ai.txt" : path;
      const raw = `https://raw.githubusercontent.com/${state.owner}/${state.repo}/${state.branch}/${targetPath}`;
      params.push("url=" + encodeURIComponent(raw));
    }
    if (state.selected.size > 2) params.push("deep=1");
    const link = base + params.join("&");
    await copyToClipboard(link);
    showToast(`RAG link copied (${state.selected.size} files)`);
  }

  // Copy the entire tree as one plain-text string — exactly what
  // `tree` prints on the command line, byte for byte.
  async function copyTreeAsText() {
    const rows = flattenRows();
    let maxLen = 0;
    const prepared = rows.map(row => {
      const nameWithSlash = row.isDir ? row.name + "/" : row.name;
      const badges = row.isDir ? "" : badgeString(row.file);
      const left = row.glyphs + nameWithSlash + (badges ? "  " + badges : "");
      if (left.length > maxLen) maxLen = left.length;
      return { row, left };
    });

    const lines = prepared.map(({ row, left }) => {
      const pad = row.size ? " ".repeat(Math.max(0, maxLen - left.length + 4)) : "";
      return left + pad + (row.size || "");
    });

    const header = `${state.owner}/${state.repo}@${state.branch}\n\n`;
    const text = header + lines.join("\n");
    await copyToClipboard(text);
    showToast(`Copied ${rows.length}-line tree`);
  }

  function saveJson() {
    const payload = {
      owner: state.owner,
      repo: state.repo,
      branch: state.branch,
      fetchedAt: new Date().toISOString(),
      total_files: state.files.length,
      files: state.files
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${state.repo}-tree.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    showToast("Saved JSON");
  }

  function showToast(msg) {
    let t = document.getElementById("gtv-toast");
    if (!t) {
      t = document.createElement("div");
      t.id = "gtv-toast";
      t.className = "gtv-toast";
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add("visible");
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove("visible"), 1800);
  }

  // -----------------------------------------------------------
  // Data flow
  // -----------------------------------------------------------
  async function refresh(forceRefresh) {
    const p = getPanel();
    if (!p) return;
    state.loading = true;
    state.error = null;
    renderBody();

    const resp = await browser.runtime.sendMessage({
      type: "treeview:build",
      forceRefresh: !!forceRefresh
    });

    if (!resp || !resp.ok) {
      state.loading = false;
      state.error = (resp && resp.error) || "Failed to load tree";
      renderBody();
      renderHeader();
      renderFooter();
      return;
    }

    state.owner = resp.result.owner;
    state.repo = resp.result.repo;
    state.branch = resp.result.branch;
    state.files = resp.result.files || [];
    state.cached = !!resp.result.cached;
    state.loading = false;
    state.collapsed.clear();

    renderHeader();
    renderBody();
    renderFooter();
    renderModeButtons();
  }

  function openPanel() {
    if (!getPanel()) buildPanel();
    state.open = true;
    if (!state.files.length) refresh(false);
  }

  function togglePanel() {
    if (getPanel()) closePanel();
    else openPanel();
  }

  // -----------------------------------------------------------
  // Messages
  // -----------------------------------------------------------
  browser.runtime.onMessage.addListener((msg) => {
    if (!msg) return;
    if (msg.type === "treeview:toggle") togglePanel();
    else if (msg.type === "treeview:show-toast") showToast(msg.message || "");
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && getPanel()) { closePanel(); return; }
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === "t") {
      e.preventDefault();
      togglePanel();
    }
  });

})();
