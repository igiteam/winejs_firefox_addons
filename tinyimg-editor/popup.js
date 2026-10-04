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
