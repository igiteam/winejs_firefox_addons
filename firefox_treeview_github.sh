#!/bin/bash

# ===============================================
# Treeview for GitHub - Firefox Addon Generator
# Toolbar button + right-click → full-screen treeview of any GitHub repo
# Two render modes: clickable links, or plain text <pre> (single string)
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                Treeview for GitHub - Firefox Addon                        ║"
echo "║   Full-screen. White GitHub theme. String + clickable links.              ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Enter your extension folder name (default: github-treeview): " EXTNAME
EXTNAME=${EXTNAME:-github-treeview}

if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        rm -rf "$EXTNAME"
    else
        exit 1
    fi
fi

mkdir -p "$EXTNAME/icons"
cd "$EXTNAME" || exit

# ---------------------------------------------------------------
# Icons
# ---------------------------------------------------------------
echo -e "${CYAN}📥 Downloading icon...${NC}"
curl -sL -o icons/tree.png "https://getdrawings.com/icon-images/tree-icon-20.png" || true

if [ ! -s icons/tree.png ]; then
    echo -e "${YELLOW}⚠ Icon download failed — using fallback SVG${NC}"
    cat > icons/tree.svg << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#0f172a"/>
  <path d="M32 8 L20 24 L26 24 L26 34 L20 34 L32 48 L44 34 L38 34 L38 24 L44 24 Z"
        fill="#22c55e" stroke="#16a34a" stroke-width="1.5" stroke-linejoin="round"/>
  <rect x="29" y="48" width="6" height="8" fill="#78350f"/>
</svg>
SVGEOF
    cp icons/tree.svg icons/tree.png 2>/dev/null || true
fi

cp icons/tree.png icons/tree128.png 2>/dev/null || true

# ---------------------------------------------------------------
# manifest.json
# ---------------------------------------------------------------
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "Treeview for GitHub",
  "version": "1.3.0",
  "description": "Full-screen treeview of any GitHub repo. White GitHub theme. String (copyable) and clickable links modes. Badges for -ai.txt and .patch siblings.",
  "icons": {
    "48": "icons/tree.png",
    "128": "icons/tree128.png"
  },
  "permissions": [
    "menus",
    "contextMenus",
    "activeTab",
    "tabs",
    "storage",
    "https://api.github.com/*",
    "https://raw.githubusercontent.com/*",
    "https://github.com/*"
  ],
  "browser_action": {
    "default_icon": "icons/tree.png",
    "default_title": "Show repo tree"
  },
  "background": {
    "scripts": ["background.js"]
  },
  "content_scripts": [
    {
      "matches": ["https://github.com/*"],
      "js": ["content.js"],
      "css": ["treeview.css"],
      "run_at": "document_idle"
    }
  ],
  "browser_specific_settings": {
    "gecko": {
      "id": "github-treeview@custom.addon",
      "strict_min_version": "78.0"
    }
  }
}
EOL

# ---------------------------------------------------------------
# background.js
# ---------------------------------------------------------------
cat << 'EOL' > background.js
// =====================================================
// Treeview for GitHub — background script
// =====================================================

const TREE_TTL_MS = 60 * 60 * 1000; // 1 hour

function parseRepoFromUrl(rawUrl) {
  try {
    const u = new URL(rawUrl);
    if (u.hostname !== "github.com") return null;

    const parts = u.pathname.split("/").filter(Boolean);
    if (parts.length < 2) return null;

    const owner = parts[0];
    const repo = parts[1];

    const reserved = new Set([
      "settings", "notifications", "explore", "marketplace",
      "pulls", "issues", "sponsors", "topics", "collections",
      "trending", "new", "login", "logout", "join", "about"
    ]);
    if (reserved.has(owner)) return null;

    let branch = null;
    const blobIdx = parts.indexOf("blob");
    const treeIdx = parts.indexOf("tree");
    if (blobIdx > 1 && parts[blobIdx + 1]) branch = parts[blobIdx + 1];
    else if (treeIdx > 1 && parts[treeIdx + 1]) branch = parts[treeIdx + 1];

    return { owner, repo, branch };
  } catch {
    return null;
  }
}

