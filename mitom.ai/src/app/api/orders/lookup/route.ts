import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url)
    const query = searchParams.get('q')?.trim()

    if (!query) {
      return NextResponse.json(
        { success: false, error: 'Vui lòng nhập Mã đơn hàng hoặc Email để tra cứu.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    // Tra cứu theo orderCode hoặc customerEmail
    const orders = await payload.find({
      collection: 'orders',
      where: {
        or: [
          {
            orderCode: {
              equals: query.toUpperCase(),
            },
          },
          {
            customerEmail: {
              equals: query.toLowerCase(),
            },
          },
        ],
      },
      depth: 1,
      limit: 10,
      sort: '-createdAt',
    })

    if (!orders.docs || orders.docs.length === 0) {
      return NextResponse.json({
        success: true,
        orders: [],
        message: 'Không tìm thấy đơn hàng nào khớp với thông tin đã nhập.',
      })
    }

    const sanitizedOrders = orders.docs.map((doc: any) => ({
      id: doc.id,
      orderCode: doc.orderCode,
      productName: typeof doc.product === 'object' && doc.product ? doc.product.name : 'Thẻ cào / Dịch vụ AI',
      planName: doc.planName,
      totalAmount: doc.totalAmount,
      paymentStatus: doc.paymentStatus,
      fulfillmentStatus: doc.fulfillmentStatus,
      deliveryInfo: doc.paymentStatus === 'paid' ? doc.deliveryInfo : null,
      createdAt: doc.createdAt,
    }))

    return NextResponse.json({
      success: true,
      orders: sanitizedOrders,
    })
  } catch (error: any) {
    console.error('Lỗi khi tra cứu đơn hàng:', error)
    return NextResponse.json(
      { success: false, error: error?.message || 'Có lỗi xảy ra khi tra cứu thông tin đơn hàng.' },
      { status: 500 }
    )
  }
}
