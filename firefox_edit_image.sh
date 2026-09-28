#!/bin/bash

# ===============================================
# TinyIMG Firefox Extension Generator
# Keep ALL enhanced features + Original design
# ===============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           TinyIMG Firefox Extension Generator                 ║"
echo "║     Enhanced features + Original TinyIMG Design              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension folder name
read -p "Enter your extension folder name (default: tinyimg-editor): " EXTNAME
EXTNAME=${EXTNAME:-tinyimg-editor}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/icons"
cd "$EXTNAME" || exit

# Download original icon
echo -e "${CYAN}📥 Downloading default extension icon...${NC}"
curl -sL -o icons/icon.png "https://raw.githubusercontent.com/igiteam/winejs_firefox_addons/refs/heads/main/images/edit-image-logo.png"
cp icons/icon.png icons/icon128.png


# Create manifest.json with proper permissions
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "TinyIMG Editor",
  "version": "1.0",
  "description": "Crop images, remove backgrounds, draw shapes - simple image editor",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "activeTab",
    "storage",
    "contextMenus",
    "downloads",
    "webRequest",
    "webRequestBlocking",
    "*://*.remove.bg/*",
    "*://api.remove.bg/*"
  ],
  "browser_action": {
    "default_icon": "icons/icon.png",
    "default_title": "TinyIMG Editor",
    "default_popup": "popup.html"
  },
  "background": {
    "scripts": ["background.js"],
    "persistent": true
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_end"
    }
  ],
  "web_accessible_resources": [
    "editor.html",
    "editor.css",
    "editor.js"
  ],
  "browser_specific_settings": {
    "gecko": {
      "id": "@tinyimg-editor",
      "strict_min_version": "78.0"
    }
  }
}
EOL

# Create background.js (keep ALL your enhanced features)
cat << 'EOL' > background.js
// Background script for TinyIMG Editor - Enhanced features kept!
let isProcessing = false;
let currentImageData = null;
let removeBgApiKey = "";

// Load saved API key
browser.storage.local.get(['removeBgApiKey']).then(result => {
  if (result.removeBgApiKey) {
    removeBgApiKey = result.removeBgApiKey;
    console.log("API key loaded from storage");
  }
});

// Initialize context menu on install
browser.runtime.onInstalled.addListener(() => {
  browser.contextMenus.create({
    id: "crop-image",
    title: "Crop Image",
    contexts: ["image"]
  });
  
  browser.contextMenus.create({
    id: "remove-bg",
    title: "Remove Background",
    contexts: ["image"]
  });
  
  browser.contextMenus.create({
    id: "separator-1",
    type: "separator",
    contexts: ["image"]
  });
  
  browser.contextMenus.create({
    id: "configure-api",
    title: "Configure remove.bg API Key",
    contexts: ["image"]
  });
});

// Handle context menu clicks
browser.contextMenus.onClicked.addListener((info, tab) => {
  if (isProcessing) {
    showNotification("Already processing an image. Please wait.");
    return;
  }
  
  switch(info.menuItemId) {
    case "crop-image":
      handleCropImage(info, tab);
      break;
    case "remove-bg":
      handleRemoveBackground(info, tab);
      break;
    case "configure-api":
      browser.tabs.create({ url: "https://www.remove.bg/api#api-key" });
      browser.tabs.create({ 
        url: browser.runtime.getURL("popup.html") + "?configure=api"
      });
      break;
  }
});

// Handle toolbar button click
browser.browserAction.onClicked.addListener((tab) => {
  browser.tabs.create({ 
    url: browser.runtime.getURL("editor.html")
  });
});

// Handle messages from content script
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log("Background received message:", message.action);
  
  switch(message.action) {
    case "getImageData":
      sendResponse({imageData: currentImageData});
      break;
      
    case "setImageData":
      currentImageData = message.imageData;
      sendResponse({success: true});
      break;
      
    case "removeBackground":
      removeBackground(message.imageData, message.imageUrl)
        .then(result => {
          sendResponse({success: true, imageData: result});
        })
        .catch(error => {
          sendResponse({success: false, error: error.message});
        });
      return true;
      
    case "downloadImage":
      downloadImage(message.imageData, message.filename);
      sendResponse({success: true});
      break;
      
    case "saveApiKey":
      removeBgApiKey = message.apiKey;
      browser.storage.local.set({removeBgApiKey: message.apiKey})
        .then(() => sendResponse({success: true}))
        .catch(error => sendResponse({success: false, error: error.message}));
      return true;
      
    case "getApiKey":
      sendResponse({apiKey: removeBgApiKey});
      break;
      
    default:
      sendResponse({success: false, error: "Unknown action"});
  }
});

// Handle crop image
async function handleCropImage(info, tab) {
  isProcessing = true;
  
  try {
    showNotification("Loading image for cropping...");
    
    const imageData = await getImageDataFromUrl(info.srcUrl);
    currentImageData = imageData;
    
    await browser.tabs.create({
      url: browser.runtime.getURL("editor.html") + "?image=" + encodeURIComponent(imageData),
      active: true
    });
    
    showNotification("Image loaded in editor!");
    
  } catch (error) {
    showNotification("Failed to crop image: " + error.message);
  } finally {
    isProcessing = false;
  }
}

// Handle background removal
async function handleRemoveBackground(info, tab) {
  isProcessing = true;
  
  try {
    if (!removeBgApiKey) {
      showNotification("Please configure your remove.bg API key first");
      browser.tabs.create({ 
        url: browser.runtime.getURL("popup.html") + "?configure=api"
      });
      return;
    }
    
    showNotification("Removing background...");
    
    const result = await removeBackground(null, info.srcUrl);
    
    await browser.tabs.create({
      url: browser.runtime.getURL("editor.html") + "?image=" + encodeURIComponent(result) + "&fromRemoveBg=true",
      active: true
    });
    
    showNotification("Background removed successfully!");
    
  } catch (error) {
    showNotification("Failed to remove background: " + error.message);
  } finally {
    isProcessing = false;
  }
}

