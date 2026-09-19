import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { sendMail, buildOrderPaidEmail } from '@/lib/mailer'
import { fulfillOrder } from '@/lib/orderFulfillment'
import { getOrCreateAstraFlowKey } from '@/lib/orderFulfillment'

interface WebhookTransaction {
  id: number | string
  gateway?: string
  transactionDate?: string
  transactionNumber?: string
  accountNumber?: string
  content?: string
  transferType?: string
  transferAmount?: number | string
  [key: string]: any
}

function generateInvoiceNumber(orderCode: string): string {
  return `INV-${orderCode}`
}

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const payload = await getPayload({ config: configPromise })

    // Load trước 1 product mặc định cho đơn nạp tiền qua webhook (orders.product là bắt buộc)
    let defaultDepositProduct: any = null
    try {
      const prodRes = await payload.find({ collection: 'products', limit: 1 })
      defaultDepositProduct = prodRes.docs && prodRes.docs.length > 0 ? prodRes.docs[0] : null
    } catch { defaultDepositProduct = null }

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
        content = '',
        transferType = 'IN',
        transferAmount,
      } = tx

      if (transferType && transferType.toUpperCase() !== 'IN') {
        results.push({ id: txId, status: 'skipped', reason: 'transferType != IN' })
        continue
      }

      const amount = Number(transferAmount)
      if (!amount || amount <= 0) {
        results.push({ id: txId, status: 'skipped', reason: 'Số tiền giao dịch không hợp lệ.' })
        continue
      }

      const transactionId = `BANK-${gateway}-${txId || transactionNumber || Date.now()}`

      // Idempotency: bỏ qua nếu giao dịch đã xử lý
      const existingTx = await payload.find({
        collection: 'transactions',
        where: { transactionId: { equals: transactionId } },
        limit: 1,
      })
      if (existingTx.docs && existingTx.docs.length > 0) {
        results.push({ id: txId, status: 'already_processed', transactionId })
        continue
      }

      // Nhận diện user qua mã MITO... trong nội dung chuyển khoản
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
      if (!matchedUserDoc) {
        const matchMito = contentUpper.match(/MITO([0-9A-Z]+)/)
        if (matchMito) {
          const parsedId = parseInt(matchMito[1], 10)
          if (!isNaN(parsedId)) {
            matchedUserDoc = allUsers.docs.find((u: any) => u.id === parsedId)
          }
          if (!matchedUserDoc) {
            matchedUserDoc = allUsers.docs.find(
              (u: any) => (u.customerCode || '').toUpperCase() === matchMito[0]
            )
          }
        }
      }

      // ===== NHÁNH 1: THANH TOÁN ĐƠN HÀNG (content chứa mã đơn MT-...) =====
      const matchOrder = contentUpper.match(/MT-[0-9A-Z]{6,20}/)
      let matchedOrder: any = null
      if (matchOrder) {
        const orderRes = await payload.find({
          collection: 'orders',
          where: { orderCode: { equals: matchOrder[0] } },
          limit: 1,
        })
        if (orderRes.docs && orderRes.docs.length > 0) {
          matchedOrder = orderRes.docs[0]
        }
      }

      if (matchedOrder) {
        const order = matchedOrder

        // Đơn đã paid trước đó: chỉ ghi nhận giao dịch, không lập hóa đơn trùng
        if (order.paymentStatus === 'paid') {
          await payload.create({
            collection: 'transactions',
            data: {
              transactionId,
              order: order.id,
              user: matchedUserDoc ? matchedUserDoc.id : undefined,
              amount,
              vatRate: Number(order.vatRate) || 10,
              paymentMethod: 'vietqr',
              status: 'success',
              rawResponse: tx,
            },
          })
          results.push({
            transactionId,
            orderCode: order.orderCode,
            status: 'order_already_paid',
            message: 'Đơn hàng đã thanh toán trước đó, chỉ ghi nhận giao dịch.',
          })
          continue
        }

        const expected = Number(order.totalAmount)
        const amountOk = amount === expected

        // Cập nhật trạng thái đơn hàng
        await payload.update({
          collection: 'orders',
          id: order.id,
          data: {
            paymentStatus: amountOk ? 'paid' : order.paymentStatus,
            note: `${order.note ? order.note + ' | ' : ''}Thanh toán ${amount.toLocaleString('vi-VN')}đ qua ${gateway} lúc ${transactionDate || new Date().toISOString()}${amountOk ? '' : ` (LƯU Ý: đơn yêu cầu ${expected.toLocaleString('vi-VN')}đ)`}`,
          },
        })

        // Ghi nhận giao dịch gắn với đơn
        await payload.create({
          collection: 'transactions',
          data: {
            transactionId,
            order: order.id,
            user: matchedUserDoc ? matchedUserDoc.id : undefined,
            amount,
            vatRate: Number(order.vatRate) || 10,
            vatAmount: Number(order.vatAmount) || 0,
            paymentMethod: 'vietqr',
            status: 'success',
            rawResponse: tx,
          },
        })

        // ===== TẠO HÓA ĐƠN (1 thanh toán = 1 hóa đơn) =====
        const invoiceNumber = generateInvoiceNumber(order.orderCode)
        let invoiceCreated = true
        try {
          await payload.create({
            collection: 'invoices',
            data: {
              invoiceNumber,
              order: order.id,
              customerType: order.customerType || 'personal',
              customerName: order.customerName || '',
              identityNumber: order.identityNumber || '',
              companyName: order.companyName || '',
              companyTaxCode: order.companyTaxCode || '',
              companyAddress: order.companyAddress || '',
              invoiceEmail: order.invoiceEmail || order.customerEmail,
              subtotal: Number(order.subtotal) || 0,
              vatRate: Number(order.vatRate) || 10,
              vatAmount: Number(order.vatAmount) || 0,
              totalAmount: Number(order.totalAmount) || amount,
              status: 'issued',
              emailSent: false,
            },
          })
        } catch (e: any) {
          if (!String(e?.message || '').includes('unique')) {
            invoiceCreated = false
          }
        }

        // ===== FULFILLMENT: cấp key AstraFlow / cộng dư số dư + email brand mitom.ai =====
        let fulfillment: any = null
        let fulfillmentError: string | null = null
        try {
          fulfillment = await fulfillOrder(payload, order, {
            transactionId,
            gateway,
            invoiceNumber,
          })
          if (fulfillment.emailSent) {
            const invRes = await payload.find({
              collection: 'invoices',
              where: { invoiceNumber: { equals: invoiceNumber } },
              limit: 1,
            })
            if (invRes.docs && invRes.docs.length > 0) {
              await payload.update({
                collection: 'invoices',
                id: invRes.docs[0].id,
                data: { emailSent: true },
              })
            }
            await payload.update({
              collection: 'orders',
              id: order.id,
              data: { fulfillmentStatus: 'fulfilled' },
            })
          }
        } catch (e: any) {
          fulfillmentError = e?.message || String(e)
          console.error('[Fulfillment Error]:', fulfillmentError)
        }

        results.push({
          transactionId,
          orderCode: order.orderCode,
          invoiceNumber: invoiceCreated ? invoiceNumber : null,
          amount,
          expectedAmount: expected,
          amountMatched: amountOk,
          fulfillmentMode: fulfillment ? fulfillment.mode : null,
          apiKeyMasked: fulfillment && fulfillment.apiKey
            ? fulfillment.apiKey.slice(0, 10) + '...' + fulfillment.apiKey.slice(-4)
            : null,
          newBalance: fulfillment ? fulfillment.newBalance : null,
          emailedTo: fulfillment && fulfillment.emailSent ? order.invoiceEmail || order.customerEmail : null,
          emailStatus: fulfillment ? (fulfillment.emailSent ? 'sent' : 'failed') : 'skipped',
          emailError: fulfillment ? fulfillment.emailError || fulfillmentError : fulfillmentError,
          status: fulfillment && fulfillment.ok ? 'order_payment_success' : 'order_payment_fulfillment_failed',
        })
        continue
      }

      // ===== KIỂM TRA ĐIỀU KIỆN CHẤP NHẬN GIAO DỊCH =====
      // Chỉ chấp nhận:
      // 1. Giao dịch thanh toán đơn hàng (chứa mã MT-...) -> đã xử lý ở trên
      // 2. Giao dịch nạp tiền tài khoản (chứa mã MITO...) -> matchedUserDoc phải tồn tại
      if (!matchedUserDoc) {
        results.push({
          id: txId,
          status: "skipped",
          reason: "Giao dịch không hợp lệ: nội dung không chứa mã đơn hàng MT-... hoặc mã tài khoản MITO...",
          content,
        });
        continue;
      }

      // ===== NHÁNH 2: NẠP TIỀN VÀO TÀI KHOẢN (có mã MITO...) =====
      const bonus = 0
      const vatRate = 10
      // amount từ callback là TỔNG khách đã chuyển (gói nạp + VAT), theo đúng hiển thị web
      const vatAmount = Math.round(amount * vatRate / (100 + vatRate))
      const netAmount = amount - vatAmount
      const totalCredit = netAmount

      // Tạo Order + Invoice tương ứng 1 giao dịch nạp tiền
      const orderCode = `MT-${Date.now().toString().slice(-4)}${Math.random().toString(36).substring(2, 8).toUpperCase()}`
      const userDoc = matchedUserDoc
      const invoiceEmail = userDoc.email
      const customerName = userDoc.name || userDoc.email.split('@')[0]

      let depositOrder: any = null
      try {
        depositOrder = await payload.create({
          collection: 'orders',
          data: {
            orderCode,
            customerEmail: invoiceEmail,
            product: defaultDepositProduct?.id,
            planName: 'Nạp tiền tài khoản (webhook)',
            subtotal: netAmount,
            vatRate,
            vatAmount,
            totalAmount: amount,
            paymentStatus: 'paid',
            fulfillmentStatus: 'unfulfilled',
            customerType: 'personal',
            customerName,
            invoiceEmail,
            note: `Nạp tiền tự động qua webhook ${gateway} - GD ${transactionId} - Mã KH ${userDoc.customerCode}`,
          },
        })
      } catch (e: any) {
        console.error('[Webhook Deposit] Tạo order lỗi:', e?.message)
      }

      // Cộng dồn số dư NGAY (tiền nạp thuộc về user, không phụ thuộc việc cấp key)
      const currentBalance = Number(userDoc.balance) || 0
      const newBalance = currentBalance + totalCredit
      await payload.update({
        collection: 'users',
        id: userDoc.id,
        data: { balance: newBalance },
      })

      // Cấp/tái sử dụng API Key AstraFlow + gửi email xác nhận
      let fulfillment: any = null
      let fulfillmentError: string | null = null
      try {
        const freshUser = await payload.findByID({ collection: 'users', id: userDoc.id })
        fulfillment = await getOrCreateAstraFlowKey(payload, freshUser || userDoc, netAmount, {
          transactionId,
          gateway,
          invoiceNumber: `INV-${orderCode}`,
          newBalance,
        })
        if (fulfillment.ok && depositOrder) {
          await payload.update({
            collection: 'orders',
            id: depositOrder.id,
            data: {
              fulfillmentStatus: 'fulfilled',
              deliveryInfo: fulfillment.isNewKey
                ? `API Key moi: ${fulfillment.apiKey}`
                : `Tai su dung API Key hien co: ${fulfillment.apiKey}`,
            },
          })
        }
      } catch (e: any) {
        fulfillmentError = e?.message || String(e)
        console.error('[Webhook Deposit] Fulfillment lỗi:', fulfillmentError)
      }

      // Tạo Invoice cho giao dịch nạp tiền
      let invoiceCreated = false
      try {
        await payload.create({
          collection: 'invoices',
          data: {
            invoiceNumber: `INV-${orderCode}`,
            order: depositOrder?.id,
            customerType: 'personal',
            customerName,
            invoiceEmail,
            subtotal: netAmount,
            vatRate,
            vatAmount,
            totalAmount: amount,
            status: 'issued',
            emailSent: fulfillment ? fulfillment.emailSent : false,
          },
        })
        invoiceCreated = true
      } catch (e: any) {
        if (!String(e?.message || '').includes('unique')) {
          console.error('[Webhook Deposit] Tạo invoice lỗi:', e?.message)
        } else {
          invoiceCreated = true
        }
      }

      await payload.create({
        collection: 'transactions',
        data: {
          transactionId,
          order: depositOrder?.id,
          user: userDoc.id,
          amount,
          vatRate,
          vatAmount,
          paymentMethod: 'vietqr',
          status: 'success',
          rawResponse: tx,
        },
      })

      results.push({
        transactionId,
        gateway,
        amount,
        bonus,
        totalCredit,
        vatAmount,
        orderCode: depositOrder ? depositOrder.orderCode : null,
        invoiceNumber: invoiceCreated ? `INV-${orderCode}` : null,
        creditedUser: userDoc.email,
        userCustomerCode: userDoc.customerCode,
        apiKeyMasked: fulfillment && fulfillment.apiKey
          ? fulfillment.apiKey.slice(0, 10) + '...' + fulfillment.apiKey.slice(-4)
          : null,
        isNewKey: fulfillment ? fulfillment.isNewKey : false,
        newBalance,
        emailedTo: fulfillment && fulfillment.emailSent ? invoiceEmail : null,
        emailStatus: fulfillment ? (fulfillment.emailSent ? 'sent' : 'failed') : 'skipped',
        emailError: fulfillment ? fulfillment.emailError || fulfillmentError : fulfillmentError,
        transactionDate,
        status: fulfillment && fulfillment.ok ? 'deposit_success' : 'deposit_fulfillment_failed',
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
