module.exports = {
  apps: [
    {
      name: 'mitom.ai',
      script: './node_modules/next/dist/bin/next',
      args: 'start -p 30000',
      cwd: '/var/www/vhosts/mitom.ai/app',
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '2G',
      env: {
        NODE_ENV: 'production',
        NODE_OPTIONS: '--no-deprecation',
        PORT: '30000',
      },
    },
  ],
}
