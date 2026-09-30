// A4 Resizer - Background Script

const A4_LANDSCAPE = { width: 1123, height: 794 };
const A4_PORTRAIT  = { width: 794,  height: 1123 };

browser.contextMenus.create({
  id: "a4-landscape",
  title: "📄 A4 Landscape (1123 × 794)",
  contexts: ["all"]
});

browser.contextMenus.create({
  id: "a4-portrait",
  title: "📄 A4 Portrait (794 × 1123)",
  contexts: ["all"]
});

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  let target = null;
  if (info.menuItemId === "a4-landscape") target = A4_LANDSCAPE;
  if (info.menuItemId === "a4-portrait")  target = A4_PORTRAIT;
  if (!target) return;

  // Resize the CURRENT window — not a new one
  const currentWindow = await browser.windows.getCurrent();
  await browser.windows.update(currentWindow.id, {
    width: target.width,
    height: target.height,
    state: "normal"
  });
});
