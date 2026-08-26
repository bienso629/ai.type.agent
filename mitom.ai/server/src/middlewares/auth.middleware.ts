import type { Request, Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { CONFIG } from '../config/env'
import { db } from '../db/database'

export interface AuthUser {
  id: string
  email: string
  name: string
  role: 'user' | 'admin'
  balance: number
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser
    }
  }
}

export function authMiddleware(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Chưa đăng nhập hoặc thiếu mã xác thực.' })
  }

  const token = authHeader.split(' ')[1]
  try {
    const decoded = jwt.verify(token, CONFIG.JWT_SECRET) as { id: string; email: string }
    const user = db.prepare('SELECT id, email, name, role, balance FROM users WHERE id = ?').get(decoded.id) as AuthUser | undefined

    if (!user) {
      return res.status(401).json({ success: false, error: 'Tài khoản không tồn tại hoặc đã bị khóa.' })
    }

    req.user = user
    next()
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.' })
  }
}

export function optionalAuthMiddleware(req: Request, _res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1]
    try {
      const decoded = jwt.verify(token, CONFIG.JWT_SECRET) as { id: string }
      const user = db.prepare('SELECT id, email, name, role, balance FROM users WHERE id = ?').get(decoded.id) as AuthUser | undefined
      if (user) {
        req.user = user
      }
    } catch {
      // Ignored for optional auth
    }
  }
  next()
}

export function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ success: false, error: 'Từ chối truy cập: Bạn không có quyền Quản trị viên (Admin).' })
  }
  next()
}
