import crypto from 'crypto'

/**
 * Tập ký tự loại bỏ các ký tự dễ gây nhầm lẫn:
 * Không có 0 (số không) và O (chữ O)
 * Không có 1 (số một), I (chữ I hoa), L (chữ L hoa)
 */
const CHARSET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'

/**
 * Sinh mã khách hàng ngẫu nhiên định dạng: MITO + 6 ký tự
 * Ví dụ: MITOT35R5M, MITOQEY57S
 */
export function generateCustomerCode(): string {
  const bytes = crypto.randomBytes(6)
  let code = 'MITO'
  for (let i = 0; i < 6; i++) {
    code += CHARSET[bytes[i] % CHARSET.length]
  }
  return code
}
