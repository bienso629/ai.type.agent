import { NextResponse } from 'next/server'
import { cookies, headers } from 'next/headers'
import { verifySessionToken } from '@/lib/auth'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { chromium } from '@playwright/test'
import fs from 'fs'
import path from 'path'

const COOKIE_FILE = path.resolve(process.cwd(), 'astraflow_cookies.json')
const USER_DATA_DIR = path.resolve(process.cwd(), '.playwright_astraflow_session')

async function checkIsAdmin(requestHeaders?: Headers): Promise<boolean> {
  try {
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

// GET: Lấy trạng thái cookies hiện tại
export async function GET(request: Request) {
  try {
    const isAdmin = await checkIsAdmin(request.headers)
    if (!isAdmin) {
      return NextResponse.json({ success: false, error: 'Chỉ quản trị viên (Admin) mới có quyền truy cập.' }, { status: 403 })
    }

    if (fs.existsSync(COOKIE_FILE)) {
      const data = JSON.parse(fs.readFileSync(COOKIE_FILE, 'utf-8'))
      return NextResponse.json({
        success: true,
        hasCookies: true,
        extractedAt: data.extractedAt,
        cookieCount: data.cookieCount,
        cookieHeader: data.cookieHeader,
      })
    }

    return NextResponse.json({
      success: true,
      hasCookies: false,
      message: 'Chưa có tệp cookies được lưu.',
    })
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}

// POST: Kích hoạt phiên đăng nhập hoặc lấy cookies
export async function POST(request: Request) {
  try {
    const isAdmin = await checkIsAdmin(request.headers)
    if (!isAdmin) {
      return NextResponse.json({ success: false, error: 'Chỉ quản trị viên (Admin) mới có quyền truy cập.' }, { status: 403 })
    }

    const body = await request.json().catch(() => ({}))
    const { mode = 'window', username, password } = body

    // Trường hợp 1: Tự động đăng nhập qua username / password nếu được truyền vào
    if (mode === 'credentials' && username && password) {
      const browser = await chromium.launch({
        executablePath: '/usr/bin/google-chrome',
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
      })

      try {
        const context = await browser.newContext()
        const page = await context.newPage()
        await page.goto('https://passport.scloudsg.com/', { waitUntil: 'networkidle', timeout: 45000 })

        // Điền form đăng nhập
        await page.fill('#username', username)
        await page.fill('input[type="password"]', password)
        await page.keyboard.press('Enter')

        // Đợi chuyển hướng sau đăng nhập
        await page.waitForTimeout(6000)

        // Sau đó truy cập astraflow để lấy trọn vẹn session
        await page.goto('https://astraflow.scloudsg.com/en-us', { waitUntil: 'networkidle', timeout: 30000 })

        const cookies = await context.cookies()
        const result = {
          targetUrl: 'https://astraflow.scloudsg.com',
          finalUrl: page.url(),
          title: await page.title(),
          extractedAt: new Date().toISOString(),
          cookieCount: cookies.length,
          cookieHeader: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
          cookies,
        }

        fs.writeFileSync(COOKIE_FILE, JSON.stringify(result, null, 2), 'utf-8')
        await browser.close()

        return NextResponse.json({
          success: true,
          message: 'Đăng nhập và cập nhật cookies AstraFlow thành công.',
          data: result,
        })
      } catch (err: any) {
        await browser.close()
        return NextResponse.json({ success: false, error: `Lỗi đăng nhập: ${err.message}` }, { status: 500 })
      }
    }

    // Trường hợp 2: Mở trình duyệt Chrome giao diện trực tiếp (Non-headless) để người dùng tự thao tác
    const displayEnv = process.env.DISPLAY || ':0'
    const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
      executablePath: '/usr/bin/google-chrome',
      headless: false,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
      env: { ...process.env, DISPLAY: displayEnv },
    })

    const page = context.pages().length > 0 ? context.pages()[0] : await context.newPage()
    await page.goto('https://passport.scloudsg.com/', { timeout: 60000 })

    const KEYS_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

    // Lắng nghe điều hướng và response để bắt API Keys tự động
    page.on('response', async (res) => {
      if (res.url().includes('ListUMInferAPIKey')) {
        try {
          const resData = await res.json()
          if (resData?.Data && Array.isArray(resData.Data)) {
            fs.writeFileSync(KEYS_FILE, JSON.stringify(resData.Data, null, 2), 'utf-8')
            const payload = await getPayload({ config: configPromise })
            for (const item of resData.Data) {
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

    const saveCookies = async () => {
      try {
        const cookies = await context.cookies()
        if (cookies.length > 0) {
          const result = {
            targetUrl: 'https://astraflow.scloudsg.com',
            finalUrl: page.url(),
            title: await page.title().catch(() => 'AstraFlow'),
            extractedAt: new Date().toISOString(),
            cookieCount: cookies.length,
            cookieHeader: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
            cookies,
          }
          fs.writeFileSync(COOKIE_FILE, JSON.stringify(result, null, 2), 'utf-8')
        }
      } catch (e) {
        // Ignored
      }
    }

    // Tự động kiểm tra và lưu cookies mỗi 5 giây trong khi người dùng thao tác
    const intervalId = setInterval(saveCookies, 5000)

    page.on('close', async () => {
      clearInterval(intervalId)
      await saveCookies()
      await context.close().catch(() => {})
    })

    // Lưu ngay trạng thái ban đầu
    await saveCookies()

    return NextResponse.json({
      success: true,
      message: 'Đã mở cửa sổ đăng nhập Chrome tại https://passport.scloudsg.com/. Sau khi đăng nhập, bạn truy cập https://astraflow.scloudsg.com/en-us/experience-modelverse/api-keys là hệ thống tự động bắt và lưu toàn bộ Keys!',
    })
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