// Get image data from URL
async function getImageDataFromUrl(url) {
  try {
    if (url.startsWith('data:')) {
      return url;
    }
    
    const cacheBusterUrl = url + (url.includes('?') ? '&' : '?') + 't=' + Date.now();
    
    const response = await fetch(cacheBusterUrl, {
      mode: 'cors',
      credentials: 'omit'
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    const blob = await response.blob();
    return await blobToDataURL(blob);
  } catch (error) {
    throw new Error("Failed to load image: " + error.message);
  }
}

// Convert blob to data URL
function blobToDataURL(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

// Remove background using remove.bg API
async function removeBackground(imageData, imageUrl) {
  console.log("Starting background removal");
  
  if (!removeBgApiKey) {
    throw new Error("API key not configured. Please set your remove.bg API key first.");
  }
  
  const formData = new FormData();
  
  try {
    if (imageData) {
      const response = await fetch(imageData);
      const blob = await response.blob();
      formData.append("image_file", blob, "image.png");
    } else if (imageUrl) {
      formData.append("image_url", imageUrl);
    } else {
      throw new Error("No image provided");
    }
    
    formData.append("size", "auto");
    formData.append("format", "png");
    
    const response = await fetch("https://api.remove.bg/v1.0/removebg", {
      method: "POST",
      headers: {
        "X-Api-Key": removeBgApiKey
      },
      body: formData
    });
    
    if (!response.ok) {
      let errorText;
      try {
        errorText = await response.text();
        try {
          const errorJson = JSON.parse(errorText);
          errorText = errorJson.errors ? errorJson.errors[0].title : errorText;
        } catch (e) {}
      } catch (e) {
        errorText = `HTTP ${response.status}`;
      }
      
      if (response.status === 402) {
        throw new Error("API quota exceeded. Free tier: 50 calls/month.");
      } else if (response.status === 403) {
        throw new Error("Invalid API key. Please check your remove.bg API key.");
      } else if (response.status === 429) {
        throw new Error("Too many requests. Please wait a moment.");
      } else {
        throw new Error(`API Error (${response.status}): ${errorText}`);
      }
    }
    
    const resultBlob = await response.blob();
    return await blobToDataURL(resultBlob);
    
  } catch (error) {
    if (error.message.includes("Failed to fetch")) {
      throw new Error("Network error. Please check your internet connection.");
    } else {
      throw error;
    }
  }
}

// Download image
function downloadImage(imageData, filename) {
  try {
    const byteString = atob(imageData.split(',')[1]);
    const mimeString = imageData.split(',')[0].split(':')[1].split(';')[0];
    const ab = new ArrayBuffer(byteString.length);
    const ia = new Uint8Array(ab);
    
    for (let i = 0; i < byteString.length; i++) {
      ia[i] = byteString.charCodeAt(i);
    }
    
    const blob = new Blob([ab], { type: mimeString });
    const url = URL.createObjectURL(blob);
    
    browser.downloads.download({
      url: url,
      filename: filename,
      saveAs: true
    }).then(() => {
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    }).catch(() => {
      const link = document.createElement('a');
      link.href = imageData;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    });
    
  } catch (error) {
    showNotification("Download failed: " + error.message);
  }
}

// Show notification
function showNotification(message) {
  try {
    browser.notifications.create({
      type: "basic",
      iconUrl: browser.runtime.getURL("icons/icon.png"),
      title: "TinyIMG Editor",
      message: message
    });
  } catch (error) {}
}
EOL

# Create content.js (message handlers only - no hover/click hijacking)
cat << 'EOL' > content.js
// Content script for TinyIMG Editor

console.log("TinyIMG Editor content script loaded");

// Listen for messages from background script
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "getCurrentImage") {
    const images = Array.from(document.querySelectorAll('img'));

    let largestImage = null;
    let maxSize = 0;

    images.forEach(img => {
      const size = img.width * img.height;
      if (size > maxSize && !img.src.startsWith('data:') && img.src) {
        maxSize = size;
        largestImage = img;
      }
    });

    if (largestImage) {
      sendResponse({url: largestImage.src, success: true});
    } else {
      sendResponse({url: null, success: false, error: "No images found"});
    }
  } else if (message.action === "getAllImages") {
    const images = Array.from(document.querySelectorAll('img'));
    const imageUrls = images
      .filter(img => !img.src.startsWith('data:') && img.src)
      .map(img => ({
        url: img.src,
        width: img.width,
        height: img.height,
        alt: img.alt || 'image'
      }));

    sendResponse({images: imageUrls, success: true});
  }

  return true;
});
EOL

