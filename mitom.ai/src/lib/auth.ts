import { SignJWT, jwtVerify } from 'jose'
import crypto from 'crypto'

const JWT_SECRET = new TextEncoder().encode(
  process.env.PAYLOAD_SECRET || 'mitom-secret-key-super-secure-payload-token-2026'
)

export interface SessionUser {
  id: string | number
  email: string
  name?: string
  avatar?: string
  authProvider: 'local' | 'google' | 'tadu'
  balance?: number
  apiKey?: string
  role?: string
}

export async function createSessionToken(user: SessionUser): Promise<string> {
  return new SignJWT({
    id: user.id,
    email: user.email,
    name: user.name || '',
    avatar: user.avatar || '',
    authProvider: user.authProvider,
    balance: user.balance || 0,
    apiKey: user.apiKey || '',
    role: user.role || 'user',
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(JWT_SECRET)
}

export async function verifySessionToken(token: string): Promise<SessionUser | null> {
  try {
    const { payload } = await jwtVerify(token, JWT_SECRET)
    return payload as unknown as SessionUser
  } catch {
    return null
  }
}

export function generateRandomPassword(): string {
  return crypto.randomBytes(24).toString('hex')
}

export function generateApiKey(): string {
  return `mt_${crypto.randomBytes(24).toString('hex')}`
}
