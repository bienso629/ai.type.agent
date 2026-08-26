import { Router } from 'express'
import { AdminController } from '../controllers/admin.controller'
import { authMiddleware, requireAdmin } from '../middlewares/auth.middleware'

export const adminRouter = Router()

// Tất cả các route bên dưới bắt buộc có quyền Admin
adminRouter.use(authMiddleware, requireAdmin)

adminRouter.get('/stats', AdminController.getDashboardStats)
adminRouter.get('/users', AdminController.listAllUsers)
adminRouter.post('/users/balance', AdminController.updateUserBalance)
adminRouter.post('/products/pricing', AdminController.updateProductPricing)
adminRouter.get('/orders', AdminController.listAllOrders)
adminRouter.put('/orders/status', AdminController.updateOrderStatus)
adminRouter.post('/inventory', AdminController.addInventoryKey)
adminRouter.get('/inventory', AdminController.listInventoryKeys)
