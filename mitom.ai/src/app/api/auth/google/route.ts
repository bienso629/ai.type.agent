import { NextResponse } from 'next/server'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { createSessionToken, generateRandomPassword, generateApiKey } from '@/lib/auth'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const { credential, accessToken } = body

    let googleUser: {
      sub: string
      email: string
      name?: string
      picture?: string
    } | null = null

    // 1. Xác thực Google Token qua Google UserInfo hoặc TokenInfo API
    if (credential) {
      // Trường hợp Google One-Tap / JWT Credential
      try {
        const verifyRes = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${credential}`)
        if (verifyRes.ok) {
          const data = await verifyRes.json()
          if (data.email) {
            googleUser = {
              sub: data.sub,
              email: data.email,
              name: data.name,
              picture: data.picture,
            }
          }
        }
      } catch (err) {
        console.error('Lỗi verify id_token Google:', err)
      }
    }

    if (!googleUser && accessToken) {
      // Trường hợp Google OAuth2 Access Token
      try {
        const profileRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
          headers: { Authorization: `Bearer ${accessToken}` },
        })
        if (profileRes.ok) {
          const data = await profileRes.json()
          if (data.email) {
            googleUser = {
              sub: data.sub,
              email: data.email,
              name: data.name,
              picture: data.picture,
            }
          }
        }
      } catch (err) {
        console.error('Lỗi fetch Google userinfo:', err)
      }
    }

    if (!googleUser || !googleUser.email) {
      return NextResponse.json(
        { success: false, message: 'Xác thực Google không thành công hoặc token không hợp lệ.' },
        { status: 401 }
      )
    }

    const userEmail = googleUser.email.toLowerCase().trim()
    const userName = googleUser.name || userEmail.split('@')[0]
    const userAvatar = googleUser.picture || ''
    const googleId = googleUser.sub

    // 2. Tìm hoặc tạo người dùng trong Payload CMS
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
          avatar: userAvatar || currentDoc.avatar,
          authProvider: 'google',
          googleId: googleId || currentDoc.googleId,
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
          avatar: userAvatar,
          authProvider: 'google',
          googleId,
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
      avatar: localUser.avatar || userAvatar,
      authProvider: 'google',
      balance: localUser.balance ?? 0,
      apiKey: localUser.apiKey,
      role: localUser.role || 'user',
    })

    const response = NextResponse.json({
      success: true,
      message: 'Đăng nhập Google thành công.',
      user: {
        id: localUser.id,
        email: localUser.email,
        name: localUser.name,
        avatar: localUser.avatar,
        authProvider: 'google',
        balance: localUser.balance ?? 0,
        apiKey: localUser.apiKey,
        role: localUser.role,
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
    console.error('Lỗi khi xử lý đăng nhập Google:', error)
    return NextResponse.json(
      { success: false, message: error?.message || 'Đã có lỗi xảy ra khi xác thực Google.' },
      { status: 500 }
    )
  }
}
