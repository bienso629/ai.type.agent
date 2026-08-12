const path = require('path');
const os = require('os');
let apiConfig;

try {
  apiConfig = require(path.join(__dirname, '../api/vietnam.tphcm/s0/restful-api/pm2.production.json'));
} catch (e) {
  // Bỏ qua nếu không tìm thấy file cấu hình api
  apiConfig = { apps: [{}] };
}

module.exports = {
  apps: [
    {
      name: "tab1-omnivoice",
      cwd: path.join(__dirname, "voiceclone-tts"),
      script: "/bin/bash",
      args: ["-c", "./start.sh"],
      interpreter: "none",
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    },
    // {
    //   name: "tab2-cloudflared-omnivoice",
    //   cwd: path.join(__dirname, ".cloudflared"),
    //   script: "cloudflared",
    //   args: ["tunnel", "--config", "config-omnivoice.yml", "run", "omnivoice-tunnel"],
    //   interpreter: "none",
    //   autorestart: true,
    //   restart_delay: 3000,
    //   max_restarts: 10
    // },
    {
      ...apiConfig.apps[0],
      name: "tab3-apiv1",
      cwd: path.join(__dirname, "../api/vietnam.tphcm/s0/restful-api"),
      autorestart: true,
      restart_delay: 3000,
      max_restarts: 10
    },
    // {
    //   name: "tab4-cloudflared-apiv1",
    //   cwd: path.join(os.homedir(), ".cloudflared"),
    //   script: "cloudflared",
    //   args: [
    //     "tunnel",
    //     "--config",
    //     "config-apiv1.yml",
    //     "run",
    //     "apiv1-tunnel"
    //   ],
    //   interpreter: "none",
    //   autorestart: true,
    //   restart_delay: 3000,
    //   max_restarts: 10
    // }
  ]
};
