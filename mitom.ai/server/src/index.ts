import { app } from './app'
import { CONFIG } from './config/env'

const port = CONFIG.PORT

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 MitomAI Backend Server đang chạy tại: http://localhost:${port}`)
  console.log(`📡 API Health Endpoint: http://localhost:${port}/api/health`)
})
