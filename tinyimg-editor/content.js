// Content script for TinyIMG Editor

console.log("TinyIMG Editor content script loaded");

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {

  // >>> FIX: NEW — grab actual pixel bytes from the page (bypasses CORS)
  if (message.action === "grabImageData") {
    grabImageData(message.srcUrl)
      .then(data => sendResponse({success: true, imageData: data}))
      .catch(err => sendResponse({success: false, error: err.message}));
    return true; // async
  }

  if (message.action === "getCurrentImage") {
    const images = Array.from(document.querySelectorAll('img'));

    let largestImage = null;
    let maxSize = 0;

    images.forEach(img => {
      const size = (img.naturalWidth || img.width) * (img.naturalHeight || img.height);
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
    return false;
  }

  if (message.action === "getAllImages") {
    const images = Array.from(document.querySelectorAll('img'));
    const imageUrls = images
      .filter(img => !img.src.startsWith('data:') && img.src)
      .map(img => ({
        url: img.src,
        width: img.naturalWidth || img.width,
        height: img.naturalHeight || img.height,
        alt: img.alt || 'image'
      }));

    sendResponse({images: imageUrls, success: true});
    return false;
  }
});

// >>> FIX: draw the <img> to canvas and return a data URL — works cross-origin
function grabImageData(srcUrl) {
  return new Promise((resolve, reject) => {
    const imgs = Array.from(document.querySelectorAll('img'));
    let el = imgs.find(i => i.src === srcUrl);

    if (!el) {
      try {
        const abs = new URL(srcUrl, location.href).href;
        el = imgs.find(i => i.src === abs);
      } catch (e) {}
    }

    if (el) {
      try {
        const w = el.naturalWidth || el.width;
        const h = el.naturalHeight || el.height;
        if (w && h) {
          const c = document.createElement('canvas');
          c.width = w; c.height = h;
          c.getContext('2d').drawImage(el, 0, 0, w, h);
          return resolve(c.toDataURL('image/png'));
        }
      } catch (e) {
        // Canvas tainted — fall through
        console.warn("canvas tainted, falling back to fetch:", e.message);
      }
    }

    // Fallback: fetch from page context
    fetch(srcUrl, { credentials: 'omit' })
      .then(r => { if (!r.ok) throw new Error("HTTP " + r.status); return r.blob(); })
      .then(blobToDataURL)
      .then(resolve)
      .catch(reject);
  });
}

function blobToDataURL(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onloadend = () => resolve(r.result);
    r.onerror = reject;
    r.readAsDataURL(blob);
  });
}
