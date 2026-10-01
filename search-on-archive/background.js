// Search on Internet Archive - Background Script

// Parent menu
browser.contextMenus.create({
  id: "search-on-archive",
  title: "🔍 Search on Archive",
  contexts: ["selection"]
});

// Submenu: Link (Wayback Machine)
browser.contextMenus.create({
  id: "search-on-archive-link",
  parentId: "search-on-archive",
  title: "🔗 Link (Wayback Machine)",
  contexts: ["selection"]
});

// Submenu: Software (Archive.org)
browser.contextMenus.create({
  id: "search-on-archive-software",
  parentId: "search-on-archive",
  title: "💾 Software (Archive.org)",
  contexts: ["selection"]
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  const selectedText = (info.selectionText || "").trim();
  if (!selectedText) return;

  if (info.menuItemId === "search-on-archive-link") {
    // Wayback Machine: https://web.archive.org/web/*/<url>
    const url = `https://web.archive.org/web/*/${selectedText}`;
    browser.tabs.create({ url: url, active: true });
  } else if (info.menuItemId === "search-on-archive-software") {
    // Archive.org search: https://archive.org/search?query=<text>&tab=all
    const url = `https://archive.org/search?query=${encodeURIComponent(selectedText)}&tab=all`;
    browser.tabs.create({ url: url, active: true });
  }
});
