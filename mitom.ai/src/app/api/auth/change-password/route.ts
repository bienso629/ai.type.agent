import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'

export async function POST(request: Request) {
  try {
    const cookieStore = await cookies()
    const sessionToken = cookieStore.get('mitom_session')?.value

    if (!sessionToken) {
      return NextResponse.json(
        { success: false, message: 'Bạn chưa đăng nhập hoặc phiên làm việc đã hết hạn.' },
        { status: 401 }
      )
    }

    const session = await verifySessionToken(sessionToken)
    if (!session || !session.email) {
      return NextResponse.json(
        { success: false, message: 'Phiên đăng nhập không hợp lệ.' },
        { status: 401 }
      )
    }

    const body = await request.json()
    const { currentPassword, newPassword } = body

    if (!newPassword || newPassword.length < 6) {
      return NextResponse.json(
        { success: false, message: 'Mật khẩu mới phải có ít nhất 6 ký tự.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    const users = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: session.email,
        },
      },
      limit: 1,
    })

    if (!users.docs || users.docs.length === 0) {
      return NextResponse.json(
        { success: false, message: 'Không tìm thấy thông tin tài khoản.' },
        { status: 404 }
      )
    }

    const user = users.docs[0]

    // Chỉ kiểm tra mật khẩu hiện tại khi tài khoản thuần local (không phải liên kết Google)
    const isGoogleUser = user.authProvider === 'google' || Boolean(user.googleId)
    if (!isGoogleUser && user.authProvider === 'local') {
      if (!currentPassword) {
        return NextResponse.json(
          { success: false, message: 'Vui lòng nhập mật khẩu hiện tại.' },
          { status: 400 }
        )
      }

      try {
        await payload.login({
          collection: 'users',
          data: {
            email: user.email,
            password: currentPassword,
          },
        })
      } catch {
        return NextResponse.json(
          { success: false, message: 'Mật khẩu hiện tại không chính xác.' },
          { status: 400 }
        )
      }
    }

    // Cập nhật mật khẩu mới
    await payload.update({
      collection: 'users',
      id: user.id,
      data: {
        password: newPassword,
        authProvider: 'local',
      },
    })

    return NextResponse.json({
      success: true,
      message: 'Thay đổi mật khẩu thành công.',
    })
  } catch (error: any) {
    console.error('Lỗi khi đổi mật khẩu:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Lỗi máy chủ khi đổi mật khẩu.' },
      { status: 500 }
    )
  }
}