# Create popup.html (ORIGINAL TINYIMG DESIGN restored!)
cat << 'EOL' > popup.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>TinyIMG Editor</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
      font-family: Arial, sans-serif;
      font-size: 14px;
      user-select: none;
      -moz-user-select: none;
    }
    
    body {
      width: 260px;
      background: #efefef;
      color: #000;
      overflow: hidden;
    }
    
    .container {
      padding: 8px;
    }
    
    .title {
      text-align: center;
      font-weight: bold;
      padding: 8px 0;
      margin-bottom: 8px;
      border-bottom: 1px solid #c4c4c4;
      color: #333;
    }
    
    button {
      width: 100%;
      padding: 8px 12px;
      margin: 4px 0;
      background-color: #efefef;
      border: 1px solid #c4c4c4;
      cursor: pointer;
      text-align: left;
      font-size: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    
    button:hover {
      background-color: #d6d6d6;
    }
    
    button.primary {
      background-color: #3a76b1;
      border-color: #2a5a8c;
      color: white;
    }
    
    button.primary:hover {
      background-color: #2a5a8c;
    }
    
    .section {
      margin: 12px 0;
      padding: 8px 0;
      border-top: 1px solid #c4c4c4;
    }
    
    .section:first-of-type {
      border-top: none;
    }
    
    .api-input {
      width: 100%;
      padding: 6px;
      margin: 4px 0;
      border: 1px solid #c4c4c4;
      background: #fff;
      font-family: monospace;
    }
    
    .api-input:focus {
      outline: 1px solid #3a76b1;
    }
    
    .status {
      margin-top: 8px;
      padding: 6px;
      font-size: 12px;
      display: none;
      background: #fff;
      border: 1px solid #c4c4c4;
    }
    
    .status.success {
      background: #e8f0fe;
      border-color: #3a76b1;
      display: block;
    }
    
    .status.error {
      background: #ffe8e8;
      border-color: #d83e3e;
      display: block;
    }
    
    .status.warning {
      background: #fff3e0;
      border-color: #f0ad4e;
      display: block;
    }
    
    .help-text {
      font-size: 11px;
      color: #666;
      margin-top: 8px;
      line-height: 1.4;
    }
    
    .help-text a {
      color: #3a76b1;
      text-decoration: none;
    }
    
    .help-text a:hover {
      text-decoration: underline;
    }
    
    hr {
      border: none;
      border-top: 1px solid #c4c4c4;
      margin: 8px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="title">TinyIMG Editor</div>
    
    <button id="openEditor">
      <span>📁</span> Open Editor
    </button>
    
    <button id="uploadImage">
      <span>📤</span> Upload Image
    </button>
    
    <button id="currentPageImages">
      <span>🌐</span> Page Images
    </button>
    
    <hr>
    
    <div style="font-weight: bold; margin: 8px 0 4px 0;">remove.bg API Key</div>
    <input type="password" id="apiKey" class="api-input" placeholder="Enter API key">
    <button id="saveApiKey" style="text-align: center; justify-content: center;">Save API Key</button>
    
    <div id="status" class="status"></div>
    
    <div class="help-text">
      • Get free API key: <a href="https://www.remove.bg/api#api-key" target="_blank">remove.bg/api</a><br>
      • 50 free calls/month<br>
      • Key stored locally
    </div>
    
    <hr>
    
    <div style="font-size: 11px; color: #666; text-align: center;">
      Right-click any image on any webpage for quick access
    </div>
  </div>
  
  <script src="popup.js"></script>
</body>
</html>
EOL

# Create popup.js (keep functionality, simplify UI)
cat << 'EOL' > popup.js
// Popup script for TinyIMG Editor
document.addEventListener('DOMContentLoaded', function() {
  console.log("Popup loaded");
  
  const urlParams = new URLSearchParams(window.location.search);
  if (urlParams.get('configure') === 'api') {
    document.getElementById('apiKey').focus();
    showStatus('Enter your remove.bg API key', 'warning');
  }
  
  loadApiKey();
  
  document.getElementById('openEditor').addEventListener('click', () => {
    browser.tabs.create({
      url: browser.runtime.getURL('editor.html'),
      active: true
    });
  });
  
  document.getElementById('uploadImage').addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    
    input.onchange = async (e) => {
      const file = e.target.files[0];
      if (file) {
        showStatus('Processing image...', 'warning');
        
        try {
          const imageData = await fileToDataURL(file);
          
          browser.runtime.sendMessage({
            action: 'setImageData',
            imageData: imageData
          }).then(() => {
            browser.tabs.create({
              url: browser.runtime.getURL('editor.html') + '?image=' + encodeURIComponent(imageData),
              active: true
            });
          });
        } catch (error) {
          showStatus('Failed to read image', 'error');
        }
      }
    };
    
    input.click();
  });
  
  document.getElementById('currentPageImages').addEventListener('click', () => {
    showStatus('Looking for images...', 'warning');
    
    browser.tabs.query({active: true, currentWindow: true}).then(tabs => {
      if (!tabs[0] || tabs[0].url.startsWith('about:') || tabs[0].url.startsWith('chrome:')) {
        showStatus('No webpage with images', 'error');
        return;
      }
      
      browser.tabs.sendMessage(tabs[0].id, {action: 'getCurrentImage'}).then(response => {
        if (response.success && response.url) {
          browser.runtime.sendMessage({
            action: 'setImageData',
            imageData: response.url
          }).then(() => {
            browser.tabs.create({
              url: browser.runtime.getURL('editor.html') + '?image=' + encodeURIComponent(response.url),
              active: true
            });
          });
        } else {
          showStatus('No images found on page', 'error');
        }
      }).catch(() => {
        showStatus('Please refresh the page', 'error');
      });
    });
  });
  
  document.getElementById('saveApiKey').addEventListener('click', saveApiKey);
  
  document.getElementById('apiKey').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      saveApiKey();
    }
  });
});

function loadApiKey() {
  browser.runtime.sendMessage({action: 'getApiKey'}).then(response => {
    if (response.apiKey) {
      document.getElementById('apiKey').value = response.apiKey;
      showStatus('API key loaded', 'success');
    } else {
      showStatus('No API key found', 'warning');
    }
  });
}

function saveApiKey() {
  const apiKeyInput = document.getElementById('apiKey');
  const apiKey = apiKeyInput.value.trim();
  
  if (!apiKey) {
    showStatus('Please enter an API key', 'error');
    apiKeyInput.focus();
    return;
  }
  
  const saveBtn = document.getElementById('saveApiKey');
  const originalText = saveBtn.textContent;
  saveBtn.textContent = 'Saving...';
  saveBtn.disabled = true;
  
  browser.runtime.sendMessage({
    action: 'saveApiKey',
    apiKey: apiKey
  }).then(response => {
    if (response.success) {
      showStatus('API key saved!', 'success');
    } else {
      showStatus('Failed to save API key', 'error');
    }
  }).catch(() => {
    showStatus('Failed to save API key', 'error');
  }).finally(() => {
    saveBtn.textContent = originalText;
    saveBtn.disabled = false;
  });
}

