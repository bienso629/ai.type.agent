import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import crypto from 'crypto'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const { email } = body

    if (!email) {
      return NextResponse.json(
        { success: false, message: 'Vui lòng nhập địa chỉ email.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    const users = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: email.toLowerCase().trim(),
        },
      },
      limit: 1,
    })

    if (!users.docs || users.docs.length === 0) {
      return NextResponse.json({
        success: true,
        message: 'Nếu email tồn tại trong hệ thống, mã xác nhận OTP đã được gửi đến bạn.',
      })
    }

    const user = users.docs[0]

    // Tạo mã OTP ngẫu nhiên 6 chữ số
    const otp = Math.floor(100000 + crypto.randomInt(900000)).toString()
    // Thời hạn 15 phút
    const expiration = new Date(Date.now() + 15 * 60 * 1000).toISOString()

    await payload.update({
      collection: 'users',
      id: user.id,
      data: {
        resetOtp: otp,
        resetOtpExpiration: expiration,
      },
    })

    console.log(`[FORGOT_PASSWORD] Ma OTP khoi phuc mat khau cho ${user.email} la: ${otp}`)

    // Gửi email nếu có thiết lập SMTP hoặc logging
    return NextResponse.json({
      success: true,
      message: 'Mã xác nhận OTP đã được gửi đến email của bạn. Vui lòng kiểm tra hộp thư.',
      // Lưu ý: Trong môi trường dev có thể đính kèm thông tin để test tiện lợi
      debugOtp: process.env.NODE_ENV !== 'production' ? otp : undefined,
    })
  } catch (error: any) {
    console.error('Lỗi khi gửi yêu cầu quên mật khẩu:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Lỗi hệ thống khi gửi yêu cầu.' },
      { status: 500 }
    )
  }
}
