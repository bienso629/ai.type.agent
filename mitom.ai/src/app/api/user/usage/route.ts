import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'
import { callUCloudApi } from '@/lib/ucloudClient'
import { getSystemUsdRate } from '@/lib/currency'
import fs from 'fs'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

const KEYS_CACHE_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

// Quy doi USD (don vi ghi nhan tren AstraFlow) ve VNĐ de hien thi
function usdToVnd(usd: number | string | undefined | null): number {
  const v = Number(usd)
  if (!Number.isFinite(v) || v <= 0) return 0
  return Math.round(v * getSystemUsdRate())
}

async function getCurrentUser() {
  const cookieStore = await cookies()
  const sessionToken = cookieStore.get('mitom_session')?.value
  if (!sessionToken) return null
  const session = await verifySessionToken(sessionToken)
  if (!session || !session.email) return null
  const payload = await getPayload({ config: configPromise })
  const res = await payload.find({
    collection: 'users',
    where: { email: { equals: session.email } },
    limit: 1,
  })
  return res.docs && res.docs.length > 0 ? res.docs[0] : null
}

// GET: Muc tieu thu API Key tren AstraFlow + lich su cac lan nap so du
export async function GET() {
  try {
    const user = await getCurrentUser()
    if (!user) {
      return NextResponse.json({ success: false, error: 'Chưa xác thực.' }, { status: 401 })
    }
    const payload = await getPayload({ config: configPromise })

    // ===== 1. Thong tin su dung API Key tren AstraFlow (UCloud API) =====
    let astraflow: any = {
      connected: false,
      keyName: '',
      maskedKey: '',
      status: '',
      dailyUsedVnd: 0,
      monthlyUsedVnd: 0,
      dailyLimitVnd: 0,
      monthlyLimitVnd: 0,
      updateTime: '',
    }

    const userKey = String((user as any).apiKey || '').trim()
    if (userKey) {
      astraflow.maskedKey = userKey.length > 14 ? userKey.slice(0, 8) + '...' + userKey.slice(-4) : userKey
      let keyData: any = null

      // 1a. Goi truc tiep API AstraFlow (chu ky UCloud chuan project)
      try {
        const res: any = await callUCloudApi({ Action: 'ListUMInferAPIKey' })
        const list = Array.isArray(res?.Data) ? res.Data : []
        keyData = list.find((k: any) => k.Key === userKey || k.SecretKey === userKey) || null
      } catch {
        // Neu API that bai se fallback xuong cache file ben duoi
      }

      // 1b. Fallback doc file cache dong bo boi cron / playwright sync
      if (!keyData && fs.existsSync(KEYS_CACHE_FILE)) {
        try {
          const cached = JSON.parse(fs.readFileSync(KEYS_CACHE_FILE, 'utf-8'))
          if (Array.isArray(cached)) {
            keyData = cached.find((k: any) => k.Key === userKey) || null
          }
        } catch {
          // Bo qua cache loi
        }
      }

      if (keyData) {
        const updateTimeRaw = Number(keyData.UpdateTime) || 0
        const userBalance = Number((user as any).balance) || 0
        const userDaily = Number((user as any).dailyLimit) || 0
        const userMonthly = Number((user as any).monthlyLimit) || 0

        // Nếu user tự cài hạn mức VNĐ cụ thể (> 0) thì dùng số đó, nếu là mặc định theo số dư (0) thì hiển thị khít 100% bằng số dư tài khoản
        const displayDailyLimit = userDaily > 0 ? userDaily : userBalance
        const displayMonthlyLimit = userMonthly > 0 ? userMonthly : userBalance

        astraflow = {
          connected: true,
          keyName: String(keyData.Name || ''),
          maskedKey: astraflow.maskedKey,
          status: Number(keyData.Status) === 1 ? 'Hoạt động' : 'Tạm khóa',
          dailyUsedVnd: usdToVnd(keyData.DailyUsedAmount),
          monthlyUsedVnd: usdToVnd(keyData.MonthlyUsedAmount),
          dailyLimitVnd: displayDailyLimit,
          monthlyLimitVnd: displayMonthlyLimit,
          updateTime: updateTimeRaw > 0 ? new Date(updateTimeRaw * 1000).toLocaleString('vi-VN') : '',
        }
      }
    }

    // ===== 2. Lich su nap so du: cac don hang da thanh toan cua chinh user =====
    const ordersRes = await payload.find({
      collection: 'orders',
      where: {
        customerEmail: { equals: String(user.email || '').toLowerCase().trim() },
        paymentStatus: { equals: 'paid' },
      },
      sort: '-createdAt',
      limit: 50,
      depth: 0,
    })
    const orders = ordersRes.docs || []

    // Map hoa don theo order de hien thi ma hoa don dien tu
    const invoiceMap: Record<string, string> = {}
    if (orders.length > 0) {
      const orderIds = orders.map((o: any) => o.id)
      const invRes = await payload.find({
        collection: 'invoices',
        where: { order: { in: orderIds } },
        limit: 100,
        depth: 0,
      })
      for (const inv of invRes.docs || []) {
        const oid = typeof inv.order === 'object' ? inv.order?.id : inv.order
        if (oid) invoiceMap[String(oid)] = inv.invoiceNumber || ''
      }
    }

    const history = orders.map((o: any) => ({
      id: o.id,
      orderCode: o.orderCode || '',
      planName: o.planName || 'Nạp số dư',
      subtotal: Number(o.subtotal) || 0,
      vatAmount: Number(o.vatAmount) || 0,
      totalAmount: Number(o.totalAmount) || 0,
      invoiceNumber: invoiceMap[String(o.id)] || `INV-${o.orderCode || ''}`,
      date: o.updatedAt || o.createdAt,
      status: 'paid',
    }))

    // Tong tien da nap vao so du (chua tinh VAT - VAT la thue tren bien lai thanh khoan)
    const totalDeposited = history.reduce((s: number, h: any) => s + (Number(h.subtotal) || 0), 0)

    return NextResponse.json(
      {
        success: true,
        astraflow,
        history,
        stats: { totalDeposited, depositCount: history.length },
        balance: Number((user as any).balance) || 0,
      },
      {
        headers: {
          'Cache-Control': 'no-store, no-cache, must-revalidate',
          Pragma: 'no-cache',
        },
      },
    )
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 })
  }
}