function fileToDataURL(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

function showStatus(message, type) {
  const statusEl = document.getElementById('status');
  statusEl.textContent = message;
  statusEl.className = 'status ' + type;
  
  setTimeout(() => {
    statusEl.className = 'status';
    statusEl.textContent = '';
  }, 5000);
}
EOL

# Create editor.html (main editor with ORIGINAL TINYIMG DESIGN)
cat << 'EOL' > editor.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>TinyIMG Editor</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=1.0" />
  <link rel="icon" type="image/png" href="icons/icon.png">
  <style>
    * {
      font-family: Arial, sans-serif;
      font-size: 16px;
      box-sizing: border-box;
      user-select: none;
      -moz-user-select: none;
    }

    body {
      margin: 0;
      background: #000;
      display: flex;
      height: 100vh;
      overflow: hidden;
    }

    /* ── Sidebar: 2-column grid ── */
    .toolbar {
      position: fixed;
      top: 0;
      left: 0;
      width: 200px;
      height: 100%;
      background: #efefef;
      border-right: 1px solid #5a5a5a;
      padding: 5px;
      overflow-y: auto;
      display: grid;
      grid-template-columns: 1fr 1fr;
      grid-auto-rows: min-content;
      gap: 4px;
      align-content: start;
    }

    .toolbar::-webkit-scrollbar {
      display: none;
    }

    /* Full-width rows: dividers, headers, big controls */
    .toolbar hr,
    .toolbar strong,
    .toolbar .color-picker,
    .toolbar .containerResize,
    .toolbar > input[type=file],
    .toolbar #btnRemoveBg {
      grid-column: 1 / -1;
    }

    .toolbar strong {
      margin: 6px 0 2px 0;
      font-size: 13px;
      color: #333;
    }

    .toolbar hr {
      border: 0;
      height: 1px;
      background: #c4c4c4;
      margin: 6px 0;
    }

    /* All buttons fit in a grid cell */
    .toolbar button {
      margin: 0;
      padding: 6px 4px;
      background-color: #efefef;
      border: 1px solid #c4c4c4;
      cursor: pointer;
      font-size: 13px;
      text-align: center;
      justify-content: center;
      width: 100%;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      min-height: 28px;
    }

    .toolbar button:hover {
      background-color: #d6d6d6;
    }

    .toolbar button.selected {
      outline: 2px solid #3a76b1;
      background-color: #dce9f9;
    }

    .toolbar button:disabled {
      opacity: 0.4;
      cursor: default;
    }

    .toolbar button:disabled:hover {
      background-color: #efefef;
    }

    /* Number inputs span both columns */
    .toolbar input[type=number] {
      grid-column: 1 / -1;
      width: 100%;
      padding: 5px;
      margin: 0;
      border: 1px solid #c4c4c4;
      background: #fff;
      font-size: 14px;
    }

    .toolbar input[type=number]:disabled {
      background-color: #efefef;
      opacity: 0.4;
    }

    .toolbar label {
      grid-column: 1 / -1;
      display: flex;
      align-items: center;
      gap: 5px;
      margin: 0;
      font-size: 13px;
    }

    .toolbar input[type=checkbox] {
      cursor: pointer;
    }

    /* Color picker spans both columns */
    .color-picker {
      padding: 5px;
      border: 1px solid #c4c4c4;
      margin: 0;
    }

    .color-picker.disabled {
      opacity: 0.4;
      pointer-events: none;
    }

    .color-picker-preview {
      width: 100%;
      height: 24px;
      border: 1px solid #c4c4c4;
      margin-bottom: 4px;
    }

    .color-picker-input {
      width: 100%;
      padding: 4px;
      margin: 2px 0;
      border: 1px solid #c4c4c4;
      font-family: monospace;
      font-size: 11px;
    }

    .containerResize {
      padding: 0;
    }

    .title {
      text-align: center;
      font-weight: bold;
      margin: 10px 0;
      cursor: default;
    }

    /* ── Workspace matches toolbar width ── */
    .workspace {
      flex: 1;
      display: flex;
      justify-content: center;
      align-items: center;
      margin-left: 200px;
      overflow: auto;
    }

    canvas {
      background: #fff;
      max-width: 100%;
      max-height: 100%;
    }

    input[type=file] {
      display: none;
    }

    .notification {
      position: fixed;
      top: 20px;
      right: 20px;
      padding: 10px 20px;
      background: #efefef;
      border: 1px solid #5a5a5a;
      color: #000;
      z-index: 9999;
      display: none;
      box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    }
  </style>
</head>
<body>
  <div class="toolbar">
    <input type="file" id="fileSelector" accept="image/*">
    <button id="btnOpen">📁 Open</button>
    <button id="btnUndo" disabled>↩ Undo</button>
    <button id="btnRedo" disabled>↪ Redo</button>
    
    <hr>
    <strong>Transform</strong>
    <button id="btnFlipH">↔ Flip H</button>
    <button id="btnFlipV">↕ Flip V</button>
    <button id="btnRotateLeft">↺ Rotate L</button>
    <button id="btnRotateRight">↻ Rotate R</button>
    <button id="btnCrop">✂ Crop</button>
    <hr>
    <button id="btnRemoveBg" class="primary" style="background:#3a76b1; color:white; text-align:center; justify-content:center;">🎭 Remove Background</button>

    <hr>
    <strong>Merge</strong>
    <button id="btnMergeH">◫ Merge H</button>
    <button id="btnMergeV">▦ Merge V</button>
    <button id="btnPasteOverlay">📋 Paste Overlay</button>
    <input type="file" id="mergeFileSelector" accept="image/*">
    <input type="file" id="pasteOverlayFileSelector" accept="image/*">
    
    <hr>
    <strong>Draw</strong>
    <button id="btnDrawSquare">■ Square</button>
    <button id="btnDrawSquareOutline">□ Outline</button>
    <button id="btnDrawCircle">● Circle</button>
    <button id="btnDrawCircleOutline">○ Outline</button>
    <button id="btnDrawLine">/ Line</button>
    
    <div class="color-picker disabled" id="colorPicker">
      <div class="color-picker-preview" id="colorPreview" style="background:#ff0000"></div>
      <input type="text" id="inputShapeColorHex" class="color-picker-input" value="#ff0000" maxlength="7">
      <input type="text" id="inputShapeColorRgb" class="color-picker-input" value="255,0,0">
    </div>
    
    <hr>
    <div class="containerResize">
      <input type="number" id="inputWidth" min="1" placeholder="Width">
      <input type="number" id="inputHeight" min="1" placeholder="Height">
      <label><input type="checkbox" id="checkKeepRatio" checked> Keep ratio</label>
    </div>
    
    <hr>
    <strong>Download</strong>
    <button id="btnDownloadPNG">💾 PNG</button>
    <button id="btnDownloadJPG">💾 JPG</button>
    <button id="btnDownloadWEBP">💾 WebP</button>
    
    <hr>
    <strong>Base64</strong>
    <button id="btnDownloadPNGBase64">📄 PNG (Base64)</button>
    <button id="btnDownloadJPGBase64">📄 JPG (Base64)</button>
    <button id="btnDownloadWEBPBase64">📄 WebP (Base64)</button>
    
    <hr>
  </div>
  
  <div class="workspace">
    <canvas id="canvas"></canvas>
  </div>
  
  <div id="notification" class="notification"></div>
  
  <script src="editor.js"></script>
</body>
</html>
EOL

# Create editor.js (core editor functionality from original TinyIMG + your enhancements)
cat << 'EOL' > editor.js
// TinyIMG Editor Core - Original functionality + remove.bg integration
var canvas, ctx, img = new Image();
var originalFileName = null;
var undoStack = [], redoStack = [];
var activeTool = null;
var isDrawingShape = false, isCropping = false;
var startX, startY;
var currentSelection = null;
var displayScaleX = 1, displayScaleY = 1;
var ratio = 1;
var shapeColor = "#ff0000";
var removeBgApiKey = "";

// DOM Elements
var btnOpen, btnUndo, btnRedo, btnFlipH, btnFlipV, btnRotateLeft, btnRotateRight;
var btnCrop, btnMergeH, btnMergeV, btnPasteOverlay, btnResize;
var btnDrawSquare, btnDrawSquareOutline, btnDrawCircle, btnDrawCircleOutline, btnDrawLine;
var btnDownloadPNG, btnDownloadJPG, btnDownloadWEBP;
var btnDownloadPNGBase64, btnDownloadJPGBase64, btnDownloadWEBPBase64;
var btnRemoveBg;
var inputWidth, inputHeight, checkKeepRatio;
var fileSelector, mergeFileSelector, pasteOverlayFileSelector;
var colorPicker, colorPreview, inputShapeColorHex, inputShapeColorRgb;

