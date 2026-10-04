# Treeview for GitHub

Full-screen treeview of any GitHub repo. White GitHub theme.
Two render modes: copyable plain-text string, or clickable links.

## Modes

- **📄 string** (default) — the whole tree is a single `<pre>` block.
  Drag-select and copy it. Nothing is clickable. Exactly what `tree`
  prints on the command line.
- **🔗 links** — same layout and glyphs, but each row is an `<a href>`.
  Files open on GitHub in a new tab. Directories toggle collapse.

Toggle with the two buttons in the header bar.

## Header

One bar, everything in it:

- `owner/repo@branch` · `N files` · `📄 x` · `🔧 y` · `cached?`
- filter box
- expand all / collapse all
- 📄 string mode / 🔗 links mode
- 📋 Copy — copies the whole tree as plain text
- 💾 JSON — downloads the tree as JSON
- ↻ refresh
- × close

## What it does

- One GitHub API call fetches the whole tree (paths, sizes, SHAs)
- Filter box narrows paths by substring
- Expand-all / collapse-all
- Badges on files that have siblings:
  - 📄 has `-ai.txt`
  - 🔧 has `.patch`
  - ✏️ has `.patch-ai.txt`
- Right-click a file → copy its path
- 📋 Copy → the whole tree as a plain-text string
- 💾 JSON → download the tree as JSON

## Keyboard

- `Ctrl+Shift+T` toggles the overlay
- `Esc` closes it

## Caching

Cached in `browser.storage.local` for 1 hour per (owner/repo/branch).
Click ↻ to force a refresh.

## Printing

The body scrolls normally on screen. When you print (Ctrl+P), the
header is hidden, the body expands to full height, and the whole tree
flows across as many pages as needed — black on white, no chrome,
no scrollbars, no shadows. Perfect for a wall chart.

## Install

1. Open Firefox → `about:debugging`
2. This Firefox → Load Temporary Add-on
3. Select `manifest.json`

Temporary add-ons are cleared on Firefox restart.
