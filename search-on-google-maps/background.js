// Search Highlighted Text on Google Maps - Background Script

browser.contextMenus.create({
  id: "search-on-google-maps",
  title: "🔍 Search on Google Maps",
  contexts: ["selection"]
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "search-on-google-maps") {
    const selectedText = (info.selectionText || "").trim();
    if (selectedText) {
      const url = `https://www.google.com/maps/search/${encodeURIComponent(selectedText)}`;
      browser.tabs.create({ url: url, active: true });
    }
  }
});