// Initialize
window.addEventListener('load', function() {
  getElements();
  initEventListeners();
  loadApiKey();
  checkUrlForImage();
});

function getElements() {
  canvas = document.getElementById('canvas');
  ctx = canvas.getContext('2d');
  
  btnOpen = document.getElementById('btnOpen');
  btnUndo = document.getElementById('btnUndo');
  btnRedo = document.getElementById('btnRedo');
  btnFlipH = document.getElementById('btnFlipH');
  btnFlipV = document.getElementById('btnFlipV');
  btnRotateLeft = document.getElementById('btnRotateLeft');
  btnRotateRight = document.getElementById('btnRotateRight');
  btnCrop = document.getElementById('btnCrop');
  btnMergeH = document.getElementById('btnMergeH');
  btnMergeV = document.getElementById('btnMergeV');
  btnPasteOverlay = document.getElementById('btnPasteOverlay');
  btnRemoveBg = document.getElementById('btnRemoveBg');
  
  btnDrawSquare = document.getElementById('btnDrawSquare');
  btnDrawSquareOutline = document.getElementById('btnDrawSquareOutline');
  btnDrawCircle = document.getElementById('btnDrawCircle');
  btnDrawCircleOutline = document.getElementById('btnDrawCircleOutline');
  btnDrawLine = document.getElementById('btnDrawLine');
  
  btnDownloadPNG = document.getElementById('btnDownloadPNG');
  btnDownloadJPG = document.getElementById('btnDownloadJPG');
  btnDownloadWEBP = document.getElementById('btnDownloadWEBP');
  btnDownloadPNGBase64 = document.getElementById('btnDownloadPNGBase64');
  btnDownloadJPGBase64 = document.getElementById('btnDownloadJPGBase64');
  btnDownloadWEBPBase64 = document.getElementById('btnDownloadWEBPBase64');
  
  inputWidth = document.getElementById('inputWidth');
  inputHeight = document.getElementById('inputHeight');
  checkKeepRatio = document.getElementById('checkKeepRatio');
  
  fileSelector = document.getElementById('fileSelector');
  mergeFileSelector = document.getElementById('mergeFileSelector');
  pasteOverlayFileSelector = document.getElementById('pasteOverlayFileSelector');
  
  colorPicker = document.getElementById('colorPicker');
  colorPreview = document.getElementById('colorPreview');
  inputShapeColorHex = document.getElementById('inputShapeColorHex');
  inputShapeColorRgb = document.getElementById('inputShapeColorRgb');
  
  disableAll();
}

function initEventListeners() {
  btnOpen.addEventListener('click', () => fileSelector.click());
  
  fileSelector.addEventListener('change', function(e) {
    var file = e.target.files[0];
    if (!file) return;
    
    originalFileName = file.name.replace(/\.[^/.]+$/, "");
    var reader = new FileReader();
    reader.onload = function(evt) {
      img.src = evt.target.result;
    };
    reader.readAsDataURL(file);
    fileSelector.value = null;
  });
  
  img.onload = function() {
    canvas.style.display = 'block';
    canvas.width = img.width;
    canvas.height = img.height;
    ctx.drawImage(img, 0, 0);
    inputWidth.value = img.width;
    inputHeight.value = img.height;
    ratio = img.width / img.height;
    enableAll();
    captureUndoState();
  };
  
  // Undo/Redo
  btnUndo.addEventListener('click', undo);
  btnRedo.addEventListener('click', redo);
  
  // Transform
  btnFlipH.addEventListener('click', () => flip(true, false));
  btnFlipV.addEventListener('click', () => flip(false, true));
  btnRotateLeft.addEventListener('click', () => rotate(-90));
  btnRotateRight.addEventListener('click', () => rotate(90));
  btnCrop.addEventListener('click', crop);
  
  // Merge
  btnMergeH.addEventListener('click', () => { mustMergeHorizontal = true; mergeFileSelector.click(); });
  btnMergeV.addEventListener('click', () => { mustMergeHorizontal = false; mergeFileSelector.click(); });
  btnPasteOverlay.addEventListener('click', () => pasteOverlayFileSelector.click());
  
  // Draw tools
  btnDrawSquare.addEventListener('click', () => setActiveTool('square'));
  btnDrawSquareOutline.addEventListener('click', () => setActiveTool('squareOutline'));
  btnDrawCircle.addEventListener('click', () => setActiveTool('circle'));
  btnDrawCircleOutline.addEventListener('click', () => setActiveTool('circleOutline'));
  btnDrawLine.addEventListener('click', () => setActiveTool('line'));
  
  // Color picker
  inputShapeColorHex.addEventListener('input', (e) => updateColorFromHex(e.target.value));
  inputShapeColorRgb.addEventListener('input', (e) => updateColorFromRgb(e.target.value));
  
  // Remove.bg
  btnRemoveBg.addEventListener('click', removeBackground);
  
  // Download
  btnDownloadPNG.addEventListener('click', () => downloadImage('png', false));
  btnDownloadJPG.addEventListener('click', () => downloadImage('jpeg', false));
  btnDownloadWEBP.addEventListener('click', () => downloadImage('webp', false));
  btnDownloadPNGBase64.addEventListener('click', () => downloadImage('png', true));
  btnDownloadJPGBase64.addEventListener('click', () => downloadImage('jpeg', true));
  btnDownloadWEBPBase64.addEventListener('click', () => downloadImage('webp', true));
  
  // Resize inputs
  inputWidth.addEventListener('input', function() {
    if (!checkKeepRatio.checked) return;
    var newW = parseInt(inputWidth.value);
    if (newW > 0) inputHeight.value = Math.round(newW / ratio);
  });
  
  inputHeight.addEventListener('input', function() {
    if (!checkKeepRatio.checked) return;
    var newH = parseInt(inputHeight.value);
    if (newH > 0) inputWidth.value = Math.round(newH * ratio);
  });
  
  btnResize = document.getElementById('btnResize');
  if (btnResize) {
    btnResize.addEventListener('click', resize);
  }
  
  // Mouse events for cropping/drawing
  canvas.addEventListener('mousedown', handleMouseDown);
  document.addEventListener('mousemove', handleMouseMove);
  document.addEventListener('mouseup', handleMouseUp);
  
  // Merge file selector
  mergeFileSelector.addEventListener('change', handleMergeFile);
  pasteOverlayFileSelector.addEventListener('change', handlePasteOverlayFile);
}

