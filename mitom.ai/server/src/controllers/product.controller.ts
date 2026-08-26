import type { Request, Response } from 'express'
import { z } from 'zod'
import { db } from '../db/database'

export const productSchema = z.object({
  id: z.string().min(1, 'ID sản phẩm không được trống'),
  name: z.string().min(1, 'Tên sản phẩm không được trống'),
  provider: z.string().min(1, 'Nhà cung cấp không được trống'),
  tag: z.enum(['chat', 'image', 'code', 'token']),
  badge: z.string().optional(),
  desc: z.string().min(1, 'Mô tả không được trống'),
  price: z.number().int().min(0, 'Giá phải là số nguyên không âm'),
  features: z.array(z.string()),
  accent: z.string().default('#34d399'),
  initials: z.string().default('AI'),
  eta: z.string().default('Kích hoạt ~5 phút'),
  stock: z.number().int().default(99),
})

export class ProductController {
  static getAllProducts(_req: Request, res: Response) {
    const rawProducts = db.prepare('SELECT * FROM products WHERE is_active = 1 ORDER BY price ASC').all() as any[]

    const products = rawProducts.map((p) => ({
      ...p,
      features: JSON.parse(p.features || '[]'),
    }))

    return res.json({
      success: true,
      data: products,
    })
  }

  static getProductById(req: Request, res: Response) {
    const { id } = req.params
    const p = db.prepare('SELECT * FROM products WHERE id = ?').get(id) as any

    if (!p) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy sản phẩm.' })
    }

    return res.json({
      success: true,
      data: {
        ...p,
        features: JSON.parse(p.features || '[]'),
      },
    })
  }

  static createProduct(req: Request, res: Response) {
    const data = req.body
    const existing = db.prepare('SELECT id FROM products WHERE id = ?').get(data.id)
    if (existing) {
      return res.status(400).json({ success: false, error: 'Mã ID sản phẩm này đã tồn tại.' })
    }

    db.prepare(`
      INSERT INTO products (id, name, provider, tag, badge, desc, price, features, accent, initials, eta, stock, is_active, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))
    `).run(
      data.id,
      data.name,
      data.provider,
      data.tag,
      data.badge || null,
      data.desc,
      data.price,
      JSON.stringify(data.features || []),
      data.accent || '#34d399',
      data.initials || 'AI',
      data.eta || 'Kích hoạt ~5 phút',
      data.stock ?? 99
    )

    return res.status(201).json({
      success: true,
      message: 'Tạo sản phẩm mới thành công!',
    })
  }

  static updateProduct(req: Request, res: Response) {
    const { id } = req.params
    const data = req.body

    const existing = db.prepare('SELECT id FROM products WHERE id = ?').get(id)
    if (!existing) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy sản phẩm cần cập nhật.' })
    }

    db.prepare(`
      UPDATE products
      SET name = ?, provider = ?, tag = ?, badge = ?, desc = ?, price = ?, features = ?, accent = ?, initials = ?, eta = ?, stock = ?
      WHERE id = ?
    `).run(
      data.name,
      data.provider,
      data.tag,
      data.badge || null,
      data.desc,
      data.price,
      JSON.stringify(data.features || []),
      data.accent,
      data.initials,
      data.eta,
      data.stock,
      id
    )

    return res.json({
      success: true,
      message: 'Cập nhật sản phẩm thành công!',
    })
  }

  static deleteProduct(req: Request, res: Response) {
    const { id } = req.params
    db.prepare('UPDATE products SET is_active = 0 WHERE id = ?').run(id)
    return res.json({
      success: true,
      message: 'Đã ẩn sản phẩm khỏi danh sách bán.',
    })
  }
}
