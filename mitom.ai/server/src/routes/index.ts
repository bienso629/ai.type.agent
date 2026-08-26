import { Router } from 'express'
import { authRouter } from './auth.routes'
import { productRouter } from './product.routes'
import { orderRouter } from './order.routes'
import { paymentRouter } from './payment.routes'
import { adminRouter } from './admin.routes'

export const apiRouter = Router()

// Health check endpoint
apiRouter.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    service: 'MitomAI Backend API',
    uptime: process.uptime(),
  })
})

apiRouter.use('/auth', authRouter)
apiRouter.use('/products', productRouter)
apiRouter.use('/orders', orderRouter)
apiRouter.use('/payments', paymentRouter)
apiRouter.use('/admin', adminRouter)