async function getDefaultBranch(owner, repo) {
  const res = await fetch(`https://api.github.com/repos/${owner}/${repo}`, {
    headers: { "Accept": "application/vnd.github+json" }
  });
  if (!res.ok) {
    const err = new Error(res.status === 404 ? "Repository not found" :
                          res.status === 403 ? "GitHub rate limit reached" :
                          `GitHub HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  const data = await res.json();
  return data.default_branch || "main";
}

async function fetchTree(owner, repo, branch) {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/git/trees/${encodeURIComponent(branch)}?recursive=1`,
    { headers: { "Accept": "application/vnd.github+json" } }
  );
  if (!res.ok) {
    const err = new Error(res.status === 403 ? "GitHub rate limit reached" :
                          res.status === 404 ? `Branch "${branch}" not found` :
                          `GitHub HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

function analyseTree(treeData) {
  const blobs = treeData.tree.filter(t => t.type === "blob");

  const hasAiTxt   = new Set();
  const hasPatch   = new Set();
  const hasPatchAi = new Set();

  for (const b of blobs) {
    if (b.path.endsWith(".patch-ai.txt")) {
      hasPatchAi.add(b.path.replace(/\.patch-ai\.txt$/, ""));
    } else if (b.path.endsWith("-ai.txt")) {
      hasAiTxt.add(b.path.replace(/-ai\.txt$/, ""));
    } else if (b.path.endsWith(".patch")) {
      hasPatch.add(b.path.replace(/\.patch$/, ""));
    }
  }

  const files = blobs.map(b => ({
    path: b.path,
    size: b.size || 0,
    sha: b.sha,
    hasAiTxt: hasAiTxt.has(b.path),
    hasPatch: hasPatch.has(b.path),
    hasPatchAi: hasPatchAi.has(b.path)
  }));

  return {
    truncated: !!treeData.truncated,
    treeSha: treeData.sha,
    files
  };
}

async function getCached(owner, repo, branch) {
  const key = `tree:${owner}/${repo}@${branch}`;
  const r = await browser.storage.local.get(key);
  const entry = r[key];
  if (!entry) return null;
  if (Date.now() - entry.fetchedAt > TREE_TTL_MS) return null;
  return entry;
}

async function setCached(owner, repo, branch, data) {
  const key = `tree:${owner}/${repo}@${branch}`;
  await browser.storage.local.set({
    [key]: { fetchedAt: Date.now(), data }
  });
}

async function buildTreeForTab(tab, forceRefresh) {
  const parsed = parseRepoFromUrl(tab && tab.url);
  if (!parsed) throw new Error("Not a GitHub repository page");
  const { owner, repo } = parsed;
  let { branch } = parsed;
  if (!branch) branch = await getDefaultBranch(owner, repo);

  if (!forceRefresh) {
    const cached = await getCached(owner, repo, branch);
    if (cached) return { owner, repo, branch, ...cached.data, cached: true };
  }

  const treeData = await fetchTree(owner, repo, branch);
  const analysed = analyseTree(treeData);
  await setCached(owner, repo, branch, analysed);
  return { owner, repo, branch, ...analysed, cached: false };
}

browser.runtime.onMessage.addListener(async (msg, sender) => {
  if (!msg || msg.type !== "treeview:build") return;

  let tab = sender && sender.tab;
  if (!tab && msg.tabId) {
    try { tab = await browser.tabs.get(msg.tabId); } catch { tab = null; }
  }
  if (!tab) return { ok: false, error: "No tab context" };

  try {
    const result = await buildTreeForTab(tab, !!msg.forceRefresh);
    return { ok: true, result };
  } catch (e) {
    return { ok: false, error: e.message, status: e.status || null };
  }
});

browser.browserAction.onClicked.addListener(async (tab) => {
  try {
    const parsed = parseRepoFromUrl(tab && tab.url);
    if (!parsed) {
      await browser.tabs.sendMessage(tab.id, {
        type: "treeview:show-toast",
        message: "Not a GitHub repository page"
      }).catch(() => {});
      return;
    }
    await browser.tabs.sendMessage(tab.id, { type: "treeview:toggle" })
      .catch(() => {});
  } catch (e) {
    console.error("[treeview] toolbar click failed:", e);
  }
});

browser.contextMenus.create({
  id: "treeview-show",
  title: "Show repo tree",
  contexts: ["page", "link"],
  documentUrlPatterns: ["https://github.com/*"]
});

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "treeview-show") return;
  if (!tab) return;
  await browser.tabs.sendMessage(tab.id, { type: "treeview:toggle" })
    .catch(() => {});
});
EOL

# ---------------------------------------------------------------
# content.js
# ---------------------------------------------------------------
cat << 'EOL' > content.js
// =====================================================
// Treeview for GitHub — content script
// =====================================================
// Full-screen overlay. White GitHub theme.
// Tree rendered as a single <pre> string.
// Two modes:
//   "text"  — plain text, one <pre>, fully selectable & copyable
//   "links" — same layout, each row is an <a> pointing to GitHub
//
// Single header bar with: repo@branch · stats · filter · expand ·
// collapse · string/links mode · copy tree · JSON · refresh · close.
// No footer. Body scrolls. Print-friendly.

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
      body.innerHTML = `<div class="gtv-loading">Loading…</div>`;
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

    // Rows are display:block, so no \n join — that would double-space.
    const titleLine = state.owner
      ? `<span class="gtv-titleline">${escapeHtml(state.owner + "/" + state.repo + "@" + state.branch)}</span>\n`
      : "";
    body.innerHTML = `<pre class="gtv-pre">${titleLine}${linesHtml.join("")}</pre>`;

    // Wire interactions (directories toggle collapse)
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
        el.addEventListener("contextmenu", (e) => {
          e.preventDefault();
          copyToClipboard(path);
          flashRow(el, "path copied");
        });
      }
    });
  }

  // -----------------------------------------------------------
  // Panel — single header bar, everything in it. No footer.
  // -----------------------------------------------------------
  function buildPanel() {
    const panel = document.createElement("div");
    panel.id = PANEL_ID;
    panel.innerHTML = `
      <div class="gtv-header">
        <span class="gtv-title"></span>
        <span class="gtv-stats"></span>
        <input type="text" class="gtv-filter" placeholder="filter paths..." spellcheck="false">
        <button class="gtv-btn" data-act="expand-all" title="Expand all">⤢</button>
        <button class="gtv-btn" data-act="collapse-all" title="Collapse all">⤡</button>
        <button class="gtv-btn gtv-btn-txt gtv-btn-active" data-act="mode-text" title="Plain string, copyable">📄</button>
        <button class="gtv-btn gtv-btn-txt" data-act="mode-links" title="Clickable rows">🔗</button>
        <button class="gtv-btn gtv-btn-txt" data-act="copy-tree" title="Copy the tree as plain text">📋 Copy</button>
        <button class="gtv-btn gtv-btn-txt" data-act="save-json" title="Download the tree as JSON">💾 JSON</button>
        <button class="gtv-btn" data-act="refresh" title="Re-fetch tree">↻</button>
        <button class="gtv-btn" data-act="close" title="Close (Esc)">×</button>
      </div>
      <div class="gtv-body">
        <div class="gtv-loading">Loading…</div>
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
      title.textContent = "";
      return;
    }
    title.textContent = `${state.owner}/${state.repo}@${state.branch}`;
    const total = state.files.length;
    const ai = state.files.filter(f => f.hasAiTxt).length;
    const patch = state.files.filter(f => f.hasPatch).length;
    stats.textContent = ` · ${total} files · 📄 ${ai} · 🔧 ${patch}` + (state.cached ? " · cached" : "");
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
EOL

# ---------------------------------------------------------------
# treeview.css — white GitHub theme, single header, tight rows,
# scrollable body, print-friendly.
# ---------------------------------------------------------------
cat << 'EOL' > treeview.css
/* ============================================================
   Treeview for GitHub — full-screen overlay, GitHub light theme
   ============================================================ */

#github-treeview-panel {
  position: fixed;
  inset: 0;
  width: 100vw;
  height: 100vh;
  z-index: 2147483600;
  background: #ffffff;
  color: #24292f;
  display: flex;
  flex-direction: column;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
  font-size: 14px;
  overflow: hidden;
}

/* ---------- Header — ONE bar, everything in it ---------- */
.gtv-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  background: #ffffff;
  border-bottom: 1px solid #d0d7de;
  min-height: 52px;
  flex-shrink: 0;
  flex-wrap: nowrap;
  overflow-x: auto;
}

.gtv-title {
  font-weight: 600;
  color: #24292f;
  font-size: 13px;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 30vw;
  flex-shrink: 1;
}

.gtv-stats {
  color: #57606a;
  font-size: 12px;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  white-space: nowrap;
  flex-shrink: 0;
}

.gtv-spacer { flex: 1; }

.gtv-btn {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  color: #24292f;
  cursor: pointer;
  min-width: 30px;
  height: 30px;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  flex-shrink: 0;
  padding: 0 8px;
  font-family: inherit;
  transition: background 0.1s, border-color 0.1s;
}
.gtv-btn:hover { background: #eef1f4; border-color: #bbc4cc; }
.gtv-btn:disabled { opacity: 0.45; cursor: not-allowed; }

.gtv-btn-txt {
  width: auto;
  padding: 0 10px;
  font-size: 13px;
  gap: 4px;
}

.gtv-btn-active {
  background: #0969da;
  border-color: #0969da;
  color: #ffffff;
}
.gtv-btn-active:hover { background: #0860ca; border-color: #0860ca; }

.gtv-filter {
  flex: 1;
  min-width: 120px;
  max-width: 320px;
  background: #ffffff;
  border: 1px solid #d0d7de;
  color: #24292f;
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 12.5px;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  height: 30px;
}
.gtv-filter::placeholder { color: #6e7781; }
.gtv-filter:focus {
  outline: none;
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9,105,218,0.15);
}

/* ---------- Body — properly scrollable ---------- */
.gtv-body {
  flex: 1 1 auto;
  overflow: auto;
  background: #ffffff;
  min-height: 0;
  padding: 0;
  scrollbar-gutter: stable;
}

.gtv-pre {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  font-size: 12.5px;
  line-height: 1.2;
  white-space: pre;
  padding: 8px 16px 40px;
  margin: 0;
  color: #24292f;
  min-width: 100%;
  display: block;
  tab-size: 4;
}

/* Zero gaps between rows — tight like `tree` output */
.gtv-line {
  display: block;
  white-space: pre;
  color: inherit;
  text-decoration: none;
  padding: 0;
  margin: 0;
  line-height: 1.2;
  cursor: default;
}
.gtv-line:hover { background: #f6f8fa; }

a.gtv-line {
  cursor: pointer;
}
a.gtv-line:focus {
  outline: none;
  background: #ddf4ff;
}
a.gtv-line:visited { color: inherit; }

/* Tree glyphs */
.gtv-glyph { color: #8b949e; }
.gtv-name  { color: #24292f; }
.gtv-dirname { color: #0969da; font-weight: 600; }

.gtv-badge {
  font-style: normal;
  font-size: 11px;
  opacity: 0.9;
}

.gtv-size {
  color: #6e7781;
  font-size: 11px;
}

/* ---------- States ---------- */
.gtv-loading,
.gtv-error,
.gtv-empty {
  padding: 60px 24px;
  text-align: center;
  color: #6e7781;
  font-size: 14px;
}
.gtv-error { color: #cf222e; }

.gtv-flash {
  margin-left: 8px;
  color: #1a7f37;
  font-size: 11px;
}

/* ---------- Toast ---------- */
.gtv-toast {
  position: fixed;
  bottom: 24px;
  left: 50%;
  transform: translateX(-50%);
  background: #24292f;
  color: #ffffff;
  padding: 10px 20px;
  border-radius: 6px;
  z-index: 2147483640;
  font-size: 13px;
  box-shadow: 0 8px 24px rgba(140,149,159,0.2);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.15s;
}
.gtv-toast.visible { opacity: 1; }

/* ---------- Scrollbar ---------- */
#github-treeview-panel ::-webkit-scrollbar { width: 12px; height: 12px; }
#github-treeview-panel ::-webkit-scrollbar-track { background: #ffffff; }
#github-treeview-panel ::-webkit-scrollbar-thumb {
  background: #d0d7de;
  border-radius: 6px;
  border: 3px solid #ffffff;
}
#github-treeview-panel ::-webkit-scrollbar-thumb:hover { background: #8b949e; }

/* ============================================================
   PRINT — full tree across pages, no chrome, black on white
   ============================================================ */
@media print {
  @page { margin: 12mm; }

  html, body {
    background: #ffffff !important;
    height: auto !important;
    overflow: visible !important;
  }

  /* Hide everything on the page except our panel */
  body > *:not(#github-treeview-panel) { display: none !important; }

  #github-treeview-panel {
    position: static !important;
    inset: auto !important;
    width: auto !important;
    height: auto !important;
    max-height: none !important;
    overflow: visible !important;
    display: block !important;
    background: #ffffff !important;
    color: #000000 !important;
    box-shadow: none !important;
    border: none !important;
  }

  /* Hide the interactive header entirely when printing */
  .gtv-header { display: none !important; }

  /* Body: no scroll, no clipping — let it flow across pages */
  .gtv-body {
    overflow: visible !important;
    height: auto !important;
    max-height: none !important;
    min-height: 0 !important;
    display: block !important;
    padding: 0 !important;
  }

  .gtv-pre {
    padding: 0 !important;
    margin: 0 !important;
    font-size: 10pt !important;
    line-height: 1.15 !important;
    color: #000 !important;
    background: transparent !important;
  }

  .gtv-line { color: #000 !important; background: transparent !important; }
  .gtv-line:hover { background: transparent !important; }
  .gtv-glyph { color: #555 !important; }
  .gtv-name  { color: #000 !important; }
  .gtv-dirname { color: #000 !important; font-weight: 700 !important; }
  .gtv-size { color: #333 !important; }
  .gtv-badge { color: #000 !important; }

  /* No toast when printing */
  .gtv-toast { display: none !important; }
}
EOL

# ---------------------------------------------------------------
# README.md
# ---------------------------------------------------------------
cat << 'EOL' > README.md
# Treeview for GitHub

Full-screen treeview of any GitHub repo. White GitHub theme.
Two render modes: copyable plain-text string, or clickable links.

## Modes

- **📄 string** (default) — the whole tree is a single `<pre>` block.
  Drag-select and copy it. Nothing is clickable. Exactly what `tree`
  prints on the command line.
- **🔗 links** — same layout and glyphs, but each row is an `<a href>`.
  Files open on GitHub in a new tab. Directories toggle collapse.

Toggle with the two buttons in the header bar.

## Header

One bar, everything in it:

- `owner/repo@branch` · `N files` · `📄 x` · `🔧 y` · `cached?`
- filter box
- expand all / collapse all
- 📄 string mode / 🔗 links mode
- 📋 Copy — copies the whole tree as plain text
- 💾 JSON — downloads the tree as JSON
- ↻ refresh
- × close

## What it does

- One GitHub API call fetches the whole tree (paths, sizes, SHAs)
- Filter box narrows paths by substring
- Expand-all / collapse-all
- Badges on files that have siblings:
  - 📄 has `-ai.txt`
  - 🔧 has `.patch`
  - ✏️ has `.patch-ai.txt`
- Right-click a file → copy its path
- 📋 Copy → the whole tree as a plain-text string
- 💾 JSON → download the tree as JSON

## Keyboard

- `Ctrl+Shift+T` toggles the overlay
- `Esc` closes it

## Caching

Cached in `browser.storage.local` for 1 hour per (owner/repo/branch).
Click ↻ to force a refresh.

## Printing

The body scrolls normally on screen. When you print (Ctrl+P), the
header is hidden, the body expands to full height, and the whole tree
flows across as many pages as needed — black on white, no chrome,
no scrollbars, no shadows. Perfect for a wall chart.

## Install

1. Open Firefox → `about:debugging`
2. This Firefox → Load Temporary Add-on
3. Select `manifest.json`

Temporary add-ons are cleared on Firefox restart.
EOL

# ---------------------------------------------------------------
# LICENSE.md
# ---------------------------------------------------------------
cat << EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOL

cd ..

# ── XPI package ─────────────────────────────────────────
echo -e "${CYAN}📦 Creating XPI package...${NC}"

DOWNLOADS_DIR="$HOME/Downloads"
XPI_FILE="$(pwd)/${EXTNAME}.xpi"

mkdir -p "$DOWNLOADS_DIR"

ZIP_TOOL=""
if command -v zip &> /dev/null; then
    ZIP_TOOL="zip"
elif command -v 7z &> /dev/null; then
    ZIP_TOOL="7z"
elif command -v jar &> /dev/null; then
    ZIP_TOOL="jar"
fi

if [ -z "$ZIP_TOOL" ]; then
    echo -e "${RED}❌ No zip tool found (zip / 7z / jar).${NC}"
    echo -e "${YELLOW}   Install one: brew install zip   (macOS)${NC}"
    echo -e "${YELLOW}                 apt install zip   (Debian/Ubuntu)${NC}"
    exit 1
fi

echo -e "${CYAN}   Using: $ZIP_TOOL${NC}"

rm -f "$XPI_FILE"
(
    cd "$EXTNAME" || exit 1
    case "$ZIP_TOOL" in
        zip) zip -r "$XPI_FILE" . -x "*.xpi" > /dev/null ;;
        7z)  7z a -tzip "$XPI_FILE" . > /dev/null ;;
        jar) jar cf "$XPI_FILE" . ;;
    esac
)

if [ ! -f "$XPI_FILE" ]; then
    echo -e "${RED}❌ Failed to create XPI.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Created: $XPI_FILE${NC}"
echo -e "${YELLOW}📦 Size: $(du -h "$XPI_FILE" | cut -f1)${NC}"

DEST="$DOWNLOADS_DIR/${EXTNAME}.xpi"
cp -f "$XPI_FILE" "$DEST"

if [ -f "$DEST" ]; then
    echo -e "${GREEN}✅ Saved to: $DEST${NC}"
    echo -e "${YELLOW}📦 Size: $(du -h "$DEST" | cut -f1)${NC}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        open -R "$DEST" 2>/dev/null || true
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$DOWNLOADS_DIR" 2>/dev/null || true
    fi
else
    echo -e "${RED}❌ Copy to Downloads failed.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Done.${NC}"
echo -e "${CYAN} XPI:      $DEST${NC}"
echo -e "${CYAN} Reload:   about:debugging#/runtime/this-firefox${NC}"
echo -e "${CYAN} Or drag:  $DEST  →  Firefox window${NC}"
echo ""
echo -e "${YELLOW} USAGE:${NC}"
echo -e "  • Open any github.com/<owner>/<repo> page"
echo -e "  • Click the toolbar button, or press Ctrl+Shift+T"
echo -e "  • Header: repo@branch · stats · filter · expand/collapse · 📄/🔗 · 📋 Copy · 💾 JSON · ↻ · ×"
echo -e "  • In string mode the tree is one copyable <pre> block"
echo -e "  • In links mode each row opens on GitHub"
echo -e "  • Ctrl+P prints the full tree across pages, no chrome"
echo -e "  • Esc to close"