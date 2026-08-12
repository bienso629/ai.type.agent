const { execSync } = require('child_process');
const apiConfig = require('/home/yenai/projects/api/vietnam.tphcm/s0/restful-api/pm2.production.json');

// Lấy đường dẫn thực tế của n8n trên Ubuntu (bỏ qua lệnh của Windows)
let n8nPath = 'n8n';
try {
  n8nPath = execSync('which n8n').toString().trim() || 'n8n';
} catch (e) {
  console.log('Không tìm thấy n8n trong PATH, pm2 sẽ tự động tìm kiếm.');
}

module.exports = {
  apps: [
    // TAB 1: Chatbot (start.py tự khởi động 4 service)
    {
      name: "tab1-chatbot",
      cwd: "/home/yenai/projects/apps/chatbot",
      script: "/home/yenai/projects/apps/chatbot/venv/bin/python3",
      args: "-X utf8 -u start.py",
      interpreter: "none",
      env: {
        PYTHONIOENCODING: "utf-8",
        PYTHONUTF8: "1"
      },
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
      // Đã bỏ windowsHide vì trên Ubuntu không cần thiết
    },

    // TAB 2: CDN
    {
      name: "tab2-cdn",
      cwd: "/home/yenai/projects/apps/cdn",
      script: "start.js",
      interpreter: "node",
      env: { 
        NODE_ENV: "production",
        API_KEY: "type-vn-secret-key-2026-yenai-dep-trai"
      },
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
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
      max_memory_restart: "1G",
      env: {
        N8N_PORT: 5678,
        WEBHOOK_URL: "https://n8n.type.vn/",
        N8N_HOST: "0.0.0.0",
        N8N_LISTEN_ADDRESS: "0.0.0.0"
      }
    },

    // TAB 4: Speech-to-tex (Dùng bin/python để activate venv trên Ubuntu)
    /*
    {
      name: "tab4-sst",
      cwd: "/home/yenai/projects/apps/speech2text",
      script: "api.py",
      interpreter: "/home/yenai/projects/apps/speech2text/venv/bin/python", // Ubuntu dùng bin/ thay vì Scripts/
      env: {
        PYTHONIOENCODING: "utf-8",
        PYTHONUTF8: "1",
        PYTHONUNBUFFERED: "1" // BẮT BUỘC ĐỂ THẤY LOG PYTHON TRONG PM2
      },
      autorestart: true,
      restart_delay: 3000
    },
    */

    // TAB 5: 100tiktok
    /*
    {
      name: "tab5-100tiktok",
      cwd: "/home/yenai/Documents/GitHub/100tiktok", // Lưu ý: Bác nhớ đổi tên user Wing386 thành tên user trên Ubuntu nếu cần (ví dụ /home/ubuntu/...)
      script: "python3", // Đổi từ lệnh cmd sang chạy python trực tiếp trên Ubuntu
      args: "app.py",
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000
    },
    */

    // TAB 6: NodeBB
    {
      name: "tab6-nodebb",
      cwd: "/home/yenai/projects/type",
      script: "loader.js",
      args: "--no-daemon",
      interpreter: "node",
      env: {
        daemon: "false"
      },
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    },

    {
      name: "tab7-cloudflared",
      cwd: "/home/yenai/.cloudflared", // Lưu ý user name
      script: "cloudflared",
      args: "tunnel run",
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    },

    // --- BÊ TỪ PC2 SANG ---
    /*
    {
      name: "tab8-omnivoice",
      cwd: "/home/yenai/projects/apps/voiceclone-tts",
      script: "bash",
      args: ["-c", "./start.sh"],
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    },
    {
      name: "tab8-cloudflared-omnivoice",
      cwd: "/home/yenai/.cloudflared",
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
      max_restarts: 10
    },
    */
    {
      ...apiConfig.apps[0],
      name: "tab9-apiv3",
      cwd: "/home/yenai/projects/api/vietnam.tphcm/s0/restful-api",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    }
  ]
};
