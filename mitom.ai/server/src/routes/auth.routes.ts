import { Router } from 'express'
import { AuthController, registerSchema, loginSchema } from '../controllers/auth.controller'
import { validateBody } from '../middlewares/validate.middleware'
import { authMiddleware } from '../middlewares/auth.middleware'

export const authRouter = Router()

authRouter.post('/register', validateBody(registerSchema), AuthController.register)
authRouter.post('/login', validateBody(loginSchema), AuthController.login)
authRouter.get('/me', authMiddleware, AuthController.getMe)
