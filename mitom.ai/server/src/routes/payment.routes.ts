import { Router } from 'express'
import { PaymentController, topUpSchema, confirmTopUpSchema } from '../controllers/payment.controller'
import { authMiddleware } from '../middlewares/auth.middleware'
import { validateBody } from '../middlewares/validate.middleware'

export const paymentRouter = Router()

paymentRouter.post('/topup', authMiddleware, validateBody(topUpSchema), PaymentController.createTopUp)
paymentRouter.post('/topup/confirm', authMiddleware, validateBody(confirmTopUpSchema), PaymentController.confirmTopUp)
paymentRouter.post('/webhook', PaymentController.webhookReceiver)
paymentRouter.get('/transactions', authMiddleware, PaymentController.getMyTransactions)
