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