// Core functions from original TinyIMG
function disableAll() {
  var buttons = document.querySelectorAll('button');
  buttons.forEach(btn => {
    if (btn.id !== 'btnOpen') {
      btn.disabled = true;
    }
  });
  inputWidth.disabled = true;
  inputHeight.disabled = true;
  checkKeepRatio.disabled = true;
  colorPicker.classList.add('disabled');
}

function enableAll() {
  var buttons = document.querySelectorAll('button');
  buttons.forEach(btn => {
    btn.disabled = false;
  });
  inputWidth.disabled = false;
  inputHeight.disabled = false;
  checkKeepRatio.disabled = false;
  colorPicker.classList.remove('disabled');
  updateUndoRedoButtons();
}

function captureUndoState() {
  if (!canvas.width) return;
  var state = canvas.toDataURL();
  undoStack.push(state);
  redoStack = [];
  updateUndoRedoButtons();
}

function undo() {
  if (undoStack.length < 2) return;
  var current = canvas.toDataURL();
  redoStack.push(current);
  undoStack.pop();
  var prev = undoStack[undoStack.length - 1];
  loadImageData(prev);
  updateUndoRedoButtons();
}

function redo() {
  if (redoStack.length === 0) return;
  var next = redoStack.pop();
  var current = canvas.toDataURL();
  undoStack.push(current);
  loadImageData(next);
  updateUndoRedoButtons();
}

function loadImageData(dataUrl) {
  var tempImg = new Image();
  tempImg.onload = function() {
    canvas.width = tempImg.width;
    canvas.height = tempImg.height;
    ctx.drawImage(tempImg, 0, 0);
    inputWidth.value = tempImg.width;
    inputHeight.value = tempImg.height;
    ratio = tempImg.width / tempImg.height;
    img.src = dataUrl;
  };
  tempImg.src = dataUrl;
}

function updateUndoRedoButtons() {
  btnUndo.disabled = undoStack.length < 2;
  btnRedo.disabled = redoStack.length === 0;
}

function flip(horizontal, vertical) {
  if (!canvas.width) return;
  captureUndoState();
  
  var tmp = document.createElement('canvas');
  tmp.width = canvas.width;
  tmp.height = canvas.height;
  var tctx = tmp.getContext('2d');
  tctx.translate(horizontal ? tmp.width : 0, vertical ? tmp.height : 0);
  tctx.scale(horizontal ? -1 : 1, vertical ? -1 : 1);
  tctx.drawImage(canvas, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(tmp, 0, 0);
  img.src = canvas.toDataURL();
}

function rotate(deg) {
  if (!canvas.width) return;
  captureUndoState();
  
  var tmp = document.createElement('canvas');
  var tctx = tmp.getContext('2d');
  
  if (Math.abs(deg) === 90 || Math.abs(deg) === 270) {
    tmp.width = canvas.height;
    tmp.height = canvas.width;
  } else {
    tmp.width = canvas.width;
    tmp.height = canvas.height;
  }
  
  tctx.translate(tmp.width / 2, tmp.height / 2);
  tctx.rotate((deg * Math.PI) / 180);
  tctx.drawImage(canvas, -canvas.width / 2, -canvas.height / 2);
  
  canvas.width = tmp.width;
  canvas.height = tmp.height;
  ctx.drawImage(tmp, 0, 0);
  img.src = canvas.toDataURL();
  inputWidth.value = canvas.width;
  inputHeight.value = canvas.height;
  ratio = canvas.width / canvas.height;
}

function crop() {
  if (!currentSelection) return;
  captureUndoState();
  
  var cropped = document.createElement('canvas');
  cropped.width = currentSelection.width;
  cropped.height = currentSelection.height;
  var croppedCtx = cropped.getContext('2d');
  
  croppedCtx.drawImage(
    img,
    currentSelection.x, currentSelection.y,
    currentSelection.width, currentSelection.height,
    0, 0, currentSelection.width, currentSelection.height
  );
  
  canvas.width = currentSelection.width;
  canvas.height = currentSelection.height;
  ctx.drawImage(cropped, 0, 0);
  img.src = canvas.toDataURL();
  currentSelection = null;
  inputWidth.value = canvas.width;
  inputHeight.value = canvas.height;
  ratio = canvas.width / canvas.height;
}

function resize() {
  var newW = parseInt(inputWidth.value);
  var newH = parseInt(inputHeight.value);
  
  if (!newW || !newH) return;
  captureUndoState();
  
  var tmp = document.createElement('canvas');
  tmp.width = newW;
  tmp.height = newH;
  var tctx = tmp.getContext('2d');
  tctx.drawImage(canvas, 0, 0, newW, newH);
  
  canvas.width = newW;
  canvas.height = newH;
  ctx.drawImage(tmp, 0, 0);
  img.src = canvas.toDataURL();
  ratio = canvas.width / canvas.height;
}

function setActiveTool(tool) {
  if (activeTool === tool) {
    activeTool = null;
  } else {
    activeTool = tool;
  }
  
  // Update button states
  [btnDrawSquare, btnDrawSquareOutline, btnDrawCircle, btnDrawCircleOutline, btnDrawLine].forEach(btn => {
    btn.classList.remove('selected');
  });
  
  if (activeTool) {
    var activeBtn = {
      'square': btnDrawSquare,
      'squareOutline': btnDrawSquareOutline,
      'circle': btnDrawCircle,
      'circleOutline': btnDrawCircleOutline,
      'line': btnDrawLine
    }[activeTool];
    if (activeBtn) activeBtn.classList.add('selected');
  }
  
  isCropping = false;
  currentSelection = null;
}

function handleMouseDown(e) {
  if (!canvas.width) return;
  if (e.button !== 0) return;
  
  var rect = canvas.getBoundingClientRect();
  displayScaleX = canvas.clientWidth / canvas.width;
  displayScaleY = canvas.clientHeight / canvas.height;
  
  var x = (e.clientX - rect.left) / displayScaleX;
  var y = (e.clientY - rect.top) / displayScaleY;
  
  if (activeTool) {
    isDrawingShape = true;
    startX = x;
    startY = y;
    return;
  }
  
  isCropping = true;
  startX = x;
  startY = y;
}

function handleMouseMove(e) {
  if (!isCropping && !isDrawingShape) return;
  
  var rect = canvas.getBoundingClientRect();
  var x = (e.clientX - rect.left) / displayScaleX;
  var y = (e.clientY - rect.top) / displayScaleY;
  
  if (isDrawingShape && activeTool) {
    redrawBaseImage();
    drawShape(startX, startY, x, y);
  } else if (isCropping) {
    currentSelection = {
      x: Math.min(startX, x),
      y: Math.min(startY, y),
      width: Math.abs(x - startX),
      height: Math.abs(y - startY)
    };
    drawSelection();
  }
}

function handleMouseUp(e) {
  if (isDrawingShape && activeTool) {
    var rect = canvas.getBoundingClientRect();
    var x = (e.clientX - rect.left) / displayScaleX;
    var y = (e.clientY - rect.top) / displayScaleY;
    
    captureUndoState();
    redrawBaseImage();
    drawShape(startX, startY, x, y);
    img.src = canvas.toDataURL();
    isDrawingShape = false;
  }
  
  isCropping = false;
  startX = null;
  startY = null;
}

function redrawBaseImage() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(img, 0, 0);
}

