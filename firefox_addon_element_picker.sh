#!/bin/bash

# ===============================================
# Element Picker - Firefox Addon Generator
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═════════════════════════════════════════════════════════════════════════════╗"
echo "║           Element Picker - Firefox Addon                                    ║"
echo "║    Hover to highlight · Click to get CSS selector + HTML for your scripts   ║"
echo "╚═════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Enter your extension folder name (default: element-picker): " EXTNAME
EXTNAME=${EXTNAME:-element-picker}

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
curl -sL -o icons/icon.png "https://raw.githubusercontent.com/igiteam/winejs_firefox_addons/refs/heads/main/images/firefox_addon_element_picker.png"
cp icons/icon.png icons/icon128.png

cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "Element Picker",
  "version": "2.0",
  "description": "Hover to highlight any element. Click to grab its CSS selector + HTML. Great for writing Tampermonkey scripts.",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "menus",
    "contextMenus",
    "activeTab",
    "clipboardWrite",
    "<all_urls>"
  ],
  "background": {
    "scripts": ["background.js"]
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ],
  "browser_action": {
    "default_title": "Element Picker",
    "default_icon": {
      "48": "icons/icon.png",
      "128": "icons/icon128.png"
    }
  },
  "browser_specific_settings": {
    "gecko": {
      "id": "element-picker@custom.addon",
      "strict_min_version": "57.0"
    }
  }
}
EOL

cat << 'EOL' > background.js
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
EOL

cat << 'EOL' > content.js
// Element Picker - Content Script (runs on every page)

