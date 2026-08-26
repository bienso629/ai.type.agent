import type { Request, Response } from 'express'
import { z } from 'zod'
import { db } from '../db/database'
import { CONFIG } from '../config/env'

export const createOrderSchema = z.object({
  productId: z.string().min(1, 'Mã sản phẩm không được trống'),
  paymentMethod: z.enum(['balance', 'vietqr', 'momo', 'zalopay']),
})

export class OrderController {
  static createOrder(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Vui lòng đăng nhập để thực hiện mua hàng.' })
    }

    const { productId, paymentMethod } = req.body
    const userId = req.user.id
    const userEmail = req.user.email

    const product = db.prepare('SELECT * FROM products WHERE id = ? AND is_active = 1').get(productId) as any
    if (!product) {
      return res.status(404).json({ success: false, error: 'Sản phẩm không tồn tại hoặc đã tạm dừng bán.' })
    }

    const orderId = 'ORD-' + Math.floor(100000 + Math.random() * 900000)
    const paymentCode = 'MITOM ' + orderId
    const now = new Date().toISOString()

    // 1. THANH TOÁN BẰNG SỐ DƯ VÍ
    if (paymentMethod === 'balance') {
      const user = db.prepare('SELECT balance FROM users WHERE id = ?').get(userId) as { balance: number }
      if (user.balance < product.price) {
        return res.status(400).json({
          success: false,
          error: `Số dư ví không đủ (Hiện có: ${user.balance.toLocaleString('vi-VN')}đ, Cần: ${product.price.toLocaleString('vi-VN')}đ). Vui lòng nạp thêm tiền.`,
        })
      }

      // Xử lý Transaction nguyên tử (Atomic Database Transaction)
      const executePurchase = db.transaction(() => {
        // Trừ tiền user
        const newBalance = user.balance - product.price
        db.prepare('UPDATE users SET balance = ?, updated_at = ? WHERE id = ?').run(newBalance, now, userId)

        // Kiểm tra xem có kho key sẵn sàng giao tự động không
        const availableKey = db.prepare('SELECT id, key_data FROM inventory_keys WHERE product_id = ? AND is_used = 0 LIMIT 1').get(productId) as
          | { id: string; key_data: string }
          | undefined

        let deliveryContent = 'Đơn hàng đã được ghi nhận. Đội ngũ sẽ kích hoạt trong 5-10 phút.'
        let status = 'paid'

        if (availableKey) {
          deliveryContent = availableKey.key_data
          status = 'completed'
          db.prepare('UPDATE inventory_keys SET is_used = 1, order_id = ?, used_at = ? WHERE id = ?').run(orderId, now, availableKey.id)
        }

        const costPrice = product.cost_price || 0
        const profit = product.price - costPrice

        // Tạo bản ghi Order
        db.prepare(`
          INSERT INTO orders (id, user_id, user_email, product_id, product_name, cost_price, amount, profit, status, payment_method, delivery_content, payment_code, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(orderId, userId, userEmail, productId, product.name, costPrice, product.price, profit, status, 'balance', deliveryContent, paymentCode, now, now)

        // Ghi nhận biến động số dư
        const txId = 'TX-' + Math.floor(100000 + Math.random() * 900000)
        db.prepare(`
          INSERT INTO transactions (id, user_id, type, amount, balance_before, balance_after, description, status, payment_method, reference_code, created_at)
          VALUES (?, ?, 'purchase', ?, ?, ?, ?, 'success', 'balance', ?, ?)
        `).run(txId, userId, -product.price, user.balance, newBalance, `Mua ${product.name} (${orderId})`, orderId, now)

        return { orderId, status, deliveryContent, newBalance }
      })

      const result = executePurchase()
      return res.status(201).json({
        success: true,
        message: 'Thanh toán thành công qua số dư ví!',
        data: {
          orderId: result.orderId,
          status: result.status,
          deliveryContent: result.deliveryContent,
          newBalance: result.newBalance,
        },
      })
    }

    // 2. THANH TOÁN BẰNG VIETQR / CHUYỂN KHOẢN
    const costPrice = product.cost_price || 0
    const profit = product.price - costPrice
    const qrUrl = `https://img.vietqr.io/image/${CONFIG.BANK_INFO.BANK_ID}-${CONFIG.BANK_INFO.ACCOUNT_NO}-${CONFIG.BANK_INFO.TEMPLATE}.png?amount=${product.price}&addInfo=${encodeURIComponent(paymentCode)}&accountName=${encodeURIComponent(CONFIG.BANK_INFO.ACCOUNT_NAME)}`

    db.prepare(`
      INSERT INTO orders (id, user_id, user_email, product_id, product_name, cost_price, amount, profit, status, payment_method, qr_code_url, payment_code, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)
    `).run(orderId, userId, userEmail, productId, product.name, costPrice, product.price, profit, paymentMethod, qrUrl, paymentCode, now, now)

    return res.status(201).json({
      success: true,
      message: 'Đơn hàng đã được tạo. Vui lòng quét mã VietQR để hoàn tất thanh toán.',
      data: {
        orderId,
        productName: product.name,
        amount: product.price,
        status: 'pending',
        paymentMethod,
        paymentCode,
        qrCodeUrl: qrUrl,
        bankInfo: CONFIG.BANK_INFO,
      },
    })
  }

  static getMyOrders(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Chưa đăng nhập.' })
    }

    const orders = db.prepare('SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id)
    return res.json({
      success: true,
      data: orders,
    })
  }

  static getOrderById(req: Request, res: Response) {
    const { id } = req.params
    const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(id) as any
    if (!order) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy đơn hàng.' })
    }

    // Nếu không phải admin và không phải chính chủ đơn thì chặn
    if (req.user?.role !== 'admin' && req.user?.id !== order.user_id) {
      return res.status(403).json({ success: false, error: 'Bạn không có quyền xem đơn hàng này.' })
    }

    return res.json({
      success: true,
      data: order,
    })
  }
}
