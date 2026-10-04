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
