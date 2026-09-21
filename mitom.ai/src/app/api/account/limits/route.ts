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

    // Đồng bộ trực tiếp hạn mức mới sang AstraFlow (scloudsg.com) nếu người dùng đã có API Key
    let astraflowSynced = false
    const userApiKey = String((user as any).apiKey || '').trim()

    if (userApiKey) {
      try {
        const { callUCloudApi } = await import('@/lib/ucloudClient')
        const { formatUsdLimitForVnd } = await import('@/lib/currency')

        // 1. Tìm keyId của user trong collection api-keys
        const keyRes = await payload.find({
          collection: 'api-keys',
          where: {
            or: [
              { secretKey: { equals: userApiKey } },
              { maskedKey: { equals: userApiKey } },
            ],
          },
          overrideAccess: true,
          limit: 1,
        })

        let targetKeyId = (keyRes?.docs?.[0] as any)?.keyId || ''

        // 2. Nếu không thấy keyId trong database, truy vấn danh sách key trực tiếp từ AstraFlow
        if (!targetKeyId) {
          try {
            const listRes: any = await callUCloudApi({ Action: 'ListUMInferAPIKey' })
            const allKeys = Array.isArray(listRes?.Data) ? listRes.Data : []
            const matchedKey = allKeys.find((k: any) => k.Key === userApiKey || k.SecretKey === userApiKey)
            if (matchedKey?.KeyId) {
              targetKeyId = matchedKey.KeyId
            }
          } catch {
            // bỏ qua lỗi list nếu API không phản hồi
          }
        }

        // 3. Gọi lệnh UpdateUMInferAPIKey để cập nhật lên AstraFlow
        if (targetKeyId) {
          const newDailyVnd = Number(updated.dailyLimit) || 0
          const newMonthlyVnd = Number(updated.monthlyLimit) || 0
          const curBalance = Number(updated.balance) || 0

          // Quy đổi hạn mức VNĐ sang USD làm tròn xuống (0 nếu không giới hạn hoặc bằng 0)
          const dailyUsd = newDailyVnd > 0 ? formatUsdLimitForVnd(newDailyVnd) : formatUsdLimitForVnd(curBalance)
          const monthlyUsd = newMonthlyVnd > 0 ? formatUsdLimitForVnd(newMonthlyVnd) : formatUsdLimitForVnd(curBalance)

          const updateRes: any = await callUCloudApi({
            Action: 'UpdateUMInferAPIKey',
            KeyId: targetKeyId,
            DailyLimitAmount: dailyUsd,
            MonthlyLimitAmount: monthlyUsd,
          })

          if (updateRes && updateRes.RetCode === 0) {
            astraflowSynced = true
          }
        }
      } catch (err: any) {
        console.error('Lỗi khi đồng bộ hạn mức sang AstraFlow:', err.message)
      }
    }

    return NextResponse.json({
      success: true,
      balance: Number(updated.balance) || 0,
      dailyLimit: updated.dailyLimit ?? 0,
      monthlyLimit: updated.monthlyLimit ?? 0,
      astraflowSynced,
      message: astraflowSynced
        ? 'Đã lưu hạn mức và đồng bộ sang AstraFlow thành công.'
        : 'Đã lưu hạn mức thành công.',
    })
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
