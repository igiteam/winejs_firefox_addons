#!/bin/bash

# ===============================================
# Search on Internet Archive - Firefox Addon Generator
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═════════════════════════════════════════════════════════════════════════════╗"
echo "║           Search on Internet Archive - Firefox Addon                        ║"
echo "║    Right-click highlighted text to search it on the Internet Archive        ║"
echo "╚═════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Enter your extension folder name (default: search-on-archive): " EXTNAME
EXTNAME=${EXTNAME:-search-on-archive}

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

echo -e "${CYAN}📥 Downloading default extension icon...${NC}"
curl -sL -o icons/icon.png "https://raw.githubusercontent.com/igiteam/winejs_firefox_addons/refs/heads/main/images/internet-archive-logo-white.png"
cp icons/icon.png icons/icon128.png

cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "Search on Internet Archive",
  "version": "2.0",
  "description": "Right-click highlighted text to search it on the Internet Archive (Wayback Machine or Archive.org)",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "menus",
    "contextMenus",
    "activeTab"
  ],
  "background": {
    "scripts": ["background.js"]
  },
  "browser_specific_settings": {
    "gecko": {
      "id": "search-on-archive@custom.addon",
      "strict_min_version": "57.0"
    }
  }
}
EOL

cat << 'EOL' > background.js
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
EOL

cat << 'EOL' > README.md
# Search on Internet Archive

Firefox addon. Highlight text on any page, right-click, choose:
- **🔗 Link (Wayback Machine)** → opens `https://web.archive.org/web/*/<your-text>`
- **💾 Software (Archive.org)** → opens `https://archive.org/search?query=<your-text>&tab=all`

## Install
1. Open Firefox → `about:debugging`
2. This Firefox → Load Temporary Add-on
3. Select `manifest.json`

## Note
Temporary add-ons are cleared on Firefox restart. For permanent install, sign it at addons.mozilla.org or use an unsigned/dev build.
EOL

cat << 'EOL' > LICENSE.md
MIT License

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

# Make sure Downloads exists
mkdir -p "$DOWNLOADS_DIR"

# Pick a zip tool: zip > 7z > jar
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

# Build the XPI (zip contents of the extension folder, no parent dir)
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

# Copy to Downloads — overwrite, and verify
DEST="$DOWNLOADS_DIR/${EXTNAME}.xpi"
cp -f "$XPI_FILE" "$DEST"

if [ -f "$DEST" ]; then
    echo -e "${GREEN}✅ Saved to: $DEST${NC}"
    echo -e "${YELLOW}📦 Size: $(du -h "$DEST" | cut -f1)${NC}"

    # Reveal in file manager
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