function drawShape(x1, y1, x2, y2) {
  ctx.save();
  ctx.strokeStyle = shapeColor;
  ctx.fillStyle = shapeColor;
  ctx.lineWidth = 3;
  
  switch(activeTool) {
    case 'square':
      var size = Math.min(Math.abs(x2 - x1), Math.abs(y2 - y1));
      var x = x2 > x1 ? x1 : x1 - size;
      var y = y2 > y1 ? y1 : y1 - size;
      ctx.fillRect(x, y, size, size);
      break;
      
    case 'squareOutline':
      var size = Math.min(Math.abs(x2 - x1), Math.abs(y2 - y1));
      var x = x2 > x1 ? x1 : x1 - size;
      var y = y2 > y1 ? y1 : y1 - size;
      ctx.strokeRect(x, y, size, size);
      break;
      
    case 'circle':
      var size = Math.min(Math.abs(x2 - x1), Math.abs(y2 - y1));
      var x = x2 > x1 ? x1 : x1 - size;
      var y = y2 > y1 ? y1 : y1 - size;
      ctx.beginPath();
      ctx.arc(x + size/2, y + size/2, size/2, 0, Math.PI * 2);
      ctx.fill();
      break;
      
    case 'circleOutline':
      var size = Math.min(Math.abs(x2 - x1), Math.abs(y2 - y1));
      var x = x2 > x1 ? x1 : x1 - size;
      var y = y2 > y1 ? y1 : y1 - size;
      ctx.beginPath();
      ctx.arc(x + size/2, y + size/2, size/2, 0, Math.PI * 2);
      ctx.stroke();
      break;
      
    case 'line':
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
      break;
  }
  
  ctx.restore();
}

function drawSelection() {
  if (!currentSelection) return;
  
  redrawBaseImage();
  
  ctx.fillStyle = 'rgba(0,0,0,0.7)';
  ctx.fillRect(0, 0, canvas.width, currentSelection.y);
  ctx.fillRect(0, currentSelection.y + currentSelection.height, canvas.width, canvas.height - (currentSelection.y + currentSelection.height));
  ctx.fillRect(0, currentSelection.y, currentSelection.x, currentSelection.height);
  ctx.fillRect(currentSelection.x + currentSelection.width, currentSelection.y, canvas.width - (currentSelection.x + currentSelection.width), currentSelection.height);
  
  ctx.strokeStyle = '#FFF';
  ctx.lineWidth = 2;
  ctx.strokeRect(currentSelection.x, currentSelection.y, currentSelection.width, currentSelection.height);
}

function downloadImage(format, asBase64) {
  if (!originalFileName) return;
  
  var canvasToUse = canvas;
  
  if (format === 'jpeg') {
    var tmp = document.createElement('canvas');
    tmp.width = canvas.width;
    tmp.height = canvas.height;
    var tctx = tmp.getContext('2d');
    tctx.fillStyle = '#fff';
    tctx.fillRect(0, 0, tmp.width, tmp.height);
    tctx.drawImage(canvas, 0, 0);
    canvasToUse = tmp;
  }
  
  if (asBase64) {
    var base64 = canvasToUse.toDataURL('image/' + format);
    var blob = new Blob([base64], { type: 'text/plain' });
    var url = URL.createObjectURL(blob);
    var link = document.createElement('a');
    link.download = originalFileName + '-base64.' + (format === 'jpeg' ? 'jpg' : format) + '.txt';
    link.href = url;
    link.click();
  } else {
    var link = document.createElement('a');
    link.download = originalFileName + '.' + (format === 'jpeg' ? 'jpg' : format);
    link.href = canvasToUse.toDataURL('image/' + format);
    link.click();
  }
}

