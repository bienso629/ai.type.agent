const { app, BrowserWindow, Menu } = require('electron');
const path = require('path');

app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('disable-gpu-sandbox');
app.commandLine.appendSwitch('enable-gpu-rasterization');
app.commandLine.appendSwitch('enable-zero-copy');
app.commandLine.appendSwitch('ignore-gpu-blocklist');
app.commandLine.appendSwitch('enable-wayland-ime');

// Vô hiệu hoá hoàn toàn Application Menu để phím ALT không kích hoạt menu
Menu.setApplicationMenu(null);

let mainWindow = null;

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 650,
    backgroundColor: '#0b0f19',
    icon: path.join(__dirname, '..', 'templates', 'icon.png'),
    title: 'Tadu Cloud AI Agent Control Center',
    autoHideMenuBar: false,
    show: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      devTools: false
    }
  });

  mainWindow.setMenu(null);
  mainWindow.setMenuBarVisibility(false);

  // Vô hiệu hoá hoàn toàn phím tắt mở DevTools Console (F12, Ctrl+Shift+I, Ctrl+Shift+J)
  mainWindow.webContents.on('before-input-event', (event, input) => {
    if (input.key === 'F12' || 
       ((input.control || input.meta) && input.shift && (input.key.toLowerCase() === 'i' || input.key.toLowerCase() === 'j' || input.key.toLowerCase() === 'c')) ||
       ((input.control || input.meta) && input.key.toLowerCase() === 'u')) {
      event.preventDefault();
    }
  });

  mainWindow.loadURL('http://127.0.0.1:8888');

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    app.quit();
  });
}

app.whenReady().then(createMainWindow);
