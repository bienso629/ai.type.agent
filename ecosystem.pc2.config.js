const { execSync } = require('child_process');
const apiConfig = require('D:/projects/api/vietnam.tphcm/s0/restful-api/pm2.production.json');

// Tự động moi đường dẫn thật của thư mục global npm trên máy bác
const npmRoot = execSync('npm root -g').toString().trim();
const n8nPath = `${npmRoot}\\n8n\\bin\\n8n`;

module.exports = {
  apps: [
    // TAB 1: Chatbot (start.py tự khởi động 4 service)
    {
      name: "tab1-chatbot",
      cwd: "D:/projects/apps/chatbot",
      script: "python",
      args: "-X utf8 -u start.py",
      interpreter: "none",
      env: {
        PYTHONIOENCODING: "utf-8",
        PYTHONUTF8: "1"
      },
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },

    // TAB 2: CDN
    {
      name: "tab2-cdn",
      cwd: "D:/projects/apps/cdn",
      script: "start.js",
      interpreter: "node",
      env: { NODE_ENV: "production" },
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },

    // TAB 3: n8n
    {
      name: "tab3-n8n",
      script: n8nPath,
      args: "start",
      exec_mode: "fork",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true,
      max_memory_restart: "1G",
      env: {
        N8N_PORT: 5678,
      }
    },

    // TAB 4: Speech-to-tex (Dùng CMD để activate venv)
    /*
    {
      name: "tab4-sst",
      cwd: "D:/projects/apps/speech2text",
      script: "api.py",
      interpreter: "D:/projects/apps/speech2text/venv/Scripts/python.exe",
      env: {
        PYTHONIOENCODING: "utf-8",
        PYTHONUTF8: "1",
        PYTHONUNBUFFERED: "1" // BẮT BUỘC ĐỂ THẤY LOG PYTHON TRONG PM2
      },
      autorestart: true,
      restart_delay: 3000,
      windowsHide: true
    },
    */

    // TAB 5: 100tiktok
    /*
    {
      name: "tab5-100tiktok",
      cwd: "C:/Users/Wing386/Documents/GitHub/100tiktok",
      script: "cmd",
      args: "/c python app.py",
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      windowsHide: true
    },
    */

    // TAB 6: NodeBB (Git Bash)
    {
      name: "tab6-nodebb",
      cwd: "D:/projects/type",
      script: "C:/Program Files/Git/bin/bash.exe",
      args: "-lc \"./nodebb start\"",
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },

    {
      name: "tab7-cloudflared",
      cwd: "C:/Users/Wing386/.cloudflared",
      script: "cloudflared",
      args: "tunnel run",
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },

    // --- BÊ TỪ PC2 SANG ---
    /*
    {
      name: "tab8-omnivoice",
      cwd: "D:/projects/apps/voiceclone-tts",
      script: "C:/Program Files/Git/bin/bash.exe",
      args: ["-c", "./start.sh"],
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },
    {
      name: "tab8-cloudflared-omnivoice",
      cwd: "C:/Users/Wing386/.cloudflared",
      script: "cloudflared",
      args: [
        "tunnel",
        "--config",
        "config-omnivoice.yml",
        "run",
        "omnivoice-tunnel"
      ],
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },
    */
    {
      ...apiConfig.apps[0],
      name: "tab9-apiv2",
      cwd: "D:/projects/api/vietnam.tphcm/s0/restful-api",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    },
    {
      name: "tab9-cloudflared-apiv2",
      cwd: "C:/Users/Wing386/.cloudflared",
      script: "cloudflared",
      args: [
        "tunnel",
        "--config",
        "config-apiv2.yml",
        "run",
        "apiv2-tunnel"
      ],
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10,
      windowsHide: true
    }
  ]
};
