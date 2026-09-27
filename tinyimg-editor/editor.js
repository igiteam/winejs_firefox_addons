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
