import type { Request, Response } from 'express'
import bcrypt from 'bcryptjs'
import jwt from 'jsonwebtoken'
import { z } from 'zod'
import { db } from '../db/database'
import { CONFIG } from '../config/env'

export const registerSchema = z.object({
  email: z.string().email('Email không hợp lệ'),
  password: z.string().min(6, 'Mật khẩu phải có ít nhất 6 ký tự'),
  name: z.string().min(2, 'Tên phải có ít nhất 2 ký tự'),
})

export const loginSchema = z.object({
  email: z.string().email('Email không hợp lệ'),
  password: z.string().min(1, 'Vui lòng nhập mật khẩu'),
})

export class AuthController {
  static register(req: Request, res: Response) {
    const { email, password, name } = req.body
    const normalizedEmail = email.toLowerCase().trim()

    const existingUser = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail)
    if (existingUser) {
      return res.status(400).json({ success: false, error: 'Email này đã được đăng ký tài khoản.' })
    }

    const salt = bcrypt.genSaltSync(10)
    const passwordHash = bcrypt.hashSync(password, salt)
    const userId = 'usr_' + Math.random().toString(36).substring(2, 9) + Date.now().toString(36)
    const now = new Date().toISOString()

    db.prepare(`
      INSERT INTO users (id, email, password_hash, name, role, balance, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'user', 0, ?, ?)
    `).run(userId, normalizedEmail, passwordHash, name.trim(), now, now)

    const token = jwt.sign({ id: userId, email: normalizedEmail }, CONFIG.JWT_SECRET, {
      expiresIn: CONFIG.JWT_EXPIRES_IN,
    })

    return res.status(201).json({
      success: true,
      message: 'Đăng ký tài khoản thành công!',
      data: {
        token,
        user: {
          id: userId,
          email: normalizedEmail,
          name: name.trim(),
          role: 'user',
          balance: 0,
        },
      },
    })
  }

  static login(req: Request, res: Response) {
    const { email, password } = req.body
    const normalizedEmail = email.toLowerCase().trim()

    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(normalizedEmail) as
      | { id: string; email: string; password_hash: string; name: string; role: 'user' | 'admin'; balance: number }
      | undefined

    if (!user) {
      return res.status(400).json({ success: false, error: 'Email hoặc mật khẩu không chính xác.' })
    }

    const isMatch = bcrypt.compareSync(password, user.password_hash)
    if (!isMatch) {
      return res.status(400).json({ success: false, error: 'Email hoặc mật khẩu không chính xác.' })
    }

    const token = jwt.sign({ id: user.id, email: user.email }, CONFIG.JWT_SECRET, {
      expiresIn: CONFIG.JWT_EXPIRES_IN,
    })

    return res.json({
      success: true,
      message: 'Đăng nhập thành công!',
      data: {
        token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          balance: user.balance,
        },
      },
    })
  }

  static getMe(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Chưa đăng nhập.' })
    }

    const freshUser = db.prepare('SELECT id, email, name, role, balance, created_at FROM users WHERE id = ?').get(req.user.id)
    return res.json({
      success: true,
      data: freshUser,
    })
  }
}
