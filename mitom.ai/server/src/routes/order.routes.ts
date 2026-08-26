import { Router } from 'express'
import { OrderController, createOrderSchema } from '../controllers/order.controller'
import { authMiddleware } from '../middlewares/auth.middleware'
import { validateBody } from '../middlewares/validate.middleware'

export const orderRouter = Router()

orderRouter.post('/', authMiddleware, validateBody(createOrderSchema), OrderController.createOrder)
orderRouter.get('/my', authMiddleware, OrderController.getMyOrders)
orderRouter.get('/:id', authMiddleware, OrderController.getOrderById)
