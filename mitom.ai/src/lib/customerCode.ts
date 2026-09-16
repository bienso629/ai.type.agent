import crypto from 'crypto'

/**
 * Sinh mã khách hàng ngẫu nhiên bảo mật định dạng: MITO-XXXXXX (ví dụ: MITO-8K3N9P)
 * Không chứa các ký tự dễ nhầm lẫn như 0, O, 1, I, L.
 * Đảm bảo tuyệt đối không lộ ID tăng dần tuần tự của User trong cơ sở dữ liệu.
 */
export function generateCustomerCode(): string {
  const chars = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
  let result = ''
  const bytes = crypto.randomBytes(6)
  for (let i = 0; i < 6; i++) {
    result += chars[bytes[i] % chars.length]
  }
  return `MITO${result}`
}
