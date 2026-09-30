#!/bin/bash

# ===============================================
# A4 Resizer - Firefox Addon Generator
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═════════════════════════════════════════════════════════════════════════════╗"
echo "║              A4 Resizer - Firefox Addon                                     ║"
echo "║    Right-click to resize the Firefox window to A4 at 96 DPI                ║"
echo "╚═════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Enter your extension folder name (default: a4-resizer): " EXTNAME
EXTNAME=${EXTNAME:-a4-resizer}

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

echo -e "${CYAN}📥 Downloading extension icon...${NC}"
curl -sL -o icons/icon.png "https://static.vecteezy.com/system/resources/previews/026/530/350/non_2x/a4-size-paper-icon-vector.jpg"
cp icons/icon.png icons/icon128.png

cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "A4 Resizer",
  "version": "1.0",
  "description": "Right-click to resize the Firefox window to A4 landscape or portrait at 96 DPI",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "menus",
    "contextMenus",
    "activeTab",
    "tabs"
  ],
  "background": {
    "scripts": ["background.js"]
  },
  "browser_specific_settings": {
    "gecko": {
      "id": "a4-resizer@custom.addon",
      "strict_min_version": "57.0"
    }
  }
}
EOL

cat << 'EOL' > background.js
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
EOL

cat << 'EOL' > README.md
# A4 Resizer

Firefox addon. Right-click anywhere, choose:
- 📄 A4 Landscape (1123 × 794)
- 📄 A4 Portrait (794 × 1123)

Opens the current page in a new popup window at exactly A4 96 DPI dimensions.

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