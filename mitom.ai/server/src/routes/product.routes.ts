import { Router } from 'express'
import { ProductController, productSchema } from '../controllers/product.controller'
import { authMiddleware, requireAdmin } from '../middlewares/auth.middleware'
import { validateBody } from '../middlewares/validate.middleware'

export const productRouter = Router()

productRouter.get('/', ProductController.getAllProducts)
productRouter.get('/:id', ProductController.getProductById)
productRouter.post('/', authMiddleware, requireAdmin, validateBody(productSchema), ProductController.createProduct)
productRouter.put('/:id', authMiddleware, requireAdmin, validateBody(productSchema.omit({ id: true })), ProductController.updateProduct)
productRouter.delete('/:id', authMiddleware, requireAdmin, ProductController.deleteProduct)
