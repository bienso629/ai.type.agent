import type { Request, Response, NextFunction } from 'express'
import { ZodSchema, ZodError } from 'zod'

export function validateBody(schema: ZodSchema) {
  return (req: Request, res: Response, next: NextFunction) => {
    try {
      req.body = schema.parse(req.body)
      next()
    } catch (error) {
      if (error instanceof ZodError) {
        return res.status(400).json({
          success: false,
          error: 'Dữ liệu không hợp lệ',
          details: error.issues.map((e) => ({
            field: e.path.join('.'),
            message: e.message,
          })),
        })
      }
      return res.status(400).json({ success: false, error: 'Dữ liệu gửi lên không đúng định dạng.' })
    }
  }
}
