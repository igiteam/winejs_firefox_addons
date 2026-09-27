// Search Highlighted Text on Meyt - Background Script

browser.contextMenus.create({
  id: "search-on-meyt",
  title: "🔍 Search on Meyt",
  contexts: ["selection"]
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "search-on-meyt") {
    const selectedText = (info.selectionText || "").trim();
    if (selectedText) {
      const url = `https://meyt.macosxjs.com/search/${encodeURIComponent(selectedText)}`;
      browser.tabs.create({ url: url, active: true });
    }
  }
});
