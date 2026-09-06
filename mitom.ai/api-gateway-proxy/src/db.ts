import { createClient, Client } from '@libsql/client'
import path from 'path'
import dotenv from 'dotenv'

dotenv.config()

let dbClient: Client | null = null

export function getDbClient(): Client {
  if (!dbClient) {
    const dbUrl = process.env.DATABASE_URL || 'file:../payload-cms-app.db'
    dbClient = createClient({
      url: dbUrl,
    })
  }
  return dbClient
}

export interface UserAccount {
  id: number
  email: string
  name: string | null
  balance: number
  customerCode: string | null
  apiKey: string
  role: string | null
}

/**
 * Xác thực API Key và kiểm tra số dư của tài khoản
 */
export async function authenticateAndCheckBalance(apiKey: string): Promise<{
  success: boolean
  message?: string
  user?: UserAccount
}> {
  if (!apiKey || typeof apiKey !== 'string') {
    return {
      success: false,
      message: 'Thiếu API Key truy cập hoặc định dạng không hợp lệ.',
    }
  }

  const cleanKey = apiKey.trim()
  const db = getDbClient()

  try {
    const rs = await db.execute({
      sql: 'SELECT id, email, name, balance, customer_code as customerCode, api_key as apiKey, role FROM users WHERE api_key = ? LIMIT 1',
      args: [cleanKey],
    })

    if (!rs.rows || rs.rows.length === 0) {
      return {
        success: false,
        message: 'API Key không hợp lệ hoặc tài khoản không tồn tại trên hệ thống Mì Tôm AI.',
      }
    }

    const row = rs.rows[0] as any
    const user: UserAccount = {
      id: Number(row.id),
      email: String(row.email),
      name: row.name ? String(row.name) : null,
      balance: Number(row.balance) || 0,
      customerCode: row.customerCode ? String(row.customerCode) : null,
      apiKey: String(row.apiKey),
      role: row.role ? String(row.role) : 'user',
    }

    // Kiểm tra số dư tài khoản
    if (user.balance <= 0) {
      return {
        success: false,
        message: `Số dư trong tài khoản của bạn hiện tại là 0 VNĐ. Vui lòng nạp thêm tiền qua VietQR tại https://mitom.ai để tiếp tục sử dụng API.`,
        user,
      }
    }

    return {
      success: true,
      user,
    }
  } catch (error: any) {
    console.error('[DB Auth Error]:', error)
    return {
      success: false,
      message: 'Lỗi hệ thống khi kiểm tra thông tin tài khoản: ' + error?.message,
    }
  }
}

/**
 * Trừ số dư tài khoản sau khi gọi model thành công
 */
export async function deductBalance(userId: number, amountVnd: number): Promise<boolean> {
  if (amountVnd <= 0) return true
  const db = getDbClient()

  try {
    await db.execute({
      sql: 'UPDATE users SET balance = MAX(0, balance - ?) WHERE id = ?',
      args: [amountVnd, userId],
    })
    return true
  } catch (err) {
    console.error('[DB Deduct Balance Error]:', err)
    return false
  }
}
