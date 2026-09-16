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

interface WebhookTransaction {
  id: number | string
  gateway?: string
  transactionDate?: string
  transactionNumber?: string
  accountNumber?: string
  content?: string
  transferType?: string
  transferAmount?: number | string
  checksum?: string
  [key: string]: any
}

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const payload = await getPayload({ config: configPromise })

    // Chuẩn hóa danh sách giao dịch từ body:
    // Hỗ trợ cả 2 định dạng:
    // 1. { "transactions": [ { ... } ] }
    // 2. { id, gateway, content, transferAmount, ... } (giao dịch đơn)
    let transactionsList: WebhookTransaction[] = []

    if (body && Array.isArray(body.transactions)) {
      transactionsList = body.transactions
    } else if (body && (body.id || body.transferAmount)) {
      transactionsList = [body]
    }

    if (!transactionsList || transactionsList.length === 0) {
      return NextResponse.json(
        { success: false, message: 'Không tìm thấy dữ liệu giao dịch trong payload.' },
        { status: 400 }
      )
    }

    // Lấy trước toàn bộ users trong hệ thống để đối soát nhanh
    const allUsers = await payload.find({
      collection: 'users',
      limit: 500,
    })

    const results: any[] = []

    for (const tx of transactionsList) {
      const {
        id: txId,
        gateway = 'ACB',
        transactionDate,
        transactionNumber,
        accountNumber,
        content = '',
        transferType = 'IN',
        transferAmount,
      } = tx

      // Bỏ qua giao dịch tiền ra (chỉ xử lý tiền vào IN / in)
      if (transferType && transferType.toUpperCase() !== 'IN') {
        results.push({
          id: txId,
          status: 'skipped',
          reason: 'transferType != IN',
        })
        continue
      }

      const amount = Number(transferAmount)
      if (!amount || amount <= 0) {
        results.push({
          id: txId,
          status: 'skipped',
          reason: 'Số tiền giao dịch không hợp lệ.',
        })
        continue
      }

      // Kiểm tra trùng lặp giao dịch (Idempotency)
      const transactionId = `BANK-${gateway}-${txId || transactionNumber || Date.now()}`
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
        results.push({
          id: txId,
          status: 'already_processed',
          transactionId,
        })
        continue
      }

      // Trích xuất mã khách hàng MITO... từ chuỗi content
      // Ví dụ: "MITO000123 GD 6246MSCBD2DKLKJI 030926-13:27:11" hoặc "MITO12"
      const contentUpper = (content || '').toUpperCase()
      let matchedUserDoc: any = null

      for (const u of allUsers.docs) {
        const uCode = (u.customerCode || '').toUpperCase()
        const uIdCode = `MITO${u.id}`.toUpperCase()
        const uIdPadded = `MITO${String(u.id).padStart(6, '0')}`.toUpperCase()

        if (
          (uCode && contentUpper.includes(uCode)) ||
          contentUpper.includes(uIdCode) ||
          contentUpper.includes(uIdPadded)
        ) {
          matchedUserDoc = u
          break
        }
      }

      // Nếu không khớp qua vòng lặp, thử quét regex bắt chuỗi MITO[0-9A-Z]{1,10}
      if (!matchedUserDoc) {
        const matchMito = contentUpper.match(/MITO([0-9A-Z]+)/)
        if (matchMito) {
          const rawSuffix = matchMito[1]
          // Thử tìm theo ID số nguyên (bỏ các số 0 ở đầu nếu có)
          const parsedId = parseInt(rawSuffix, 10)
          if (!isNaN(parsedId)) {
            matchedUserDoc = allUsers.docs.find((u) => u.id === parsedId)
          }
          if (!matchedUserDoc) {
            matchedUserDoc = allUsers.docs.find(
              (u) => (u.customerCode || '').toUpperCase() === matchMito[0]
            )
          }
        }
      }

      // Tính toán khuyến mãi và thuế VAT (10%)
      const bonus = calculateBonus(amount)
      const totalCredit = amount + bonus
      const vatRate = 10
      const vatAmount = Math.round(amount - amount / (1 + vatRate / 100))

      let updatedBalance: number | null = null

      // Cộng tiền vào tài khoản người dùng nếu nhận diện được
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

      // Tìm đơn hàng liên kết nếu nội dung chuyển khoản chứa mã đơn hàng MT-...
      let matchedOrderDoc: any = null
      const matchOrderCode = contentUpper.match(/MT-[0-9A-Z]+/i)
      if (matchOrderCode) {
        const orderCodeToFind = matchOrderCode[0].toUpperCase()
        const orderQuery = await payload.find({
          collection: 'orders',
          where: {
            orderCode: {
              equals: orderCodeToFind,
            },
          },
          limit: 1,
        })
        if (orderQuery.docs.length > 0) {
          matchedOrderDoc = orderQuery.docs[0]
        }
      }

      // Nếu tìm thấy đơn hàng tương ứng, cập nhật đơn hàng sang đã thanh toán 'paid'
      // Khi Order chuyển sang paid, hook afterChange trong Orders.ts sẽ tự động:
      // 1. Tạo API Key trên AstraFlow
      // 2. Tạo mã hóa đơn điện tử
      // 3. Cập nhật giao hàng và gửi email cho khách
      if (matchedOrderDoc && matchedOrderDoc.paymentStatus !== 'paid') {
        try {
          await payload.update({
            collection: 'orders',
            id: matchedOrderDoc.id,
            data: {
              paymentStatus: 'paid',
            },
          })
          console.log(`[Payment Webhook] Đã kích hoạt thanh toán thành công cho đơn hàng: ${matchedOrderDoc.orderCode}`)
        } catch (orderUpdateErr: any) {
          console.error(`[Payment Webhook Error] Cập nhật đơn hàng ${matchedOrderDoc.orderCode} thất bại:`, orderUpdateErr.message)
        }
      }

      // Lưu bản ghi Giao dịch vào collection Transactions
      const newTransaction = await payload.create({
        collection: 'transactions',
        data: {
          transactionId,
          order: matchedOrderDoc ? matchedOrderDoc.id : undefined,
          user: matchedUserDoc ? matchedUserDoc.id : undefined,
          amount,
          vatRate,
          vatAmount,
          paymentMethod: 'vietqr',
          status: 'success',
          rawResponse: tx,
        },
      })

      results.push({
        transactionId: newTransaction.transactionId,
        gateway,
        amount,
        bonus,
        totalCredit,
        vatAmount,
        creditedUser: matchedUserDoc ? matchedUserDoc.email : null,
        userCustomerCode: matchedUserDoc ? matchedUserDoc.customerCode : null,
        newBalance: updatedBalance,
        matchedOrder: matchedOrderDoc ? matchedOrderDoc.orderCode : null,
        transactionDate,
        status: 'success',
      })
    }

    return NextResponse.json({
      success: true,
      message: 'Xử lý webhook giao dịch ngân hàng thành công.',
      processedCount: results.length,
      results,
    })
  } catch (error: any) {
    console.error('[Payment Webhook Error]:', error)
    return NextResponse.json(
      {
        success: false,
        message: error?.message || 'Có lỗi xảy ra trong quá trình xử lý Webhook.',
      },
      { status: 500 }
    )
  }
}
