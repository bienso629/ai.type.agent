import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const { email, otp, newPassword } = body

    if (!email || !otp || !newPassword) {
      return NextResponse.json(
        { success: false, message: 'Vui lòng điền đầy đủ Email, mã OTP và mật khẩu mới.' },
        { status: 400 }
      )
    }

    if (newPassword.length < 6) {
      return NextResponse.json(
        { success: false, message: 'Mật khẩu mới phải có tối thiểu 6 ký tự.' },
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
      return NextResponse.json(
        { success: false, message: 'Không tìm thấy tài khoản tương ứng.' },
        { status: 404 }
      )
    }

    const user = users.docs[0]

    if (!user.resetOtp || user.resetOtp.trim() !== otp.trim()) {
      return NextResponse.json(
        { success: false, message: 'Mã xác nhận OTP không chính xác.' },
        { status: 400 }
      )
    }

    if (user.resetOtpExpiration) {
      const expDate = new Date(user.resetOtpExpiration)
      if (expDate.getTime() < Date.now()) {
        return NextResponse.json(
          { success: false, message: 'Mã xác nhận OTP đã hết hạn. Vui lòng yêu cầu mã mới.' },
          { status: 400 }
        )
      }
    }

    // Đặt lại mật khẩu và xóa OTP
    await payload.update({
      collection: 'users',
      id: user.id,
      data: {
        password: newPassword,
        authProvider: 'local',
        resetOtp: null,
        resetOtpExpiration: null,
      },
    })

    return NextResponse.json({
      success: true,
      message: 'Đặt lại mật khẩu thành công! Bây giờ bạn có thể đăng nhập bằng mật khẩu mới.',
    })
  } catch (error: any) {
    console.error('Lỗi khi đặt lại mật khẩu:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Lỗi hệ thống khi đặt lại mật khẩu.' },
      { status: 500 }
    )
  }
}
