import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'

export async function GET() {
  try {
    const cookieStore = await cookies()
    const sessionToken = cookieStore.get('mitom_session')?.value

    if (!sessionToken) {
      return NextResponse.json({ authenticated: false, user: null })
    }

    const session = await verifySessionToken(sessionToken)
    if (!session || !session.email) {
      return NextResponse.json({ authenticated: false, user: null })
    }

    // Lấy dữ liệu mới nhất từ database
    try {
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
            customerCode: userDoc.customerCode || `MT${String(userDoc.id).padStart(6, '0')}`,
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
