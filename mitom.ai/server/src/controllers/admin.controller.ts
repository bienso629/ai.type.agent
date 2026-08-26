import type { Request, Response } from 'express'
import { z } from 'zod'
import { db } from '../db/database'

export class AdminController {
  static getDashboardStats(_req: Request, res: Response) {
    const totalUsers = (db.prepare('SELECT COUNT(*) as count FROM users').get() as any).count
    const totalOrders = (db.prepare('SELECT COUNT(*) as count FROM orders').get() as any).count

    // Tính Doanh thu (Giá bán), Tiền vốn (Giá gốc) và Lợi nhuận ròng
    const revRow = db.prepare(`
      SELECT 
        COALESCE(SUM(amount), 0) as totalRevenue,
        COALESCE(SUM(cost_price), 0) as totalCost,
        COALESCE(SUM(profit), 0) as totalProfit
      FROM orders 
      WHERE status IN ('paid', 'completed')
    `).get() as any

    const totalRevenue = revRow.totalRevenue || 0
    const totalCost = revRow.totalCost || 0
    const totalProfit = revRow.totalProfit || (totalRevenue - totalCost)
    const profitMarginPct = totalRevenue > 0 ? Math.round((totalProfit / totalRevenue) * 100) : 0

    const availableKeys = (db.prepare('SELECT COUNT(*) as count FROM inventory_keys WHERE is_used = 0').get() as any).count

    const recentOrders = db.prepare('SELECT * FROM orders ORDER BY created_at DESC LIMIT 6').all()
    const recentTransactions = db.prepare('SELECT * FROM transactions ORDER BY created_at DESC LIMIT 6').all()

    return res.json({
      success: true,
      data: {
        stats: {
          totalUsers,
          totalOrders,
          totalRevenue,
          totalCost,
          totalProfit,
          profitMarginPct,
          availableKeys,
        },
        recentOrders,
        recentTransactions,
      },
    })
  }

  static listAllUsers(_req: Request, res: Response) {
    const users = db.prepare('SELECT id, email, name, role, balance, created_at FROM users ORDER BY created_at DESC').all()
    return res.json({
      success: true,
      data: users,
    })
  }

  static updateUserBalance(req: Request, res: Response) {
    const { userId, amount, reason } = req.body
    if (!userId || typeof amount !== 'number') {
      return res.status(400).json({ success: false, error: 'Thiếu thông tin người dùng hoặc số tiền.' })
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any
    if (!user) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy người dùng.' })
    }

    const newBalance = user.balance + amount
    const now = new Date().toISOString()
    const txId = 'TX-ADJ-' + Math.floor(100000 + Math.random() * 900000)

    db.transaction(() => {
      db.prepare('UPDATE users SET balance = ?, updated_at = ? WHERE id = ?').run(newBalance, now, userId)
      db.prepare(`
        INSERT INTO transactions (id, user_id, type, amount, balance_before, balance_after, description, status, reference_code, created_at)
        VALUES (?, ?, 'admin_adjust', ?, ?, ?, ?, 'success', 'ADMIN', ?)
      `).run(txId, userId, amount, user.balance, newBalance, reason || 'Admin điều chỉnh số dư', now)
    })()

    return res.json({
      success: true,
      message: `Đã cập nhật số dư cho user ${user.email} thành công!`,
      data: { userId, newBalance },
    })
  }

  static updateProductPricing(req: Request, res: Response) {
    const { productId, costPrice, salePrice } = req.body
    if (!productId || typeof costPrice !== 'number' || typeof salePrice !== 'number') {
      return res.status(400).json({ success: false, error: 'Vui lòng cung cấp mã sản phẩm, giá gốc và giá bán hợp lệ.' })
    }

    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as any
    if (!product) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy sản phẩm.' })
    }

    db.prepare('UPDATE products SET cost_price = ?, price = ? WHERE id = ?').run(costPrice, salePrice, productId)

    return res.json({
      success: true,
      message: `Đã cập nhật: Giá gốc ${costPrice.toLocaleString('vi-VN')}đ | Giá bán ${salePrice.toLocaleString('vi-VN')}đ (Lãi ${(salePrice - costPrice).toLocaleString('vi-VN')}đ)`,
      data: {
        productId,
        costPrice,
        salePrice,
        profit: salePrice - costPrice,
      },
    })
  }

  static listAllOrders(_req: Request, res: Response) {
    const orders = db.prepare('SELECT * FROM orders ORDER BY created_at DESC').all()
    return res.json({
      success: true,
      data: orders,
    })
  }

  static updateOrderStatus(req: Request, res: Response) {
    const { orderId, status, deliveryContent } = req.body
    const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId) as any
    if (!order) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy đơn hàng.' })
    }

    const now = new Date().toISOString()
    db.prepare(`
      UPDATE orders
      SET status = ?, delivery_content = COALESCE(?, delivery_content), updated_at = ?
      WHERE id = ?
    `).run(status, deliveryContent || null, now, orderId)

    return res.json({
      success: true,
      message: 'Cập nhật trạng thái đơn hàng thành công!',
    })
  }

  static addInventoryKey(req: Request, res: Response) {
    const { productId, keyData } = req.body
    if (!productId || !keyData) {
      return res.status(400).json({ success: false, error: 'Vui lòng cung cấp mã sản phẩm và dữ liệu key.' })
    }

    const keyId = 'key_' + Math.random().toString(36).substring(2, 9)
    db.prepare(`
      INSERT INTO inventory_keys (id, product_id, key_data, is_used, created_at)
      VALUES (?, ?, ?, 0, datetime('now'))
    `).run(keyId, productId, keyData.trim())

    return res.status(201).json({
      success: true,
      message: 'Đã thêm key/tài khoản mới vào kho thành công!',
    })
  }

  static listInventoryKeys(_req: Request, res: Response) {
    const keys = db.prepare(`
      SELECT k.*, p.name as product_name
      FROM inventory_keys k
      LEFT JOIN products p ON k.product_id = p.id
      ORDER BY k.created_at DESC
    `).all()

    return res.json({
      success: true,
      data: keys,
    })
  }
}
