# Treeview for GitHub

Full-screen treeview of any GitHub repo. White GitHub theme.
Two render modes: copyable plain-text string, or clickable links.

## Modes

- **📄 string** (default) — the whole tree is a single `<pre>` block.
  Drag-select and copy it. Nothing is clickable. Exactly what `tree`
  prints on the command line.
- **🔗 links** — same layout and glyphs, but each row is an `<a href>`.
  Files open on GitHub in a new tab. Directories toggle collapse.

Toggle with the two buttons in the toolbar.

## Glyphs

Rows use the real `tree` branch glyphs:
repo
├── engine
│ ├── Poseidon
│ │ ├── AI
│ │ │ ├── AICenter.cpp 28.4 KB
│ │ │ └── AICenter.hpp 4.2 KB
│ │ └── Audio
│ │ └── Voice
│ │ └── VonApp.cpp 34.1 KB
│ └── Trident
│ └── Cargo.toml 1.1 KB
├── README.md 2.1 KB
└── CMakeLists.txt 8.4 KB

Correct `├─` / `└─` / `│` at every depth — last-child detection
works because the tree is built as nested nodes and walked
recursively.

## What it does

- One GitHub API call fetches the whole tree (paths, sizes, SHAs)
- Filter box narrows paths by substring
- Expand-all / collapse-all
- Badges on files that have siblings:
  - 📄 has `-ai.txt`
  - 🔧 has `.patch`
  - ✏️ has `.patch-ai.txt`
- Ctrl/Cmd+click files → multi-select
- Right-click a file → copy its path
- Footer buttons:
  - 🔗 RAG link → one `rag.songdrop.band/?url=…&url=…` link
  - 📋 Copy paths → newline-separated paths
  - 📄 Copy tree → the whole tree as a plain-text string
  - 💾 JSON → download the tree as JSON

## Keyboard

- `Ctrl+Shift+T` toggles the overlay
- `Esc` closes it

## Caching

Cached in `browser.storage.local` for 1 hour per (owner/repo/branch).
Click ↻ to force a refresh.

## Install

1. Open Firefox → `about:debugging`
2. This Firefox → Load Temporary Add-on
3. Select `manifest.json`

Temporary add-ons are cleared on Firefox restart.