(function () {
    'use strict';

    let active = false;
    let box, label, panel;

    // ── Build the overlay elements ────────────────────────────
    function buildUI() {
        if (box) return;

        box = document.createElement('div');
        Object.assign(box.style, {
            position: 'fixed',
            pointerEvents: 'none',
            zIndex: '2147483647',
            border: '2px solid #00e5ff',
            background: 'rgba(0,229,255,0.15)',
            borderRadius: '2px',
            display: 'none',
            transition: 'all 0.05s ease-out'
        });

        label = document.createElement('div');
        Object.assign(label.style, {
            position: 'fixed',
            pointerEvents: 'none',
            zIndex: '2147483647',
            background: 'rgba(0,0,0,0.88)',
            color: '#00e5ff',
            font: '12px/1.4 monospace',
            padding: '4px 8px',
            borderRadius: '4px',
            display: 'none',
            whiteSpace: 'nowrap',
            maxWidth: '90vw',
            overflow: 'hidden',
            textOverflow: 'ellipsis'
        });

        panel = document.createElement('div');
        Object.assign(panel.style, {
            position: 'fixed',
            bottom: '20px',
            right: '20px',
            zIndex: '2147483647',
            background: 'rgba(15,15,20,0.97)',
            color: '#e0e0e0',
            font: '12px/1.5 monospace',
            padding: '0',
            borderRadius: '8px',
            maxWidth: '480px',
            width: '480px',
            maxHeight: '60vh',
            overflow: 'hidden',
            boxShadow: '0 8px 30px rgba(0,0,0,0.55)',
            border: '1px solid #00e5ff',
            display: 'none',
            flexDirection: 'column'
        });

        document.documentElement.appendChild(box);
        document.documentElement.appendChild(label);
        document.documentElement.appendChild(panel);
    }

    // ── Generate a good CSS selector for an element ───────────
    function getSelector(el) {
        if (!(el instanceof Element)) return '';
        if (el.id) return '#' + CSS.escape(el.id);

        const parts = [];
        while (el && el.nodeType === 1 && parts.length < 6) {
            let part = el.tagName.toLowerCase();

            if (el.id) {
                part = '#' + CSS.escape(el.id);
                parts.unshift(part);
                break;
            }

            const classes = (el.className || '')
                .toString()
                .trim()
                .split(/\s+/)
                .filter(Boolean)
                .map(c => '.' + CSS.escape(c))
                .join('');
            if (classes) part += classes;

            const parent = el.parentElement;
            if (parent) {
                const siblings = [...parent.children].filter(
                    s => s.tagName === el.tagName
                );
                if (siblings.length > 1) {
                    const idx = siblings.indexOf(el) + 1;
                    part += `:nth-of-type(${idx})`;
                }
            }

            parts.unshift(part);
            el = el.parentElement;
        }
        return parts.join(' > ');
    }

    // ── Clean HTML preview of the element (unlimited) ─────────
    function getHtmlPreview(el) {
        const clone = el.cloneNode(true);
        clone.querySelectorAll('script,style').forEach(n => n.remove());
        return clone.outerHTML;
    }

    // ── Copy to clipboard ─────────────────────────────────────
    async function copy(text) {
        try {
            await navigator.clipboard.writeText(text);
        } catch {
            const ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            ta.remove();
        }
    }

    // ── Show panel with info ──────────────────────────────────
    function showPanel(el) {
        const selector = getSelector(el);
        const html = getHtmlPreview(el);
        const text = (el.textContent || '').trim().slice(0, 200);

        const esc = (s) => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

        panel.innerHTML = `
            <div style="
                display:flex; justify-content:space-between; align-items:center;
                padding:10px 14px;
                background:rgba(0,229,255,0.08);
                border-bottom:1px solid rgba(0,229,255,0.3);
                color:#00e5ff; font-weight:bold;
                flex-shrink:0;
            ">
                <span>🎯 Element Picked</span>
                <span id="ep-close" style="cursor:pointer;padding:2px 8px;border-radius:4px;background:rgba(255,255,255,0.08);">✕</span>
            </div>

            <div id="ep-body" style="
                padding:10px 14px;
                overflow-y:auto;
                flex:1 1 auto;
                min-height:0;
            ">
                <div style="margin-bottom:8px;">
                    <span style="color:#888;">Selector:</span><br>
                    <code style="color:#7CFC00;word-break:break-all;">${esc(selector)}</code>
                </div>
                <div style="margin-bottom:8px;">
                    <span style="color:#888;">Tag:</span> ${el.tagName.toLowerCase()}
                    ${el.id ? `| <span style="color:#888;">ID:</span> ${esc(el.id)}` : ''}
                    ${el.className ? `| <span style="color:#888;">Class:</span> ${esc(el.className.toString())}` : ''}
                </div>
                ${text ? `<div style="margin-bottom:8px;"><span style="color:#888;">Text:</span> ${esc(text)}</div>` : ''}
                <div style="margin-bottom:8px;">
                    <span style="color:#888;">HTML:</span><br>
                    <pre style="color:#ffb86c;white-space:pre-wrap;word-break:break-all;margin:4px 0;background:#000;padding:6px;border-radius:4px;max-height:150px;overflow:auto;">${esc(html)}</pre>
                </div>
            </div>

            <div style="
                display:flex; gap:8px;
                padding:10px 14px;
                background:rgba(0,0,0,0.35);
                border-top:1px solid rgba(0,229,255,0.3);
                flex-shrink:0;
            ">
                <button id="ep-copy-sel" style="flex:1;padding:6px;background:#00e5ff;border:none;border-radius:4px;cursor:pointer;font-weight:bold;">📋 Copy Selector</button>
                <button id="ep-copy-html" style="flex:1;padding:6px;background:#ffb86c;border:none;border-radius:4px;cursor:pointer;font-weight:bold;">📋 Copy HTML</button>
                <button id="ep-copy-tm" style="flex:1;padding:6px;background:#7CFC00;border:none;border-radius:4px;cursor:pointer;font-weight:bold;">📋 Copy TM Snippet</button>
            </div>
        `;
        panel.style.display = 'flex';

        panel.querySelector('#ep-copy-sel').onclick = () => {
            copy(selector);
            const b = panel.querySelector('#ep-copy-sel');
            b.textContent = '✅ Copied!';
            setTimeout(() => b.textContent = '📋 Copy Selector', 1200);
        };
        panel.querySelector('#ep-copy-html').onclick = () => {
            copy(html);
            const b = panel.querySelector('#ep-copy-html');
            b.textContent = '✅ Copied!';
            setTimeout(() => b.textContent = '📋 Copy HTML', 1200);
        };
        panel.querySelector('#ep-copy-tm').onclick = () => {
            const tm = `// ==UserScript==\n// @name         My Script\n// @match        ${location.origin}/*\n// @grant        none\n// ==/UserScript==\n\n(function() {\n    'use strict';\n\n    const el = document.querySelector('${selector.replace(/'/g, "\\'")}');\n    if (el) {\n        console.log('Found:', el);\n        // your code here\n    }\n})();\n`;
            copy(tm);
            const b = panel.querySelector('#ep-copy-tm');
            b.textContent = '✅ Copied!';
            setTimeout(() => b.textContent = '📋 Copy TM Snippet', 1200);
        };
        panel.querySelector('#ep-close').onclick = () => {
            panel.style.display = 'none';
        };
    }

    // ── Mouse handlers ────────────────────────────────────────
    function onMove(e) {
        if (!active) return;
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (!el || el === box || el === label || el === panel || panel.contains(el)) return;

        const r = el.getBoundingClientRect();
        Object.assign(box.style, {
            display: 'block',
            left: r.left + 'px',
            top: r.top + 'px',
            width: r.width + 'px',
            height: r.height + 'px'
        });

        const sel = getSelector(el);
        label.textContent = `${el.tagName.toLowerCase()}  ${sel}`;
        Object.assign(label.style, {
            display: 'block',
            left: r.left + 'px',
            top: Math.max(0, r.top - 24) + 'px'
        });
    }

    function onClick(e) {
        if (!active) return;
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (!el || el === box || el === label || panel.contains(el)) return;

        e.preventDefault();
        e.stopPropagation();
        showPanel(el);
    }

    function onKey(e) {
        if (e.key === 'Escape' && active) {
            setActive(false);
        }
    }

    function setActive(state) {
        buildUI();
        active = state;
        box.style.display = active ? 'block' : 'none';
        label.style.display = active ? 'block' : 'none';
        if (!active) panel.style.display = 'none';
        document.documentElement.style.cursor = active ? 'crosshair' : '';
    }

    // Listen for toggle from background/toolbar
    browser.runtime.onMessage.addListener((msg) => {
        if (msg && msg.action === 'toggle-picker') {
            setActive(!active);
        }
    });

    // Keyboard shortcut: Alt+Shift+E
    document.addEventListener('keydown', (e) => {
        if (e.altKey && e.shiftKey && (e.key === 'E' || e.key === 'e')) {
            e.preventDefault();
            setActive(!active);
        }
    }, true);

    // Mouse listeners
    document.addEventListener('mousemove', onMove, true);
    document.addEventListener('click', onClick, true);
    document.addEventListener('keydown', onKey, true);

    console.log('%c🎯 Element Picker loaded — Alt+Shift+E or click toolbar button', 'color:#00e5ff;font-weight:bold;');
})();
EOL

cat << 'EOL' > README.md
# Element Picker

Firefox addon. Hover any element → cyan highlight box. Click it → panel with:
- CSS **selector**
- **tag / id / class**
- **HTML** preview (unlimited)
- Ready-to-use **Tampermonkey snippet**

Toggle with **Alt+Shift+E**, the toolbar button, or right-click → "🎯 Element Picker: Start".
Press **Esc** to cancel.

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