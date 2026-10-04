// Element Picker - Background Script

// Context menu entry
browser.contextMenus.create({
  id: "element-picker-start",
  title: "🎯 Element Picker: Start",
  contexts: ["all"]
});

// Toolbar button toggles picker
browser.browserAction.onClicked.addListener((tab) => {
  browser.tabs.sendMessage(tab.id, { action: "toggle-picker" }).catch(() => {
    // content script not loaded (e.g. about: page)
  });
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "element-picker-start") {
    browser.tabs.sendMessage(tab.id, { action: "toggle-picker" }).catch(() => {});
  }
});
