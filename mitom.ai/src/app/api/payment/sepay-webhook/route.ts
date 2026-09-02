import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'

// Bảng khuyến mãi nạp tiền đồng bộ với Frontend
const TOPUP_BONUS_TIERS = [
  { amount: 50000, bonusPct: 0 },
  { amount: 100000, bonusPct: 5 },
  { amount: 200000, bonusPct: 10 },
  { amount: 500000, bonusPct: 15 },
  { amount: 1000000, bonusPct: 20 },
  { amount: 2000000, bonusPct: 25 },
]

function calculateBonus(amount: number): number {
  const sorted = [...TOPUP_BONUS_TIERS].sort((a, b) => b.amount - a.amount)
  const matched = sorted.find((tier) => amount >= tier.amount)
  if (!matched || matched.bonusPct <= 0) return 0
  return Math.round((amount * matched.bonusPct) / 100)
}

export async function POST(request: Request) {
  try {
    // 1. Kiểm tra Authentication Headers từ SePay
    const authHeader = request.headers.get('Authorization') || request.headers.get('authorization')
    const expectedApiKey = process.env.SEPAY_API_KEY || 'yenaideptraihocgioihoangtuong'

    // Hỗ trợ các kiểu header SePay gửi: "Apikey yenaideptraihocgioihoangtuong", "ApiKey ...", "Bearer ..." hoặc "yenaideptraihocgioihoangtuong"
    const isValidAuth =
      authHeader === expectedApiKey ||
      authHeader === `Apikey ${expectedApiKey}` ||
      authHeader === `ApiKey ${expectedApiKey}` ||
      authHeader === `Bearer ${expectedApiKey}`

    if (!isValidAuth) {
      console.warn('[SePay Webhook] Xác thực thất bại với Authorization header:', authHeader)
      return NextResponse.json(
        { success: false, message: 'Unauthorized. API Key không hợp lệ.' },
        { status: 401 }
      )
    }

    // 2. Parse dữ liệu giao dịch từ body
    const body = await request.json()
    const {
      gateway,
      transactionDate,
      accountNumber,
      code,
      content,
      transferType,
      transferAmount,
      referenceCode,
      id: sePayId,
    } = body

    // Bỏ qua nếu không phải giao dịch tiền vào (tiền nhận)
    if (transferType && transferType !== 'in') {
      return NextResponse.json({
        success: true,
        message: 'Bỏ qua giao dịch tiền ra (transferType != in)',
      })
    }

    const amount = Number(transferAmount)
    if (!amount || amount <= 0) {
      return NextResponse.json(
        { success: false, message: 'Số tiền giao dịch không hợp lệ.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    // 3. Kiểm tra tính trùng lặp giao dịch (Idempotency)
    const transactionId = `SEPAY-${sePayId || referenceCode || Date.now()}`
    const existingTx = await payload.find({
      collection: 'transactions',
      where: {
        transactionId: {
          equals: transactionId,
        },
      },
      limit: 1,
    })

    if (existingTx.docs && existingTx.docs.length > 0) {
      return NextResponse.json({
        success: true,
        message: 'Giao dịch này đã được xử lý trước đó.',
        transactionId,
      })
    }

    // 4. Trích xuất mã khách hàng hoặc mã đơn hàng từ content / description / code
    const fullText = `${code || ''} ${content || ''} ${body.description || ''}`.toUpperCase()

    let matchedUserDoc: any = null

    // Tìm theo customerCode hoặc ID trong DB Users
    const allUsers = await payload.find({
      collection: 'users',
      limit: 500,
    })

    for (const u of allUsers.docs) {
      const uCode = (u.customerCode || '').toUpperCase()
      const uIdCode = `MT${u.id}`.toUpperCase()
      const uIdFull = `MT-${u.id}`.toUpperCase()

      if (
        (uCode && fullText.includes(uCode)) ||
        fullText.includes(uIdCode) ||
        fullText.includes(uIdFull) ||
        (code && (code.toUpperCase() === uCode || code.toUpperCase() === uIdCode))
      ) {
        matchedUserDoc = u
        break
      }
    }

    // Nếu không khớp User, thử khớp theo đơn hàng Orders
    let matchedOrder: any = null
    if (!matchedUserDoc) {
      const allOrders = await payload.find({
        collection: 'orders',
        where: {
          paymentStatus: {
            equals: 'pending',
          },
        },
        limit: 100,
      })

      for (const ord of allOrders.docs) {
        const oCode = ord.orderCode.toUpperCase()
        if (fullText.includes(oCode) || (code && code.toUpperCase() === oCode)) {
          matchedOrder = ord
          break
        }
      }

      if (matchedOrder && matchedOrder.customerEmail) {
        const userByEmail = await payload.find({
          collection: 'users',
          where: {
            email: {
              equals: matchedOrder.customerEmail,
            },
          },
          limit: 1,
        })
        if (userByEmail.docs.length > 0) {
          matchedUserDoc = userByEmail.docs[0]
        }
      }
    }

    // Tính toán số dư được cộng (bao gồm cả tiền thưởng khuyến mãi)
    const bonus = calculateBonus(amount)
    const totalCredit = amount + bonus

    // 5. Cộng tiền vào tài khoản User nếu tìm thấy
    let updatedBalance = null
    if (matchedUserDoc) {
      const currentBalance = Number(matchedUserDoc.balance) || 0
      updatedBalance = currentBalance + totalCredit

      await payload.update({
        collection: 'users',
        id: matchedUserDoc.id,
        data: {
          balance: updatedBalance,
        },
      })
    }

    // Cập nhật trạng thái đơn hàng nếu có đơn hàng khớp
    if (matchedOrder) {
      await payload.update({
        collection: 'orders',
        id: matchedOrder.id,
        data: {
          paymentStatus: 'paid',
          fulfillmentStatus: 'fulfilled',
        },
      })
    }

    // 6. Lưu bản ghi Giao dịch vào collection Transactions
    const newTransaction = await payload.create({
      collection: 'transactions',
      data: {
        transactionId,
        order: matchedOrder ? matchedOrder.id : undefined,
        user: matchedUserDoc ? matchedUserDoc.id : undefined,
        amount,
        paymentMethod: 'sepay',
        status: 'success',
        rawResponse: body,
      },
    })

    return NextResponse.json({
      success: true,
      message: 'Giao dịch SePay đã được xử lý và cộng tiền thành công.',
      data: {
        transactionId: newTransaction.transactionId,
        amount,
        bonus,
        totalCredit,
        creditedUser: matchedUserDoc ? matchedUserDoc.email : null,
        newBalance: updatedBalance,
        matchedOrder: matchedOrder ? matchedOrder.orderCode : null,
        transactionDate,
        gateway,
        accountNumber,
      },
    })
  } catch (error: any) {
    console.error('[SePay Webhook Error]:', error)
    return NextResponse.json(
      {
        success: false,
        message: error?.message || 'Lỗi xử lý Webhook SePay.',
      },
      { status: 500 }
    )
  }
}
