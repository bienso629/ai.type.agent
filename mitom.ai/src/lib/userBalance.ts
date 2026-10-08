import { BasePayload } from 'payload'
import { callUCloudApi } from '@/lib/ucloudClient'
import { getSystemUsdRate, getListPriceMultiplier, convertCostToCustomerListPrice } from '@/lib/currency'
import fs from 'fs'
import path from 'path'

const KEYS_CACHE_FILE = path.resolve(process.cwd(), 'astraflow_keys.json')

function usdCostToListPriceVnd(usd: number | string | undefined | null, multiplier: number): number {
  const v = Number(usd)
  if (!Number.isFinite(v) || v <= 0) return 0
  const costVnd = v * getSystemUsdRate()
  const listPriceVnd = convertCostToCustomerListPrice(costVnd, multiplier)
  return Math.round(listPriceVnd * 100) / 100
}

/**
 * Tính toán và đồng bộ số dư chuẩn xác tuyệt đối cho user:
 * Số dư = Tổng số tiền đã nạp từ các đơn hàng paid - Tổng số tiền đã sử dụng toàn thời gian từ AstraFlow
 */
export async function syncAndCalculateUserBalance(
  payload: BasePayload,
  user: any
): Promise<{
  actualBalance: number
  totalDepositedVnd: number
  allTimeUsedVnd: number
  dailyUsedVnd: number
  monthlyUsedVnd: number
  keyData: any
  historyMap: Record<string, number>
}> {
  const userKey = String(user.apiKey || '').trim()
  let keyData: any = null

  // 1. Lấy dữ liệu API Key mới nhất từ AstraFlow
  if (userKey) {
    try {
      const res: any = await callUCloudApi({ Action: 'ListUMInferAPIKey' })
      const list = Array.isArray(res?.Data) ? res.Data : []
      keyData = list.find((k: any) => k.Key === userKey || k.SecretKey === userKey) || null
    } catch {
      // Fallback xuống cache nếu API mạng bận
    }

    if (!keyData && fs.existsSync(KEYS_CACHE_FILE)) {
      try {
        const cached = JSON.parse(fs.readFileSync(KEYS_CACHE_FILE, 'utf-8'))
        if (Array.isArray(cached)) {
          keyData = cached.find((k: any) => k.Key === userKey) || null
        }
      } catch {}
    }
  }

  // 2. Hệ số chiết khấu đại lý / List Price
  let listPriceMultiplier = getListPriceMultiplier()
  try {
    const settings = await payload.findGlobal({ slug: 'system-settings' })
    if (settings && (settings as any).listPriceMultiplier && Number((settings as any).listPriceMultiplier) >= 1) {
      listPriceMultiplier = Number((settings as any).listPriceMultiplier)
    }
  } catch {}

  // 3. Lịch sử tiêu thụ theo ngày từ database CMS
  let historyMap: Record<string, number> = {}
  let dbKeyDoc: any = null

  if (userKey) {
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
        overrideAccess: true,
        limit: 1,
      })
      if (dbKeyRes.docs.length > 0) {
        dbKeyDoc = dbKeyRes.docs[0]
        const h = (dbKeyDoc as any).usageHistory
        if (h && typeof h === 'object') {
          historyMap = { ...h }
        } else if (typeof h === 'string') {
          try {
            historyMap = JSON.parse(h)
          } catch {
            historyMap = {}
          }
        }
      }
    } catch {}
  }

  let dailyUsedVnd = 0
  let monthlyUsedVnd = 0
  let allTimeUsedVnd = 0

  if (keyData) {
    const nowVn = new Date(Date.now() + 7 * 60 * 60 * 1000)
    const todayStr = nowVn.toISOString().split('T')[0]
    const currentDailyUsd = Number(keyData.DailyUsedAmount) || 0
    historyMap[todayStr] = currentDailyUsd

    if (dbKeyDoc && dbKeyDoc.id) {
      try {
        await payload.update({
          collection: 'api-keys',
          id: dbKeyDoc.id,
          overrideAccess: true,
          data: {
            secretKey: userKey,
            dailySpend: String(currentDailyUsd),
            monthlySpend: String(keyData.MonthlyUsedAmount || '0'),
            usageHistory: historyMap,
          } as any,
        })
      } catch {}
    }

    dailyUsedVnd = usdCostToListPriceVnd(keyData.DailyUsedAmount, listPriceMultiplier)
    monthlyUsedVnd = usdCostToListPriceVnd(keyData.MonthlyUsedAmount, listPriceMultiplier)

    const totalAllTimeUsedUsd = Object.values(historyMap).reduce(
      (sum, usd) => sum + (Number(usd) || 0),
      0,
    )
    allTimeUsedVnd = usdCostToListPriceVnd(totalAllTimeUsedUsd, listPriceMultiplier)
  }

  // 4. Tính tổng tiền nạp từ các đơn hàng đã thanh toán (paid)
  let totalDepositedVnd = 0
  try {
    const userOrders = await payload.find({
      collection: 'orders',
      where: {
        customerEmail: { equals: String(user.email || '').toLowerCase().trim() },
        paymentStatus: { equals: 'paid' },
      },
      overrideAccess: true,
      limit: 200,
    })
    totalDepositedVnd = (userOrders.docs || []).reduce(
      (sum: number, o: any) => sum + (Number(o.subtotal) || 0),
      0
    )
  } catch {}

  // 5. Số dư = Tổng nạp - Toàn bộ quá trình đã sử dụng từ đầu đến cuối
  let actualBalance = Number(user.balance) || 0
  if (totalDepositedVnd > 0) {
    actualBalance = Math.round(Math.max(0, totalDepositedVnd - allTimeUsedVnd) * 100) / 100
  }

  if (actualBalance !== Number(user.balance)) {
    try {
      await payload.update({
        collection: 'users',
        id: user.id,
        overrideAccess: true,
        data: {
          balance: actualBalance,
        } as any,
      })
      user.balance = actualBalance
    } catch {}
  }

  return {
    actualBalance,
    totalDepositedVnd,
    allTimeUsedVnd,
    dailyUsedVnd,
    monthlyUsedVnd,
    keyData,
    historyMap,
  }
}
