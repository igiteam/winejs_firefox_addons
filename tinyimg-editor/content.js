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
