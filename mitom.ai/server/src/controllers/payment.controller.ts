import type { Request, Response } from 'express'
import { z } from 'zod'
import { db } from '../db/database'
import { CONFIG } from '../config/env'

export const topUpSchema = z.object({
  amount: z.number().int().min(10000, 'Số tiền nạp tối thiểu là 10.000đ'),
})

export const confirmTopUpSchema = z.object({
  transactionId: z.string().min(1, 'Mã giao dịch không được trống'),
})

export class PaymentController {
  static createTopUp(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Vui lòng đăng nhập để nạp tiền.' })
    }

    const { amount } = req.body
    const userId = req.user.id

    // Tính % khuyến mãi
    let bonusPct = 0
    if (amount >= 1000000) bonusPct = 15
    else if (amount >= 500000) bonusPct = 10
    else if (amount >= 200000) bonusPct = 5

    const bonusAmount = Math.round((amount * bonusPct) / 100)
    const totalCredit = amount + bonusAmount

    const txCode = 'NAP' + Math.floor(100000 + Math.random() * 900000)
    const txId = 'TX-' + txCode
    const now = new Date().toISOString()

    const user = db.prepare('SELECT balance FROM users WHERE id = ?').get(userId) as { balance: number }

    db.prepare(`
      INSERT INTO transactions (id, user_id, type, amount, balance_before, balance_after, description, status, payment_method, reference_code, created_at)
      VALUES (?, ?, 'topup', ?, ?, ?, ?, 'pending', 'vietqr', ?, ?)
    `).run(
      txId,
      userId,
      totalCredit,
      user.balance,
      user.balance + totalCredit,
      `Nạp ${amount.toLocaleString('vi-VN')}đ (Thưởng ${bonusAmount.toLocaleString('vi-VN')}đ)`,
      txCode,
      now
    )

    const qrUrl = `https://img.vietqr.io/image/${CONFIG.BANK_INFO.BANK_ID}-${CONFIG.BANK_INFO.ACCOUNT_NO}-${CONFIG.BANK_INFO.TEMPLATE}.png?amount=${amount}&addInfo=${encodeURIComponent(txCode)}&accountName=${encodeURIComponent(CONFIG.BANK_INFO.ACCOUNT_NAME)}`

    return res.status(201).json({
      success: true,
      message: 'Khởi tạo yêu cầu nạp tiền thành công.',
      data: {
        transactionId: txId,
        paymentCode: txCode,
        amount,
        bonusAmount,
        totalCredit,
        qrCodeUrl: qrUrl,
        bankInfo: CONFIG.BANK_INFO,
      },
    })
  }

  static confirmTopUp(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Chưa đăng nhập.' })
    }

    const { transactionId } = req.body
    const tx = db.prepare('SELECT * FROM transactions WHERE id = ?').get(transactionId) as any

    if (!tx) {
      return res.status(404).json({ success: false, error: 'Không tìm thấy giao dịch nạp tiền.' })
    }

    if (tx.status === 'success') {
      return res.json({ success: true, message: 'Giao dịch này đã được xác nhận trước đó.' })
    }

    // Chỉ cho phép chủ giao dịch hoặc admin xác nhận
    if (req.user.role !== 'admin' && req.user.id !== tx.user_id) {
      return res.status(403).json({ success: false, error: 'Không có quyền xác nhận giao dịch này.' })
    }

    const executeConfirm = db.transaction(() => {
      const user = db.prepare('SELECT balance FROM users WHERE id = ?').get(tx.user_id) as { balance: number }
      const newBalance = user.balance + tx.amount
      const now = new Date().toISOString()

      db.prepare('UPDATE users SET balance = ?, updated_at = ? WHERE id = ?').run(newBalance, now, tx.user_id)
      db.prepare('UPDATE transactions SET status = "success", balance_before = ?, balance_after = ? WHERE id = ?').run(
        user.balance,
        newBalance,
        tx.id
      )

      return newBalance
    })

    const newBalance = executeConfirm()

    return res.json({
      success: true,
      message: 'Xác nhận nạp tiền thành công! Số dư đã được cộng vào tài khoản.',
      data: {
        transactionId: tx.id,
        newBalance,
      },
    })
  }

  static webhookReceiver(req: Request, res: Response) {
    const payload = req.body
    console.log('🔔 Nhận Webhook thanh toán:', JSON.stringify(payload))

    // Định dạng nội dung chuyển khoản từ Webhook ngân hàng (Casso / SeAPay / PayOS)
    // Giả sử body có: { description: 'NAP123456' hoặc 'MITOM ORD-123456', amount: 500000, error: 0 }
    const description = (payload.description || payload.content || payload.orderCode || '').toString()
    const amount = Number(payload.amount || payload.transferAmount || 0)

    if (!description) {
      return res.json({ success: true, message: 'Bỏ qua webhook không có nội dung' })
    }

    const now = new Date().toISOString()

    // 1. Kiểm tra nếu là Nạp tiền: NAP...
    const topupMatch = description.match(/NAP\d+/i)
    if (topupMatch) {
      const txCode = topupMatch[0].toUpperCase()
      const tx = db.prepare('SELECT * FROM transactions WHERE reference_code = ? AND status = "pending"').get(txCode) as any

      if (tx) {
        const user = db.prepare('SELECT balance FROM users WHERE id = ?').get(tx.user_id) as { balance: number }
        const newBalance = user.balance + tx.amount

        db.prepare('UPDATE users SET balance = ?, updated_at = ? WHERE id = ?').run(newBalance, now, tx.user_id)
        db.prepare('UPDATE transactions SET status = "success", balance_before = ?, balance_after = ? WHERE id = ?').run(
          user.balance,
          newBalance,
          tx.id
        )
        console.log(`✅ Webhook: Đã cộng ${tx.amount}đ cho user ${tx.user_id}`)
        return res.json({ success: true, message: 'Đã xử lý nạp tiền thành công qua Webhook' })
      }
    }

    // 2. Kiểm tra nếu là Thanh toán đơn hàng: ORD-123456
    const orderMatch = description.match(/ORD-\d+/i)
    if (orderMatch) {
      const orderId = orderMatch[0].toUpperCase()
      const order = db.prepare('SELECT * FROM orders WHERE id = ? AND status = "pending"').get(orderId) as any

      if (order) {
        // Tìm key bản quyền
        const availableKey = db.prepare('SELECT id, key_data FROM inventory_keys WHERE product_id = ? AND is_used = 0 LIMIT 1').get(order.product_id) as
          | { id: string; key_data: string }
          | undefined

        let deliveryContent = 'Đã nhận thanh toán qua QR. Kích hoạt trong 5 phút.'
        let status = 'paid'

        if (availableKey) {
          deliveryContent = availableKey.key_data
          status = 'completed'
          db.prepare('UPDATE inventory_keys SET is_used = 1, order_id = ?, used_at = ? WHERE id = ?').run(orderId, now, availableKey.id)
        }

        db.prepare('UPDATE orders SET status = ?, delivery_content = ?, updated_at = ? WHERE id = ?').run(
          status,
          deliveryContent,
          now,
          orderId
        )

        console.log(`✅ Webhook: Đã kích hoạt đơn hàng ${orderId}`)
        return res.json({ success: true, message: 'Đã xử lý đơn hàng thành công qua Webhook' })
      }
    }

    return res.json({ success: true, message: 'Webhook đã tiếp nhận' })
  }

  static getMyTransactions(req: Request, res: Response) {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Chưa đăng nhập.' })
    }

    const txs = db.prepare('SELECT * FROM transactions WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id)
    return res.json({
      success: true,
      data: txs,
    })
  }
}