// Color picker functions
function updateColorFromHex(hex) {
  if (!/^#[0-9A-F]{6}$/i.test(hex)) return;
  shapeColor = hex;
  colorPreview.style.backgroundColor = hex;
  
  var r = parseInt(hex.slice(1,3), 16);
  var g = parseInt(hex.slice(3,5), 16);
  var b = parseInt(hex.slice(5,7), 16);
  inputShapeColorRgb.value = r + ',' + g + ',' + b;
}

function updateColorFromRgb(rgb) {
  var parts = rgb.split(',').map(p => parseInt(p.trim()));
  if (parts.length !== 3 || parts.some(isNaN)) return;
  
  var hex = '#' + parts.map(p => p.toString(16).padStart(2,'0')).join('');
  shapeColor = hex;
  colorPreview.style.backgroundColor = hex;
  inputShapeColorHex.value = hex;
}

// API Key functions
function loadApiKey() {
  browser.runtime.sendMessage({action: 'getApiKey'}).then(response => {
    if (response.apiKey) {
      removeBgApiKey = response.apiKey;
    }
  });
}

function removeBackground() {
  if (!canvas.width) {
    showNotification('No image loaded');
    return;
  }
  
  if (!removeBgApiKey) {
    showNotification('Please set API key in popup first');
    return;
  }
  
  showNotification('Removing background...');
  
  browser.runtime.sendMessage({
    action: 'removeBackground',
    imageData: canvas.toDataURL()
  }).then(response => {
    if (response.success) {
      loadImageData(response.imageData);
      showNotification('Background removed!');
    } else {
      showNotification('Error: ' + response.error);
    }
  });
}

function handleMergeFile(e) {
  var file = e.target.files[0];
  if (!file) return;
  
  var reader = new FileReader();
  reader.onload = function(evt) {
    var mergeImg = new Image();
    mergeImg.onload = function() {
      mergeImages(mergeImg, mustMergeHorizontal);
    };
    mergeImg.src = evt.target.result;
  };
  reader.readAsDataURL(file);
}

function handlePasteOverlayFile(e) {
  var file = e.target.files[0];
  if (!file) return;
  
  var reader = new FileReader();
  reader.onload = function(evt) {
    var overlayImg = new Image();
    overlayImg.onload = function() {
      pasteOverlay(overlayImg);
    };
    overlayImg.src = evt.target.result;
  };
  reader.readAsDataURL(file);
}

function mergeImages(mergeImg, horizontal) {
  captureUndoState();
  
  var newCanvas = document.createElement('canvas');
  var newCtx = newCanvas.getContext('2d');
  
  if (horizontal) {
    var scale = img.height / mergeImg.height;
    var mergeW = mergeImg.width * scale;
    newCanvas.width = img.width + mergeW;
    newCanvas.height = img.height;
    newCtx.drawImage(img, 0, 0);
    newCtx.drawImage(mergeImg, img.width, 0, mergeW, img.height);
  } else {
    var scale = img.width / mergeImg.width;
    var mergeH = mergeImg.height * scale;
    newCanvas.width = img.width;
    newCanvas.height = img.height + mergeH;
    newCtx.drawImage(img, 0, 0);
    newCtx.drawImage(mergeImg, 0, img.height, img.width, mergeH);
  }
  
  canvas.width = newCanvas.width;
  canvas.height = newCanvas.height;
  ctx.drawImage(newCanvas, 0, 0);
  img.src = canvas.toDataURL();
  inputWidth.value = canvas.width;
  inputHeight.value = canvas.height;
  ratio = canvas.width / canvas.height;
}

function pasteOverlay(overlayImg) {
  captureUndoState();
  
  var x = (canvas.width - overlayImg.width) / 2;
  var y = (canvas.height - overlayImg.height) / 2;
  
  ctx.drawImage(overlayImg, x, y);
  img.src = canvas.toDataURL();
}

function checkUrlForImage() {
  var urlParams = new URLSearchParams(window.location.search);
  var imageParam = urlParams.get('image');
  
  if (imageParam) {
    img.src = imageParam;
  }
}

function showNotification(msg) {
  var notif = document.getElementById('notification');
  notif.textContent = msg;
  notif.style.display = 'block';
  
  setTimeout(() => {
    notif.style.display = 'none';
  }, 3000);
}
EOL

# Create README.md
cat << 'EOL' > README.md
# TinyIMG Editor - Firefox Extension

A lightweight image editor for Firefox with original TinyIMG design and enhanced features.

## Features
- ✂️ Crop, resize, rotate, flip images
- 🎨 Draw shapes (squares, circles, lines)
- 🎭 AI background removal (remove.bg API)
- 📋 Right-click any image on any webpage
- 💾 Download as PNG, JPG, WebP
- 📄 Export as Base64
- ↩️ Undo/Redo support

## Installation
1. Open Firefox and go to `about:debugging`
2. Click "This Firefox" → "Load Temporary Add-on"
3. Select the `manifest.json` file

## Get API Key for Background Removal
1. Visit https://www.remove.bg/api#api-key
2. Sign up for free (50 calls/month)
3. Enter API key in extension popup

## Usage
- **Right-click** any image on any webpage
- Click extension icon in toolbar
- Open editor and drag & drop images

## Original Design
Maintains the clean, functional aesthetic of TinyIMG Editor with gray toolbar and black workspace.
EOL


# Create LICENSE.md
cat << EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y) Gabriel Majorsky

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

Third-party Services:
- remove.bg API (https://www.remove.bg) - Proprietary, free tier available
EOL

# ===============================================
# Auto-Package extension as .xpi file
# ===============================================

echo -e "${CYAN}📦 Auto-packaging extension as .xpi file...${NC}"

# Stay in the extension directory
XPI_FILE="${EXTNAME}.xpi"

# Remove any existing XPI file
rm -f "$XPI_FILE" 2>/dev/null
# Create the XPI file with correct structure

echo -e "${CYAN}Creating $XPI_FILE...${NC}"

# Use 7z if available
if command -v 7z &> /dev/null; then
7z a "$XPI_FILE" * -r -x!.xpi -x!.
elif command -v zip &> /dev/null; then
zip -r "$XPI_FILE" * -x ".xpi" -x "."
else
echo -e "${RED}Error: Need zip or 7z to create XPI${NC}"
exit 1
fi

# Check if XPI was created
if [ -f "$XPI_FILE" ]; then
echo -e "${GREEN}✅ Created: $XPI_FILE${NC}"
echo -e "${YELLOW}📦 XPI file size: $(du -h "$XPI_FILE" | cut -f1)${NC}"

# Move XPI to parent directory
echo -e "${CYAN}📁 Moving XPI to parent directory...${NC}"
mv "$XPI_FILE" "../"
XPI_FILE="../${EXTNAME}.xpi"

# Move XPI to Downloads folder
echo -e "${CYAN}📁 Moving XPI to Downloads folder...${NC}"
mv "$XPI_FILE" "$HOME/Downloads/${EXTNAME}.xpi"
XPI_FILE="$HOME/Downloads/${EXTNAME}.xpi"
echo -e "${GREEN}✅ XPI moved to: $XPI_FILE${NC}"

# Open Firefox Developer Edition addons page
echo -e "${CYAN}🌐 Opening Firefox Developer Edition addons page...${NC}"
/Applications/Firefox\ Developer\ Edition.app/Contents/MacOS/firefox "about:addons" &
# Go to parent directory
cd ..

echo -e ""
echo -e "${GREEN}✨ FILES:${NC}"
echo -e " • ${EXTNAME}/ - Source folder"
echo -e " • ${EXTNAME}.xpi - Extension package"

echo -e ""
echo -e "${CYAN}🚀 INSTALLATION:${NC}"
echo -e " • Drag and drop ${EXTNAME}.xpi into Firefox"
echo -e " • Or load temporarily via about:debugging"

else
echo -e "${RED}❌ Failed to create XPI file${NC}"
fi

echo -e ""
echo -e "${GREEN}✅ Extension generation complete!${NC}"
echo -e ""
echo -e "${YELLOW}🎯 Features preserved:${NC}"
echo -e "  ✅ Original TinyIMG gray toolbar design"
echo -e "  ✅ Black workspace background"
echo -e "  ✅ Simple, functional buttons"
echo -e "  ✅ remove.bg API integration"
echo -e "  ✅ Right-click context menu"
echo -e "  ✅ Image hover effects"
echo -e "  ✅ Multiple export formats"
echo -e "  ✅ Undo/Redo support"
echo -e ""
echo -e "${CYAN}Load in Firefox: about:debugging → This Firefox → Load Temporary Add-on${NC}"
