import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { createSessionToken, generateRandomPassword, generateApiKey } from '@/lib/auth'

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

    // 1. Gọi trực tiếp API Tadu Cloud
    let taduRes: Response
    try {
      taduRes = await fetch('https://api3.tadu.cloud/api/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      })
    } catch (networkErr: any) {
      console.error('Lỗi kết nối tới Tadu Cloud API:', networkErr)
      return NextResponse.json(
        { success: false, message: 'Không thể kết nối đến máy chủ xác thực Tadu Cloud.' },
        { status: 502 }
      )
    }

    const taduData = await taduRes.json()

    // Kiểm tra phản hồi từ Tadu Cloud
    if (!taduRes.ok || taduData.isError || !taduData.data) {
      const errorMsg =
        taduData.error?.password ||
        taduData.error?.email ||
        taduData.error?.message ||
        taduData.message ||
        'Sai email hoặc mật khẩu Tadu Cloud.'
      return NextResponse.json(
        { success: false, message: errorMsg },
        { status: 401 }
      )
    }

    const taduUser = taduData.data.user || taduData.data
    const taduToken = taduData.data.token || taduData.data.accessToken || ''
    const userEmail = (taduUser.email || email).toLowerCase().trim()
    const userName = taduUser.name || taduUser.fullname || taduUser.username || userEmail.split('@')[0]
    const taduUserId = String(taduUser.id || taduUser._id || '')

    // 2. Đồng bộ hoặc tạo User trong hệ thống Payload CMS
    const payload = await getPayload({ config: configPromise })

    const existingUsers = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: userEmail,
        },
      },
      limit: 1,
    })

    let localUser: any

    if (existingUsers.docs && existingUsers.docs.length > 0) {
      const currentDoc = existingUsers.docs[0]
      localUser = await payload.update({
        collection: 'users',
        id: currentDoc.id,
        data: {
          name: currentDoc.name || userName,
          authProvider: 'tadu',
          taduUserId: taduUserId || currentDoc.taduUserId,
          apiKey: currentDoc.apiKey || generateApiKey(),
        },
      })
    } else {
      localUser = await payload.create({
        collection: 'users',
        data: {
          email: userEmail,
          password: generateRandomPassword(),
          name: userName,
          authProvider: 'tadu',
          taduUserId: taduUserId,
          balance: 0,
          role: 'user',
          apiKey: generateApiKey(),
        },
      })
    }

    // 3. Khởi tạo Session JWT và thiết lập Cookie
    const sessionToken = await createSessionToken({
      id: localUser.id,
      email: localUser.email,
      name: localUser.name || userName,
      avatar: localUser.avatar || '',
      authProvider: 'tadu',
      balance: localUser.balance ?? 0,
      apiKey: localUser.apiKey,
      role: localUser.role || 'user',
    })

    const response = NextResponse.json({
      success: true,
      message: 'Đăng nhập Tadu Cloud thành công.',
      user: {
        id: localUser.id,
        email: localUser.email,
        name: localUser.name,
        avatar: localUser.avatar,
        authProvider: 'tadu',
        balance: localUser.balance ?? 0,
        apiKey: localUser.apiKey,
        role: localUser.role,
      },
      taduToken,
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
    console.error('Lỗi khi xử lý đăng nhập Tadu:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Đã có lỗi xảy ra trong quá trình xử lý đăng nhập.' },
      { status: 500 }
    )
  }
}
