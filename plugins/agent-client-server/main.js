const { app, BrowserWindow, dialog } = require('electron');
const path = require('path');
const { spawn, execSync } = require('child_process');
const http = require('http');

// Tương thích với môi trường bảo mật của Ubuntu Linux
app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('disable-gpu-sandbox');

let mainWindow = null;
let pyProcess = null;
const PORT = 8888;
const APP_URL = `http://127.0.0.1:${PORT}`;

// Kiểm tra xem server backend đã sẵn sàng chưa
function checkServerReady(url, maxAttempts = 50, interval = 200) {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const check = () => {
      attempts++;
      http.get(url + '/api/config', (res) => {
        if (res.statusCode === 200) {
          resolve(true);
        } else if (attempts < maxAttempts) {
          setTimeout(check, interval);
        } else {
          resolve(false);
        }
      }).on('error', () => {
        if (attempts < maxAttempts) {
          setTimeout(check, interval);
        } else {
          resolve(false);
        }
      });
    };
    check();
  });
}

// Khởi chạy tiến trình Python Backend
function startPythonBackend() {
  const binaryPath = path.join(__dirname, 'dist', 'tadu-cloud-ai-agent');
  const pythonScript = path.join(__dirname, 'client_ui.py');

  // Ưu tiên chạy binary nếu có, hoặc dùng python3
  let cmd = 'python3';
  let args = [pythonScript, '--no-browser'];

  // Nếu binary độc lập tồn tại thì dùng binary
  const fs = require('fs');
  if (fs.existsSync(binaryPath) && !app.isPackaged) {
    // Có thể dùng python3 trong môi trường dev
    cmd = 'python3';
    args = [pythonScript, '--no-browser'];
  } else if (app.isPackaged) {
    // Khi đã đóng gói Electron
    const packagedBinary = path.join(process.resourcesPath, 'tadu-cloud-ai-agent');
    if (fs.existsSync(packagedBinary)) {
      cmd = packagedBinary;
      args = ['--no-browser'];
    }
  }

  console.log(`[Electron] Khởi động Python backend: ${cmd} ${args.join(' ')}`);
  pyProcess = spawn(cmd, args, {
    cwd: __dirname,
    detached: false,
    stdio: 'pipe'
  });

  pyProcess.stdout.on('data', (data) => {
    console.log(`[Python] ${data.toString().trim()}`);
  });

  pyProcess.stderr.on('data', (data) => {
    console.error(`[Python Err] ${data.toString().trim()}`);
  });

  pyProcess.on('close', (code) => {
    console.log(`[Python] Tiến trình kết thúc với mã: ${code}`);
  });
}

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 650,
    backgroundColor: '#0b0f19',
    icon: path.join(__dirname, 'templates', 'icon.png'),
    title: 'Tadu Cloud AI Agent Control Center',
    autoHideMenuBar: true,
    show: false, // Ẩn cho đến khi nội dung tải xong để không bị nháy trắng
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });

  mainWindow.loadURL(APP_URL);

  // Hỗ trợ phím tắt Reload (Ctrl+R, F5) và DevTools (Ctrl+Shift+I, F12)
  mainWindow.webContents.on('before-input-event', (event, input) => {
    if ((input.control || input.meta) && input.key.toLowerCase() === 'r') {
      mainWindow.reload();
      event.preventDefault();
    }
    if (input.key === 'F5') {
      mainWindow.reload();
      event.preventDefault();
    }
    if (((input.control || input.meta) && input.shift && input.key.toLowerCase() === 'i') || input.key === 'F12') {
      mainWindow.webContents.toggleDevTools();
      event.preventDefault();
    }
  });

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  // 1. Kiểm tra xem server có đang chạy sẵn không
  let isRunning = await checkServerReady(APP_URL, 2, 100);

  if (!isRunning) {
    // Khởi chạy tiến trình Python
    startPythonBackend();
    // Đợi server sẵn sàng (tối đa 15 giây)
    isRunning = await checkServerReady(APP_URL, 60, 250);
  }

  if (isRunning) {
    createMainWindow();
  } else {
    dialog.showErrorBox(
      'Lỗi Khởi Động Backend',
      'Không thể kết nối đến máy chủ Tadu Cloud AI Agent nội bộ trên cổng 8888. Vui lòng kiểm tra lại môi trường Python!'
    );
    app.quit();
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

// Dọn dẹp tiến trình Python khi thoát app
function cleanup() {
  if (pyProcess) {
    console.log('[Electron] Đang dừng tiến trình Python backend...');
    try {
      if (process.platform === 'win32') {
        execSync(`taskkill /pid ${pyProcess.pid} /T /F`);
      } else {
        process.kill(-pyProcess.pid, 'SIGTERM');
      }
    } catch (e) {
      pyProcess.kill('SIGKILL');
    }
    pyProcess = null;
  }
}

app.on('will-quit', cleanup);

app.on('window-all-closed', () => {
  cleanup();
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
