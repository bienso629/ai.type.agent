import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { verifySessionToken } from '@/lib/auth'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { callUCloudApi } from '@/lib/ucloudClient'
import { getSystemUsdRate } from '@/lib/currency'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export async function GET() {
  try {
    const cookieStore = await cookies()
    const sessionToken = cookieStore.get('mitom_session')?.value

    if (!sessionToken) {
      return NextResponse.json({ success: false, error: 'Chưa đăng nhập.' }, { status: 401 })
    }

    const session = await verifySessionToken(sessionToken)
    if (!session || !session.email) {
      return NextResponse.json({ success: false, error: 'Phiên đăng nhập không hợp lệ.' }, { status: 401 })
    }

    const payload = await getPayload({ config: configPromise })

    // 1. Tìm thông tin người dùng
    const userDocs = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: session.email,
        },
      },
      limit: 1,
    })

    if (userDocs.docs.length === 0) {
      return NextResponse.json({ success: false, error: 'Không tìm thấy người dùng.' }, { status: 404 })
    }

    const user = userDocs.docs[0]
    const userApiKey = user.apiKey || ''
    const usdRate = getSystemUsdRate()

    // 2. Lấy dữ liệu sử dụng từ AstraFlow qua API chính thống
    let usageStats = {
      dailyUsedVnd: 0,
      monthlyUsedVnd: 0,
      dailyUsedUsd: '0.00',
      monthlyUsedUsd: '0.00',
      keyStatus: 'Chưa cấp',
      lastUpdated: null as string | null,
    }

    const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY
    const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY

    if (pubKey && privKey && userApiKey) {
      try {
        const ucloudRes = await callUCloudApi(
          { Action: 'ListUMInferAPIKey' },
          { publicKey: pubKey, privateKey: privKey }
        )

        if (ucloudRes?.Data && Array.isArray(ucloudRes.Data)) {
          // Khớp key qua key string hoặc qua Name
          const matchedAstraKey = ucloudRes.Data.find(
            (k: any) =>
              k.Key === userApiKey ||
              k.Name === user.email ||
              (user.customerCode && k.Name && k.Name.includes(user.customerCode))
          )

          if (matchedAstraKey) {
            const dailyUsd = Number(matchedAstraKey.DailyUsedAmount) || 0
            const monthlyUsd = Number(matchedAstraKey.MonthlyUsedAmount) || 0

            usageStats = {
              dailyUsedVnd: Math.round(dailyUsd * usdRate),
              monthlyUsedVnd: Math.round(monthlyUsd * usdRate),
              dailyUsedUsd: dailyUsd.toFixed(2),
              monthlyUsedUsd: monthlyUsd.toFixed(2),
              keyStatus: matchedAstraKey.Status === 1 ? 'Đang hoạt động' : 'Tạm khóa',
              lastUpdated: matchedAstraKey.UpdateTime
                ? new Date(matchedAstraKey.UpdateTime * 1000).toISOString()
                : null,
            }
          }
        }
      } catch (err: any) {
        console.warn('[Usage API] Không thể lấy usage từ AstraFlow:', err.message)
      }
    }

    // 3. Lấy lịch sử nạp số dư từ Transactions và Orders đã thanh toán
    const transactions = await payload.find({
      collection: 'transactions',
      where: {
        or: [
          { user: { equals: user.id } },
          { status: { equals: 'success' } },
        ],
      },
      limit: 50,
      sort: '-createdAt',
    })

    // Lọc lại các transactions thực sự của user này
    const userTransactions = transactions.docs.filter((tx: any) => {
      if (typeof tx.user === 'object' && tx.user !== null) {
        return tx.user.id === user.id || tx.user.email === user.email
      }
      return tx.user === user.id
    })

    // Lấy thêm orders đã hoàn thành của user
    const orders = await payload.find({
      collection: 'orders',
      where: {
        customerEmail: {
          equals: user.email,
        },
      },
      limit: 50,
      sort: '-createdAt',
    })

    // Chuẩn hóa danh sách lịch sử nạp
    const topupHistory = orders.docs
      .filter((o: any) => o.paymentStatus === 'paid')
      .map((o: any) => ({
        id: o.id,
        code: o.orderCode,
        type: 'order',
        planName: o.planName,
        amount: o.subtotal || o.totalAmount,
        totalPaid: o.totalAmount,
        status: o.fulfillmentStatus === 'fulfilled' ? 'Đã kích hoạt' : 'Đã thanh toán',
        invoiceCode: o.invoiceCode || null,
        createdAt: o.createdAt,
      }))

    // Nếu có transactions độc lập không qua order hoặc bổ sung
    for (const tx of userTransactions) {
      const isAlreadyInOrders = topupHistory.some((item: any) => {
        if (typeof tx.order === 'object' && tx.order !== null) {
          return item.id === tx.order.id
        }
        return item.id === tx.order
      })

      if (!isAlreadyInOrders) {
        topupHistory.push({
          id: tx.id,
          code: tx.transactionId,
          type: 'direct_bank',
          planName: 'Nạp số dư trực tiếp VietQR',
          amount: tx.amount,
          totalPaid: tx.amount,
          status: tx.status === 'success' ? 'Thành công' : 'Đang xử lý',
          invoiceCode: null,
          createdAt: tx.createdAt,
        })
      }
    }

    // Sắp xếp giảm dần theo thời gian
    topupHistory.sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())

    return NextResponse.json({
      success: true,
      currentBalance: user.balance || 0,
      usageStats,
      topupHistory,
    })
  } catch (error: any) {
    console.error('[API Usage Error]:', error)
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
