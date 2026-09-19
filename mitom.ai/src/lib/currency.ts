/**
 * Module xử lý tỷ giá USD / VNĐ gọn nhẹ từ biến môi trường
 */

const DEFAULT_USD_RATE = 26000

/**
 * Lấy tỷ giá USD/VND hiện hành từ .env (fallback 26000)
 */
export function getSystemUsdRate(): number {
  const envRate = process.env.USD_RATE || process.env.NEXT_PUBLIC_USD_RATE
  if (envRate) {
    const parsed = Number(envRate)
    if (!isNaN(parsed) && parsed > 0) {
      return parsed
    }
  }
  return DEFAULT_USD_RATE
}

/**
 * Quy đổi từ số tiền VNĐ sang số dư USD
 */
export function convertVndToUsd(vndAmount: number, rate?: number): number {
  if (!vndAmount || vndAmount <= 0) return 0
  const appliedRate = rate || getSystemUsdRate()
  const usd = vndAmount / appliedRate
  // Làm tròn 4 chữ số thập phân
  return Math.round(usd * 10000) / 10000
}

/**
 * Quy đổi từ số tiền VNĐ sang chuỗi USD 2 chữ số thập phân cho hạn mức AstraFlow.
 * Bắt buộc làm tròn xuống (floor) 2 chữ số thập phân để đảm bảo khi quy đổi ngược lại VNĐ,
 * số tiền hạn mức USD trên hệ thống không bao giờ vượt quá số dư/hạn mức VNĐ thực tế của người dùng.
 */
export function formatUsdLimitForVnd(vndAmount: number, rate?: number): string {
  if (!vndAmount || vndAmount <= 0) return '0.00'
  const appliedRate = rate || getSystemUsdRate()
  const rawUsd = vndAmount / appliedRate
  // Cắt (floor) tại 2 chữ số thập phân
  const floored = Math.floor(rawUsd * 100) / 100
  return floored.toFixed(2)
}
