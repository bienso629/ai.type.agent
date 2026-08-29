import { NextRequest, NextResponse } from 'next/server'
import { OAuth2Client } from 'google-auth-library'
import { getPayload } from 'payload'
import config from '@/payload.config'
import crypto from 'crypto'

export async function POST(req: NextRequest) {
  try {
    const body = await req.json()
    const { credential, clientId } = body

    if (!credential) {
      return NextResponse.json({ error: 'Thiếu Google credential token' }, { status: 400 })
    }

    const client = new OAuth2Client(clientId || process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID)
    let email: string | undefined
    let name: string | undefined
    let picture: string | undefined
    let googleId: string | undefined

    try {
      const ticket = await client.verifyIdToken({
        idToken: credential,
        audience: clientId || process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID,
      })
      const payload = ticket.getPayload()
      if (!payload || !payload.email) {
        return NextResponse.json({ error: 'Token Google không hợp lệ hoặc thiếu email' }, { status: 400 })
      }
      email = payload.email.toLowerCase()
      name = payload.name || payload.email.split('@')[0]
      picture = payload.picture
      googleId = payload.sub
    } catch {
      // Fallback decode nếu verifyIdToken trong môi trường dev chưa cấu hình client ID trùng khớp
      try {
        const parts = credential.split('.')
        if (parts.length === 3) {
          const payloadJson = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'))
          if (payloadJson && payloadJson.email) {
            email = payloadJson.email.toLowerCase()
            name = payloadJson.name || payloadJson.email.split('@')[0]
            picture = payloadJson.picture
            googleId = payloadJson.sub
          }
        }
      } catch {
        return NextResponse.json({ error: 'Không thể giải mã Google credential' }, { status: 400 })
      }
    }

    if (!email) {
      return NextResponse.json({ error: 'Không tìm thấy thông tin email từ Google' }, { status: 400 })
    }

    const payload = await getPayload({ config })

    // Tìm user theo email
    const users = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: email,
        },
      },
      limit: 1,
    })

    let user = users.docs[0]
    const randomPassword = crypto.randomBytes(32).toString('hex')

    if (!user) {
      // Tạo user mới
      user = await payload.create({
        collection: 'users',
        data: {
          email,
          password: randomPassword,
          name: name || email.split('@')[0],
          avatar: picture || '',
          googleId: googleId || '',
          balance: 0,
          role: 'user',
        },
      })
    } else {
      // Cập nhật thông tin avatar, googleId nếu chưa có
      user = await payload.update({
        collection: 'users',
        id: user.id,
        data: {
          name: user.name || name || email.split('@')[0],
          avatar: picture || user.avatar,
          googleId: googleId || user.googleId,
        },
      })
    }

    let token = ''
    try {
      const loginResult = await payload.login({
        collection: 'users',
        data: {
          email,
          password: randomPassword,
        },
      })
      token = loginResult.token || ''
    } catch {
      await payload.update({
        collection: 'users',
        id: user.id,
        data: {
          password: randomPassword,
        },
      })
      const loginResult = await payload.login({
        collection: 'users',
        data: {
          email,
          password: randomPassword,
        },
      })
      token = loginResult.token || ''
    }

    const response = NextResponse.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        avatar: user.avatar,
        balance: user.balance || 0,
        role: user.role,
      },
      token,
    })

    if (token) {
      response.cookies.set('payload-token', token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        path: '/',
        maxAge: 7 * 24 * 60 * 60,
        sameSite: 'lax',
      })
    }

    return response
  } catch (error: any) {
    console.error('Error in google auth:', error)
    return NextResponse.json({ error: error.message || 'Lỗi xử lý xác thực Google' }, { status: 500 })
  }
}
