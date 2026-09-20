import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { verifySessionToken } from '@/lib/auth'
import { callUCloudApi } from '@/lib/ucloudClient'
import { getSystemUsdRate, getListPriceMultiplier, convertCostToCustomerListPrice } from '@/lib/currency'
import fs from 'fs'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

const KEYS_CACHE_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

// Quy đổi USD (đơn vị ghi nhận gốc trên AstraFlow) về VNĐ theo giá niêm yết bán lẻ (List Price) mà khách hàng chi trả
function usdCostToListPriceVnd(usd: number | string | undefined | null, multiplier: number): number {
  const v = Number(usd)
  if (!Number.isFinite(v) || v <= 0) return 0
  const costVnd = v * getSystemUsdRate()
  return Math.round(convertCostToCustomerListPrice(costVnd, multiplier))
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
export async function GET(request: Request) {
  try {
    const user = await getCurrentUser()
    if (!user) {
      return NextResponse.json({ success: false, error: 'Chưa xác thực.' }, { status: 401 })
    }
    const payload = await getPayload({ config: configPromise })
    const { searchParams } = new URL(request.url)
    const queryDate = searchParams.get('date')?.trim() // YYYY-MM-DD

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
      dailyHistory: [] as { date: string; usedVnd: number }[],
      selectedDate: queryDate || null,
      selectedDateUsedVnd: null as number | null,
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

    // Lấy cài đặt hệ thống về hệ số List Price của đại lý
    let listPriceMultiplier = getListPriceMultiplier()
    try {
      const settings = await payload.findGlobal({ slug: 'system-settings' })
      if (settings && (settings as any).listPriceMultiplier && Number((settings as any).listPriceMultiplier) >= 1) {
        listPriceMultiplier = Number((settings as any).listPriceMultiplier)
      }
    } catch {
      // Fallback theo biến môi trường
    }

    // Đọc lịch sử tiêu thụ theo ngày từ database CMS bảng api-keys
    let historyMap: Record<string, number> = {}
    let dbKeyDoc: any = null
    try {
      const dbKeyRes = await payload.find({
        collection: 'api-keys',
        where: {
          or: [
            { secretKey: { equals: userKey } },
            { maskedKey: { equals: userKey } },
            { keyId: { equals: keyData?.KeyId || 'not-matched' } },
          ],
        },
        limit: 1,
      })
      if (dbKeyRes.docs.length > 0) {
        dbKeyDoc = dbKeyRes.docs[0]
        const h = (dbKeyDoc as any).usageHistory
        if (h && typeof h === 'object') {
          historyMap = { ...h }
        } else if (typeof h === 'string') {
          historyMap = JSON.parse(h)
        }
      }
    } catch {
      historyMap = {}
    }

    if (keyData) {
      const updateTimeRaw = Number(keyData.UpdateTime) || 0
      const userBalance = Number((user as any).balance) || 0
      const userDaily = Number((user as any).dailyLimit) || 0
      const userMonthly = Number((user as any).monthlyLimit) || 0

      // Cập nhật ngày hôm nay vào historyMap
      const todayStr = new Date().toISOString().split('T')[0]
      const currentDailyUsd = Number(keyData.DailyUsedAmount) || 0
      historyMap[todayStr] = currentDailyUsd

      // Tự động lưu cập nhật historyMap vào database nếu có thay đổi
      if (dbKeyDoc && dbKeyDoc.id) {
        try {
          await payload.update({
            collection: 'api-keys',
            id: dbKeyDoc.id,
            data: {
              secretKey: userKey,
              dailySpend: String(currentDailyUsd),
              monthlySpend: String(keyData.MonthlyUsedAmount || '0'),
              usageHistory: historyMap,
            } as any,
          })
        } catch {
          // Bo qua loi update ngam
        }
      }

      // Nếu user tự cài hạn mức VNĐ cụ thể (> 0) thì dùng số đó nhưng không vượt quá số dư hiện có, nếu là 0 thì mặc định bằng 100% số dư tài khoản
      const displayDailyLimit = userDaily > 0 ? Math.min(userDaily, userBalance) : userBalance
      const displayMonthlyLimit = userMonthly > 0 ? Math.min(userMonthly, userBalance) : userBalance

      // Danh sách tiêu thụ theo từng ngày quy đổi ra List Price (VNĐ)
      const dailyHistory = Object.entries(historyMap)
        .map(([date, usd]) => ({
          date,
          usedVnd: usdCostToListPriceVnd(usd, listPriceMultiplier),
        }))
        .sort((a, b) => b.date.localeCompare(a.date))

      // Nếu khách chọn một ngày bất kỳ, tra cứu số tiền tiêu thụ của ngày đó
      let selectedDateUsedVnd: number | null = null
      if (queryDate) {
        const foundDay = dailyHistory.find((d) => d.date === queryDate)
        selectedDateUsedVnd = foundDay ? foundDay.usedVnd : 0
      }

      astraflow = {
        connected: true,
        keyName: String(keyData.Name || ''),
        maskedKey: astraflow.maskedKey,
        status: Number(keyData.Status) === 1 ? 'Hoạt động' : 'Tạm khóa',
        dailyUsedVnd: usdCostToListPriceVnd(keyData.DailyUsedAmount, listPriceMultiplier),
        monthlyUsedVnd: usdCostToListPriceVnd(keyData.MonthlyUsedAmount, listPriceMultiplier),
        dailyLimitVnd: displayDailyLimit,
        monthlyLimitVnd: displayMonthlyLimit,
        updateTime: updateTimeRaw > 0 ? new Date(updateTimeRaw * 1000).toLocaleString('vi-VN') : '',
        dailyHistory,
        selectedDate: queryDate || null,
        selectedDateUsedVnd,
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
