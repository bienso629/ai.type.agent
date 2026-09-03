import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const {
      productId,
      planName,
      totalAmount,
      customerEmail,
      customerPhone,
      customerType,
      customerName,
      identityNumber,
      invoiceEmail,
      companyName,
      companyTaxCode,
      companyAddress,
      note,
    } = body

    if (!productId || !planName || !totalAmount || !customerEmail) {
      return NextResponse.json(
        { success: false, error: 'Vui lòng cung cấp đầy đủ thông tin đặt hàng bắt buộc.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    // Tính toán VAT 10% (Giá gói là tiền dịch vụ chưa VAT)
    const subtotal = Number(totalAmount)
    const vatRate = 10
    const vatAmount = Math.round(subtotal * (vatRate / 100))
    const total = subtotal + vatAmount

    // Sinh mã đơn hàng ngẫu nhiên định dạng MT-XXXXXX
    const randomCode = Math.random().toString(36).substring(2, 8).toUpperCase()
    const orderCode = `MT-${Date.now().toString().slice(-4)}${randomCode}`

    const newOrder = await payload.create({
      collection: 'orders',
      data: {
        orderCode,
        customerEmail,
        customerPhone: customerPhone || '',
        product: productId,
        planName,
        subtotal,
        vatRate,
        vatAmount,
        totalAmount: total,
        paymentStatus: 'pending',
        fulfillmentStatus: 'unfulfilled',
        customerType: customerType === 'company' ? 'company' : 'personal',
        customerName: customerName || '',
        identityNumber: identityNumber || '',
        invoiceEmail: invoiceEmail || customerEmail,
        companyName: companyName || '',
        companyTaxCode: companyTaxCode || '',
        companyAddress: companyAddress || '',
        note: note || '',
      },
    })

    // Tạo bản ghi giao dịch tương ứng nếu cần
    try {
      await payload.create({
        collection: 'transactions',
        data: {
          transactionId: `TX-${orderCode}`,
          order: newOrder.id,
          amount: Number(totalAmount),
          status: 'pending',
          paymentMethod: 'vietqr',
        },
      })
    } catch {
      // Bỏ qua nếu có lỗi giao dịch phụ
    }

    return NextResponse.json({
      success: true,
      order: {
        id: newOrder.id,
        orderCode: newOrder.orderCode,
        customerEmail: newOrder.customerEmail,
        totalAmount: newOrder.totalAmount,
        planName: newOrder.planName,
        paymentStatus: newOrder.paymentStatus,
        fulfillmentStatus: newOrder.fulfillmentStatus,
        createdAt: newOrder.createdAt,
      },
    })
  } catch (error: any) {
    console.error('Lỗi khi tạo đơn hàng:', error)
    return NextResponse.json(
      { success: false, error: error?.message || 'Có lỗi xảy ra trong quá trình xử lý đơn hàng.' },
      { status: 500 }
    )
  }
}
