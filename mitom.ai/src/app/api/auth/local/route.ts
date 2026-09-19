import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { createSessionToken, generateCustomerCode } from '@/lib/auth'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const { email, password } = body

    if (!email || !password) {
      return NextResponse.json(
        { success: false, message: 'Vui lòng cung cấp email và mật khẩu.' },
        { status: 400 }
      )
    }

    const payload = await getPayload({ config: configPromise })

    let loginResult: any
    try {
      loginResult = await payload.login({
        collection: 'users',
        data: {
          email: email.toLowerCase().trim(),
          password,
        },
      })
    } catch {
      return NextResponse.json(
        { success: false, message: 'Email hoặc mật khẩu không chính xác.' },
        { status: 401 }
      )
    }

    const user = loginResult.user
    if (!user) {
      return NextResponse.json(
        { success: false, message: 'Đăng nhập không thành công.' },
        { status: 401 }
      )
    }

    let customerCode = user.customerCode
    if (!customerCode) {
      customerCode = generateCustomerCode()
      try {
        await payload.update({
          collection: 'users',
          id: user.id,
          data: { customerCode },
        })
      } catch {}
    }

    const sessionToken = await createSessionToken({
      id: user.id,
      email: user.email,
      name: user.name || user.email.split('@')[0],
      avatar: user.avatar || '',
      authProvider: user.authProvider || 'local',
      balance: user.balance ?? 0,
      customerCode,
      apiKey: user.apiKey,
      role: user.role || 'user',
    })

    const response = NextResponse.json({
      success: true,
      message: 'Đăng nhập thành công.',
      user: {
        id: user.id,
        email: user.email,
        name: user.name || user.email.split('@')[0],
        avatar: user.avatar || '',
        authProvider: user.authProvider || 'local',
        balance: user.balance ?? 0,
        customerCode,
        apiKey: user.apiKey,
        role: user.role || 'user',
      },
    })

    response.cookies.set({
      name: 'mitom_session',
      value: sessionToken,
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      path: '/',
      maxAge: 30 * 24 * 60 * 60, // 30 ngày
    })

    return response
  } catch (error: any) {
    console.error('Lỗi khi xử lý đăng nhập nội bộ:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Đã có lỗi xảy ra trong quá trình đăng nhập.' },
      { status: 500 }
    )
  }
}
