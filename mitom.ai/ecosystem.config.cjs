module.exports = {
  apps: [
    {
      name: 'mitom.ai',
      script: 'node_modules/next/dist/bin/next',
      args: 'dev -p 30000',
      cwd: '/home/yenai/Documents/Projects/Typing/apps/mitom.ai',
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '2G',
      env: {
        NODE_ENV: 'development',
        NODE_OPTIONS: '--no-deprecation',
      },
    },
  ],
}
