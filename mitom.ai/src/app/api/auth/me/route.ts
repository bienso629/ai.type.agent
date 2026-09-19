import { NextResponse } from 'next/server'
import { cookies, headers } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'

export async function GET() {
  try {
    const headerStore = await headers()
    const apiKey = headerStore.get('x-api-key')?.trim() || null

    const payload = await getPayload({ config: configPromise })

    // 1. Trường hợp xác thực qua Header x-api-key (Dành cho App thứ 3 / SDK / Terminal)
    if (apiKey) {
      try {
        const users = await payload.find({
          collection: 'users',
          where: {
            apiKey: {
              equals: apiKey,
            },
          },
          limit: 1,
        })

        if (users.docs && users.docs.length > 0) {
          const userDoc = users.docs[0]
          return NextResponse.json({
            authenticated: true,
            user: {
              id: userDoc.id,
              email: userDoc.email,
              name: userDoc.name || userDoc.email.split('@')[0],
              avatar: userDoc.avatar || '',
              authProvider: userDoc.authProvider || 'local',
              balance: userDoc.balance ?? 0,
              customerCode: userDoc.customerCode || ``,
              apiKey: userDoc.apiKey,
              role: userDoc.role || 'user',
            },
          })
        }

        return NextResponse.json(
          { authenticated: false, message: 'API Key sử dụng AI không hợp lệ.' },
          { status: 401 }
        )
      } catch (e: any) {
        return NextResponse.json(
          { authenticated: false, message: 'Lỗi khi kiểm tra API Key sử dụng AI.' },
          { status: 500 }
        )
      }
    }

    // 2. Trường hợp xác thực qua Cookie phiên đăng nhập trình duyệt
    const cookieStore = await cookies()
    const sessionToken = cookieStore.get('mitom_session')?.value

    if (!sessionToken) {
      return NextResponse.json({ authenticated: false, user: null })
    }

    const session = await verifySessionToken(sessionToken)
    if (!session || !session.email) {
      return NextResponse.json({ authenticated: false, user: null })
    }

    try {
      const users = await payload.find({
        collection: 'users',
        where: {
          email: {
            equals: session.email,
          },
        },
        limit: 1,
      })

      if (users.docs && users.docs.length > 0) {
        const userDoc = users.docs[0]
        return NextResponse.json({
          authenticated: true,
          user: {
            id: userDoc.id,
            email: userDoc.email,
            name: userDoc.name || session.name,
            avatar: userDoc.avatar || session.avatar,
            authProvider: userDoc.authProvider || session.authProvider,
            balance: userDoc.balance ?? session.balance ?? 0,
            customerCode: userDoc.customerCode || ``,
            apiKey: userDoc.apiKey || session.apiKey,
            role: userDoc.role || session.role || 'user',
          },
        })
      }
    } catch {
      // Fallback về session JWT nếu Payload DB bận
    }

    return NextResponse.json({
      authenticated: true,
      user: session,
    })
  } catch (error) {
    return NextResponse.json({ authenticated: false, user: null })
  }
}
