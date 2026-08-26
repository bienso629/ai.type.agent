import express, { type Request, type Response, type NextFunction } from 'express'
import cors from 'cors'
import { apiRouter } from './routes/index'
import { initDatabase } from './db/database'

// Khởi tạo và đồng bộ Database SQLite
initDatabase()

export const app = express()

// Cấu hình Middleware cơ bản
app.use(
  cors({
    origin: '*',
    credentials: true,
  })
)
app.use(express.json())
app.use(express.urlencoded({ extended: true }))

// Gắn toàn bộ API vào /api
app.use('/api', apiRouter)

// Xử lý lỗi 404 chỉ khi request là /api/...
app.use((req: Request, res: Response, next: NextFunction) => {
  const url = req.originalUrl || req.url || ''
  if (url.startsWith('/api')) {
    return res.status(404).json({ success: false, error: 'Đường dẫn API không tồn tại.' })
  }
  next()
})

// Global Error Handler
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error('❌ Server Error:', err)
  res.status(500).json({
    success: false,
    error: 'Đã có lỗi xảy ra phía máy chủ: ' + err.message,
  })
})
