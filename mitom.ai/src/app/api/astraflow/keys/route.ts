import { NextResponse } from 'next/server'
import { cookies, headers } from 'next/headers'
import { verifySessionToken } from '@/lib/auth'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { chromium } from '@playwright/test'
import fs from 'fs'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

const COOKIE_FILE = path.resolve(process.cwd(), 'astraflow_cookies.json')
const USER_DATA_DIR = path.resolve(process.cwd(), '.playwright_astraflow_session')
const KEYS_CACHE_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

async function checkIsAdmin(): Promise<boolean> {
  try {
    const cookieStore = await cookies()
    const sessionToken = cookieStore.get('mitom_session')?.value

    if (sessionToken) {
      const sessionUser = await verifySessionToken(sessionToken)
      if (sessionUser && sessionUser.role === 'admin') {
        return true
      }
    }

    // Kiểm tra đăng nhập từ giao diện Payload Admin (/101)
    const payload = await getPayload({ config: configPromise })
    const headerStore = await headers()
    const { user } = await payload.auth({ headers: headerStore })
    if (user && (user as any).role === 'admin') {
      return true
    }

    return false
  } catch {
    return false
  }
}

// GET: Lấy danh sách Keys (ưu tiên Payload Database -> Cache File -> Playwright sync nếu có session)
export async function GET() {
  try {
    const isAdmin = await checkIsAdmin()
    if (!isAdmin) {
      return NextResponse.json(
        { success: false, error: 'Chỉ quản trị viên (Admin) mới có quyền truy cập.' },
        { status: 403 },
      )
    }

    const payload = await getPayload({ config: configPromise })

    // 1. Lấy danh sách keys đã đồng bộ và lưu trong cơ sở dữ liệu Payload CMS
    const dbKeys = await payload.find({
      collection: 'api-keys',
      limit: 100,
      sort: '-updatedAt',
    })

    // 2. Lấy dữ liệu file cache nếu có
    let cachedKeys: any[] = []
    if (fs.existsSync(KEYS_CACHE_FILE)) {
      try {
        cachedKeys = JSON.parse(fs.readFileSync(KEYS_CACHE_FILE, 'utf-8'))
      } catch {
        // Ignored
      }
    }

    const hasCookies = fs.existsSync(COOKIE_FILE)

    return NextResponse.json(
      {
        success: true,
        hasCookies,
        keys: dbKeys.docs.length > 0 ? dbKeys.docs : cachedKeys,
        count: dbKeys.docs.length > 0 ? dbKeys.totalDocs : cachedKeys.length,
        source: dbKeys.docs.length > 0 ? 'database' : (cachedKeys.length > 0 ? 'cache' : 'none'),
        updatedAt: new Date().toISOString(),
      },
      {
        headers: {
          'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
          Pragma: 'no-cache',
          Expires: '0',
        },
      },
    )
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}

// POST: Kích hoạt đồng bộ danh sách Keys trực tiếp từ AstraFlow bằng phiên Chrome
export async function POST(request: Request) {
  try {
    const isAdmin = await checkIsAdmin()
    if (!isAdmin) {
      return NextResponse.json(
        { success: false, error: 'Chỉ quản trị viên (Admin) mới có quyền truy cập.' },
        { status: 403 },
      )
    }

    const body = await request.json().catch(() => ({}))
    const { mode = 'fetch' } = body

    // Trường hợp mở trực tiếp trang AstraFlow API Keys trong cửa sổ trình duyệt có giao diện
    if (mode === 'open_browser') {
      const displayEnv = process.env.DISPLAY || ':0'
      const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
        executablePath: '/usr/bin/google-chrome',
        headless: false,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
        env: { ...process.env, DISPLAY: displayEnv },
      })

      const page = context.pages().length > 0 ? context.pages()[0] : await context.newPage()
      await page.goto('https://astraflow.scloudsg.com/en-us/experience-modelverse/api-keys', { timeout: 60000 })

      // Tự động lưu cookie và bắt request ListUMInferAPIKey nếu có
      page.on('response', async (res) => {
        if (res.url().includes('ListUMInferAPIKey')) {
          try {
            const data = await res.json()
            if (data?.Data && Array.isArray(data.Data)) {
              fs.writeFileSync(KEYS_CACHE_FILE, JSON.stringify(data.Data, null, 2), 'utf-8')
              // Lưu vào Payload CMS
              const payload = await getPayload({ config: configPromise })
              for (const item of data.Data) {
                const keyId = item.KeyId || item.ResourceId || `key-${Date.now()}`
                const existing = await payload.find({
                  collection: 'api-keys',
                  where: { keyId: { equals: keyId } },
                })

                const docData = {
                  name: item.KeyName || item.Name || 'AstraFlow API Key',
                  keyId,
                  maskedKey: item.APIKey || item.Key || '',
                  secretKey: item.SecretKey || item.APIKey || '',
                  status: item.Status === 2 ? 'Disabled' : 'Normal',
                  permissions: item.Permissions || 'Sandbox, Modelverse',
                  dailyLimit: String(item.DailyLimitAmount || 'Không giới hạn'),
                  monthlyLimit: String(item.MonthlyLimitAmount || 'Không giới hạn'),
                  dailySpend: String(item.DailyUsedAmount || '0'),
                  monthlySpend: String(item.MonthlyUsedAmount || '0'),
                  modelAccessMode: item.ModelAccessMode || 'All Models',
                  expiryTime: item.ExpireTime ? new Date(item.ExpireTime * 1000).toLocaleString('vi-VN') : 'Vĩnh viễn',
                  rawResponse: item,
                }

                if (existing.docs.length > 0) {
                  await payload.update({
                    collection: 'api-keys',
                    id: existing.docs[0].id,
                    data: docData as any,
                  })
                } else {
                  await payload.create({
                    collection: 'api-keys',
                    data: docData as any,
                  })
                }
              }
            }
          } catch {
            // Ignored
          }
        }
      })

      return NextResponse.json({
        success: true,
        message: 'Đã mở cửa sổ Chrome trực tiếp tới trang Quản lý Keys AstraFlow.',
      })
    }

    // Chế độ 'fetch': Sử dụng Playwright headless để truy cập và trích xuất danh sách key tự động
    let interceptedKeys: any[] = []
    const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
      executablePath: '/usr/bin/google-chrome',
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    })

    try {
      const page = context.pages().length > 0 ? context.pages()[0] : await context.newPage()

      page.on('response', async (res) => {
        if (res.url().includes('ListUMInferAPIKey')) {
          try {
            const data = await res.json()
            if (data?.Data && Array.isArray(data.Data)) {
              interceptedKeys = data.Data
            }
          } catch {
            // Ignored
          }
        }
      })

      // Truy cập trang API Keys
      await page.goto('https://astraflow.scloudsg.com/en-us/experience-modelverse/api-keys', {
        waitUntil: 'domcontentloaded',
        timeout: 45000,
      }).catch(() => {})

      await page.waitForTimeout(6000)

      // Lưu lại cookies mới nhất
      const cookies = await context.cookies()
      if (cookies.length > 0) {
        const cookieResult = {
          targetUrl: 'https://astraflow.scloudsg.com',
          finalUrl: page.url(),
          title: await page.title().catch(() => 'AstraFlow'),
          extractedAt: new Date().toISOString(),
          cookieCount: cookies.length,
          cookieHeader: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
          cookies,
        }
        fs.writeFileSync(COOKIE_FILE, JSON.stringify(cookieResult, null, 2), 'utf-8')
      }

      await context.close()

      // Nếu bắt được keys, đồng bộ vào database
      if (interceptedKeys.length > 0) {
        fs.writeFileSync(KEYS_CACHE_FILE, JSON.stringify(interceptedKeys, null, 2), 'utf-8')
        const payload = await getPayload({ config: configPromise })

        for (const item of interceptedKeys) {
          const keyId = item.KeyId || item.ResourceId || `key-${Date.now()}`
          const existing = await payload.find({
            collection: 'api-keys',
            where: { keyId: { equals: keyId } },
          })

          const docData = {
            name: item.KeyName || item.Name || 'AstraFlow API Key',
            keyId,
            maskedKey: item.APIKey || item.Key || '',
            secretKey: item.SecretKey || item.APIKey || '',
            status: item.Status === 2 ? 'Disabled' : 'Normal',
            permissions: item.Permissions || 'Sandbox, Modelverse',
            dailyLimit: String(item.DailyLimitAmount || 'Không giới hạn'),
            monthlyLimit: String(item.MonthlyLimitAmount || 'Không giới hạn'),
            dailySpend: String(item.DailyUsedAmount || '0'),
            monthlySpend: String(item.MonthlyUsedAmount || '0'),
            modelAccessMode: item.ModelAccessMode || 'All Models',
            expiryTime: item.ExpireTime ? new Date(item.ExpireTime * 1000).toLocaleString('vi-VN') : 'Vĩnh viễn',
            rawResponse: item,
          }

          if (existing.docs.length > 0) {
            await payload.update({
              collection: 'api-keys',
              id: existing.docs[0].id,
              data: docData as any,
            })
          } else {
            await payload.create({
              collection: 'api-keys',
              data: docData as any,
            })
          }
        }

        return NextResponse.json({
          success: true,
          message: `Đã đồng bộ thành công ${interceptedKeys.length} API Keys từ AstraFlow!`,
          keys: interceptedKeys,
        })
      }

      // Nếu chưa bắt được (ví dụ phiên đăng nhập hết hạn)
      return NextResponse.json({
        success: true,
        message: 'Chưa thể trích xuất tự động qua headless (có thể cần đăng nhập lại session). Bạn có thể dùng nút Mở trang Keys để đăng nhập và lấy trực tiếp.',
        keys: [],
      })
    } catch (err: any) {
      await context.close().catch(() => {})
      return NextResponse.json({ success: false, error: err.message }, { status: 500 })
    }
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
