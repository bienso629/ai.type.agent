import { NextResponse } from 'next/server'
import { cookies, headers } from 'next/headers'
import { verifySessionToken } from '@/lib/auth'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { chromium } from '@playwright/test'
import { callUCloudApi } from '@/lib/ucloudClient'
import fs from 'fs'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

const COOKIE_FILE = path.resolve(process.cwd(), 'astraflow_cookies.json')
const USER_DATA_DIR = path.resolve(process.cwd(), '.playwright_astraflow_session')
const KEYS_CACHE_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

async function checkIsAdmin(requestHeaders?: Headers): Promise<boolean> {
  try {
    // Cho phép xác thực qua Cron Secret hoặc Header Bearer Token nội bộ
    if (requestHeaders) {
      const cronSecret = requestHeaders.get('x-cron-secret')
      const authHeader = requestHeaders.get('authorization')
      const expectedSecret = process.env.CRON_SECRET || process.env.PAYLOAD_SECRET
      if (expectedSecret) {
        if (cronSecret === expectedSecret) return true
        if (authHeader === `Bearer ${expectedSecret}`) return true
      }
    }

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
export async function GET(request: Request) {
  try {
    const isAdmin = await checkIsAdmin(request.headers)
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

async function saveKeysToPayload(keysList: any[]): Promise<number> {
  if (!keysList || keysList.length === 0) return 0
  const payload = await getPayload({ config: configPromise })

  const validKeyIds = new Set<string>()

  for (const item of keysList) {
    const keyId = item.KeyId || item.ResourceId || `key-${Date.now()}`
    validKeyIds.add(keyId)

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

  // Tự động dọn dẹp các key đã bị xóa trên AstraFlow khỏi database Payload
  try {
    const allDbKeys = await payload.find({
      collection: 'api-keys',
      limit: 500,
    })
    for (const doc of allDbKeys.docs) {
      if (doc.keyId && !validKeyIds.has(doc.keyId)) {
        await payload.delete({
          collection: 'api-keys',
          id: doc.id,
        })
        console.log(`Đã tự động dọn dẹp key bị xóa trên AstraFlow: ${doc.keyId} (${doc.name})`)
      }
    }
  } catch (cleanErr: any) {
    console.error('Lỗi khi dọn dẹp key đã xóa:', cleanErr.message)
  }

  return keysList.length
}

// POST: Kích hoạt đồng bộ danh sách Keys trực tiếp từ AstraFlow bằng phiên Chrome
export async function POST(request: Request) {
  try {
    const isAdmin = await checkIsAdmin(request.headers)
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
              await saveKeysToPayload(data.Data)
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

    // 1. ƯU TIÊN SỐ 1: Gọi trực tiếp qua API chính thống của AstraFlow / UCloud bằng HMAC-SHA1 Signature
    const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY
    const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY

    if (pubKey && privKey) {
      try {
        const ucloudRes = await callUCloudApi({ Action: 'ListUMInferAPIKey' }, { publicKey: pubKey, privateKey: privKey })
        if (ucloudRes?.Data && Array.isArray(ucloudRes.Data) && ucloudRes.Data.length > 0) {
          fs.writeFileSync(KEYS_CACHE_FILE, JSON.stringify(ucloudRes.Data, null, 2), 'utf-8')
          await saveKeysToPayload(ucloudRes.Data)

          return NextResponse.json({
            success: true,
            source: 'official_api',
            message: `Đồng bộ thành công ${ucloudRes.Data.length} API Keys trực tiếp từ AstraFlow API!`,
            keysCount: ucloudRes.Data.length,
            keys: ucloudRes.Data,
          })
        }
      } catch (apiErr: any) {
        console.warn('Lỗi gọi AstraFlow Official API:', apiErr.message)
      }
    }

    // 2. Chế độ fallback: Sử dụng Playwright headless nếu có chrome, hoặc fallback trực tiếp từ cache
    let interceptedKeys: any[] = []
    let context: any = null

    try {
      context = await chromium.launchPersistentContext(USER_DATA_DIR, {
        executablePath: fs.existsSync('/usr/bin/google-chrome') ? '/usr/bin/google-chrome' : undefined,
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
      })
    } catch (e: any) {
      console.warn('Không thể khởi chạy Chromium browser:', e.message)
    }

    try {
      if (context) {
        const page = context.pages().length > 0 ? context.pages()[0] : await context.newPage()

        page.on('response', async (res: any) => {
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
            cookieHeader: cookies.map((c: any) => `${c.name}=${c.value}`).join('; '),
            cookies,
          }
          fs.writeFileSync(COOKIE_FILE, JSON.stringify(cookieResult, null, 2), 'utf-8')
        }

        await context.close()
      }

      // 1. Nếu bắt được keys trực tiếp từ mạng
      if (interceptedKeys.length > 0) {
        fs.writeFileSync(KEYS_CACHE_FILE, JSON.stringify(interceptedKeys, null, 2), 'utf-8')
        await saveKeysToPayload(interceptedKeys)

        return NextResponse.json({
          success: true,
          message: `Đã đồng bộ thành công ${interceptedKeys.length} API Keys từ AstraFlow!`,
          keysCount: interceptedKeys.length,
          keys: interceptedKeys,
        })
      }

      // 2. Fallback: Nếu không chặn được trực tiếp do AstraFlow yêu cầu signature nhưng file cache keys đã có
      if (fs.existsSync(KEYS_CACHE_FILE)) {
        try {
          const cached = JSON.parse(fs.readFileSync(KEYS_CACHE_FILE, 'utf-8'))
          if (Array.isArray(cached) && cached.length > 0) {
            await saveKeysToPayload(cached)
            return NextResponse.json({
              success: true,
              message: `Đã làm mới và đồng bộ ${cached.length} API Keys từ cache AstraFlow vào database!`,
              keysCount: cached.length,
              keys: cached,
            })
          }
        } catch {
          // Ignored
        }
      }

      // Nếu chưa bắt được (ví dụ phiên đăng nhập hết hạn)
      return NextResponse.json({
        success: false,
        keysCount: 0,
        error: 'Chưa trích xuất được keys từ AstraFlow (phiên đăng nhập hết hạn hoặc chưa tải xong).',
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
