import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'

export const dynamic = 'force-dynamic'

async function getCurrentUser() {
  const cookieStore = await cookies()
  const sessionToken = cookieStore.get('mitom_session')?.value
  if (!sessionToken) return null
  const session = await verifySessionToken(sessionToken)
  if (!session || !session.email) return null
  const payload = await getPayload({ config: configPromise })
  const res = await payload.find({
    collection: 'users',
    where: { email: { equals: session.email } },
    limit: 1,
  })
  return res.docs && res.docs.length > 0 ? res.docs[0] : null
}

// GET: Lấy hạn mức ngày/tháng và số dư tài khoản hiện tại của người dùng
export async function GET() {
  try {
    const user = await getCurrentUser()
    if (!user) {
      return NextResponse.json({ success: false, error: 'Chưa xác thực.' }, { status: 401 })
    }
    return NextResponse.json({
      success: true,
      balance: Number(user.balance) || 0,
      dailyLimit: user.dailyLimit ?? 0,
      monthlyLimit: user.monthlyLimit ?? 0,
    })
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}

// PATCH: Người dùng tự điều chỉnh hạn mức ngày/tháng của chính mình
export async function PATCH(request: Request) {
  try {
    const user = await getCurrentUser()
    if (!user) {
      return NextResponse.json({ success: false, error: 'Chưa xác thực.' }, { status: 401 })
    }

    const body = await request.json().catch(() => ({}))
    const data: Record<string, number> = {}

    const userBalance = Number(user.balance) || 0

    if (body.dailyLimit !== undefined) {
      const v = Number(body.dailyLimit)
      if (!Number.isFinite(v) || v < 0 || v > 100000000) {
        return NextResponse.json(
          { success: false, error: 'Hạn mức ngày không hợp lệ (0 - 100.000.000 VNĐ).' },
          { status: 400 },
        )
      }
      if (v > userBalance) {
        return NextResponse.json(
          {
            success: false,
            error: `Hạn mức ngày (${v.toLocaleString('vi-VN')} đ) không được vượt quá số dư tài khoản hiện có (${userBalance.toLocaleString('vi-VN')} đ).`,
          },
          { status: 400 },
        )
      }
      data.dailyLimit = v
    }

    if (body.monthlyLimit !== undefined) {
      const v = Number(body.monthlyLimit)
      if (!Number.isFinite(v) || v < 0 || v > 1000000000) {
        return NextResponse.json(
          { success: false, error: 'Hạn mức tháng không hợp lệ (0 - 1.000.000.000 VNĐ).' },
          { status: 400 },
        )
      }
      if (v > userBalance) {
        return NextResponse.json(
          {
            success: false,
            error: `Hạn mức tháng (${v.toLocaleString('vi-VN')} đ) không được vượt quá số dư tài khoản hiện có (${userBalance.toLocaleString('vi-VN')} đ).`,
          },
          { status: 400 },
        )
      }
      data.monthlyLimit = v
    }

    if (Object.keys(data).length === 0) {
      return NextResponse.json({ success: false, error: 'Không có dữ liệu cần cập nhật.' }, { status: 400 })
    }

    const payload = await getPayload({ config: configPromise })
    const updated = await payload.update({ collection: 'users', id: user.id, data })

    return NextResponse.json({
      success: true,
      balance: Number(updated.balance) || 0,
      dailyLimit: updated.dailyLimit ?? 0,
      monthlyLimit: updated.monthlyLimit ?? 0,
      message: 'Đã lưu hạn mức thành công.',
    })
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
