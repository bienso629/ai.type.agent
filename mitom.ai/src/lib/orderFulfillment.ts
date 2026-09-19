// Module fulfillment sau thanh toán mitom.ai
// Logic: 1 tài khoản - duy nhất 1 API Key. Các lần nạp tiếp theo KHÔNG tạo key mới,
// chỉ cộng dồn số dư tài khoản và gửi email thông báo kèm hóa đơn.
// Email bàn giao thiết kế theo brand mitom.ai (dark theme, rounded-sm, logo inline CID).
import fs from 'fs'
import path from 'path'
import { callUCloudApi } from '@/lib/ucloudClient'
import { convertVndToUsd, formatUsdLimitForVnd } from '@/lib/currency'
import { sendMail } from '@/lib/mailer'

const C = {
  bg: '#08090c',
  card: '#101319',
  cardAlt: '#13161d',
  border: '#23282f',
  primary: '#f5c451',
  success: '#34d399',
  text: '#e5e7eb',
  muted: '#9ca3af',
}

export interface LogoAttachment {
  filename: string
  content: Buffer
  cid: string
}

export function getLogoAttachment(): LogoAttachment | null {
  try {
    const logoPath = path.join(process.cwd(), 'public', 'logo.png')
    return { filename: 'logo.png', content: fs.readFileSync(logoPath), cid: 'mitomlogo' }
  } catch {
    return null
  }
}

function esc(s: unknown): string {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

function money(n: number): string {
  return (Number(n) || 0).toLocaleString('vi-VN') + ' đ'
}

function row(label: string, value: string, strong = false): string {
  return (
    '<tr>' +
    `<td style="padding:10px 16px;color:${C.muted};font-size:13px;white-space:nowrap;border-bottom:1px solid ${C.border}">${esc(label)}</td>` +
    `<td style="padding:10px 16px;text-align:right;font-size:14px;border-bottom:1px solid ${C.border};${strong ? `font-weight:700;color:${C.primary}` : `color:${C.text}`}">${value}</td>` +
    '</tr>'
  )
}

function keyBox(key: string): string {
  return (
    `<div style="margin:16px 0;padding:14px 16px;background:${C.cardAlt};border:1px dashed ${C.primary};border-radius:2px;">` +
    `<div style="color:${C.muted};font-size:12px;margin-bottom:6px;">API KEY CỦA BẠN</div>` +
    `<div style="font-family:'JetBrains Mono',Consolas,monospace;font-size:14px;color:${C.success};word-break:break-all;">${esc(key)}</div>` +
    '</div>'
  )
}

function noteBox(text: string): string {
  return (
    `<div style="margin:16px 0;padding:12px 16px;background:${C.card};border-left:3px solid ${C.primary};border-radius:2px;color:${C.muted};font-size:13px;line-height:1.6;">${text}</div>`
  )
}

export function buildBrandEmail(title: string, bodyInner: string, footerNote: string): string {
  return (
    '<!DOCTYPE html><html><head><meta charset="utf-8"></head>' +
    `<body style="margin:0;padding:24px 12px;background:${C.bg};font-family:'Segoe UI',Arial,sans-serif;">` +
    '<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:560px;margin:0 auto;">' +
    // Header: logo + brand
    `<tr><td style="padding:0 0 20px 0;background:${C.bg};">` +
    '<table role="presentation" cellpadding="0" cellspacing="0"><tr>' +
    `<td style="width:48px;"><img src="cid:mitomlogo" alt="MiTom AI" width="48" style="width:48px;height:auto;display:block;border:1px solid ${C.border};border-radius:2px;"></td>` +
    '<td style="padding-left:12px;">' +
    `<div style="color:${C.primary};font-size:18px;font-weight:700;letter-spacing:0.5px;">MiTom AI</div>` +
    `<div style="color:${C.muted};font-size:13px;margin-top:2px;">${esc(title)}</div>` +
    '</td></tr></table></td></tr>' +
    // Body
    `<tr><td style="background:${C.bg};">${bodyInner}</td></tr>` +
    // Footer
    `<tr><td style="padding:20px 0 0 0;background:${C.bg};">` +
    `<div style="padding:14px 16px;background:${C.card};border:1px solid ${C.border};border-radius:2px;color:${C.muted};font-size:12px;line-height:1.6;">${footerNote}</div>` +
    '<div style="padding:16px 4px 0 4px;color:#4b5563;font-size:11px;text-align:center;">Email tự động từ hệ thống MiTom AI &mdash; mitom.ai</div>' +
    '</td></tr>' +
    '</table></body></html>'
  )
}

export interface FulfillmentResult {
  ok: boolean
  mode: 'new_key' | 'topup' | 'error'
  apiKey?: string
  keyId?: string
  isNewKey: boolean
  newBalance?: number
  emailSent: boolean
  emailError?: string
  message: string
}

function sanitizeKeyName(email: string, orderCode: string): string {
  const local = (email.split('@')[0] || 'user').replace(/[^a-zA-Z0-9]/g, '').slice(0, 24)
  const suffix = orderCode.replace(/[^a-zA-Z0-9]/g, '').slice(-8)
  return `mitom-${local}-${suffix}`
}

export async function fulfillOrder(
  payload: any,
  order: any,
  opts: { transactionId?: string; gateway?: string; invoiceNumber?: string } = {},
): Promise<FulfillmentResult> {
  const email = String(order.customerEmail || '').toLowerCase().trim()
  const orderCode = String(order.orderCode || '')
  const invoiceNumber = opts.invoiceNumber || `INV-${orderCode}`
  const totalAmount = Number(order.totalAmount) || 0
  // Số tiền dịch vụ thực nhận cộng vào số dư tài khoản (chưa bao gồm thuế VAT)
  const creditAmount = order.subtotal !== undefined && order.subtotal !== null && Number(order.subtotal) > 0
    ? Number(order.subtotal)
    : Math.round(totalAmount / 1.1)

  if (!email || !email.includes('@')) {
    return { ok: false, mode: 'error', isNewKey: false, emailSent: false, message: 'Email khách hàng không hợp lệ' }
  }

  // ===== 1. Tra cứu tài khoản khách theo email =====
  const userRes = await payload.find({
    collection: 'users',
    where: { email: { equals: email } },
    limit: 1,
  })
  const user = userRes.docs && userRes.docs.length > 0 ? userRes.docs[0] : null

  // ===== 2. Xác định API Key: đã có thì tái sử dụng, chưa có thì cấp mới =====
  let apiKey = (user && user.apiKey) || ''
  let keyId = ''
  let isNewKey = false

  if (!apiKey && user) {
    // Phòng hờ: user có key trong bảng api-keys nhưng chưa được gán ngược
    const keyRes = await payload.find({
      collection: 'api-keys',
      where: { secretKey: { not_equals: '' } },
      limit: 500,
    })
    const found = (keyRes.docs || []).find((k: any) => k.secretKey && user.apiKey && k.secretKey === user.apiKey)
    if (found) apiKey = found.secretKey
  }

  // Hạn mức hiệu dụng (VNĐ): ưu tiên hạn mức user tự cấu hình, nếu chưa có thì theo số tiền nạp/dư mới
  const dailyProfileVnd = Number(user && user.dailyLimit) || 0
  const monthlyProfileVnd = Number(user && user.monthlyLimit) || 0
  const balanceAfterDeposit = user ? (Number(user.balance) || 0) + creditAmount : creditAmount
  const effectiveDailyVnd = dailyProfileVnd > 0 ? dailyProfileVnd : balanceAfterDeposit
  const effectiveMonthlyVnd = monthlyProfileVnd > 0 ? monthlyProfileVnd : balanceAfterDeposit

  if (!apiKey) {
    // Hạn mức key trên AstraFlow tính bằng USD: quy đổi từ số tiền nạp/hạn mức (VNĐ) làm tròn xuống để không vượt quá số dư
    const res = await callUCloudApi({
      Action: 'CreateUMInferAPIKey',
      Name: sanitizeKeyName(email, orderCode),
      DailyLimitAmount: formatUsdLimitForVnd(effectiveDailyVnd),
      MonthlyLimitAmount: formatUsdLimitForVnd(effectiveMonthlyVnd),
    })
    if (!res || !res.Data || !res.Data.Key) {
      throw new Error('AstraFlow AstraFlow không trả về API Key: ' + JSON.stringify(res).slice(0, 200))
    }
    apiKey = res.Data.Key
    keyId = res.Data.KeyId || ''
    isNewKey = true

    // Lưu key vào CMS (đủ secretKey + rawResponse để hook ApiKeys bỏ qua việc tự tạo key)
    await payload.create({
      collection: 'api-keys',
      data: {
        name: `Key cho ${email}`,
        keyId: keyId || undefined,
        maskedKey: apiKey.length > 14 ? apiKey.slice(0, 10) + '...' + apiKey.slice(-4) : apiKey,
        secretKey: apiKey,
        rawResponse: res.Data,
        permissions: 'Sandbox, Modelverse',
        status: res.Data.Status === 2 ? 'Disabled' : 'Normal',
      },
    })

    // Gán key duy nhất vào tài khoản
    if (user) {
      await payload.update({ collection: 'users', id: user.id, data: { apiKey } })
    }
  }

  // ===== 3. Cộng dồn số dư tài khoản (chỉ cộng tiền dịch vụ trước thuế) =====
  let newBalance: number | undefined
  if (user) {
    newBalance = (Number(user.balance) || 0) + creditAmount
    await payload.update({ collection: 'users', id: user.id, data: { balance: newBalance } })
  }

  // ===== 4. Cập nhật thông tin bàn giao + trạng thái đơn =====
  const deliveryInfo = isNewKey
    ? `API Key: ${apiKey}${keyId ? ` (KeyId: ${keyId})` : ''}`
    : `Tái sử dụng API Key hiện có: ${apiKey} | Số dư sau nạp: ${money(newBalance || 0)}`
  await payload.update({
    collection: 'orders',
    id: order.id,
    data: { deliveryInfo, fulfillmentStatus: 'fulfilled' },
  })

  // ===== 5. Soạn nội dung email theo brand mitom.ai =====
  const customerLabel =
    order.customerType === 'company'
      ? order.companyName || 'Quý khách hàng'
      : order.customerName || 'Quý khách'

  const rowsTable =
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.card};border:1px solid ${C.border};border-radius:2px;">` +
    row('Mã đơn hàng', esc(orderCode), true) +
    row('Gói dịch vụ', esc(order.planName)) +
    row('Mã hóa đơn', esc(invoiceNumber), true) +
    row('Số dư cộng tài khoản', money(creditAmount), true) +
    row('Thuế VAT (10%)', money(totalAmount - creditAmount)) +
    row('Tổng thanh toán', money(totalAmount), true) +
    (opts.transactionId ? row('Mã giao dịch', esc(opts.transactionId) + (opts.gateway ? ` (${esc(opts.gateway)})` : '')) : '') +
    (newBalance !== undefined ? row('Số dư tài khoản mới', money(newBalance), true) : '') +
    '</table>'

  const bodyInner = isNewKey
    ? `<div style="padding:20px;background:${C.card};border:1px solid ${C.border};border-radius:2px;color:${C.text};font-size:14px;line-height:1.6;">` +
      `Kính gửi <strong style="color:${C.primary}">${esc(customerLabel)}</strong>,<br><br>` +
      `Đơn hàng <strong>${esc(orderCode)}</strong> đã được thanh toán thành công. MiTom AI trân trọng bàn giao API Key của bạn:` +
      '</div>' +
      keyBox(apiKey) +
      rowsTable +
      noteBox('Hãy giữ bí mật API Key. Bạn có thể quản lý hạn mức và theo dõi chi tiêu bất kỳ lúc nào tại mitom.ai.')
    : `<div style="padding:20px;background:${C.card};border:1px solid ${C.border};border-radius:2px;color:${C.text};font-size:14px;line-height:1.6;">` +
      `Kính gửi <strong style="color:${C.primary}">${esc(customerLabel)}</strong>,<br><br>` +
      `Hệ thống đã nhận thanh toán nạp tiền cho đơn hàng <strong>${esc(orderCode)}</strong>. Số dư tài khoản của bạn đã được cộng dồn thành công.` +
      '</div>' +
      rowsTable +
      noteBox(`Tài khoản của bạn tiếp tục sử dụng API Key hiện có (không thay đổi). Số dư khả dụng mới: <strong style="color:${C.success}">${money(newBalance || 0)}</strong>.`)

  const footerNote =
    `Đây là email tự động từ hệ thống MiTom AI. ` +
    (isNewKey
      ? 'Nếu bạn không thực hiện đơn hàng này, vui lòng liên hệ support@mitom.ai ngay lập tức.'
      : 'Cảm ơn bạn đã tin tưởng sử dụng dịch vụ của MiTom AI.')

  const subject = isNewKey
    ? `[MiTom AI] Bàn giao API Key - Đơn hàng ${orderCode} - Hóa đơn ${invoiceNumber}`
    : `[MiTom AI] Nạp tiền thành công - Đơn hàng ${orderCode} - Hóa đơn ${invoiceNumber}`

  const html = buildBrandEmail(
    isNewKey ? 'Bàn giao API Key và hóa đơn điện tử' : 'Xác nhận nạp tiền và hóa đơn điện tử',
    bodyInner,
    footerNote,
  )

  // ===== 6. Gửi email (logo nhúng inline CID) =====
  const logo = getLogoAttachment()
  const mailRes = await sendMail(email, subject, html, logo ? [logo] : undefined)

  return {
    ok: true,
    mode: isNewKey ? 'new_key' : 'topup',
    apiKey,
    keyId: keyId || undefined,
    isNewKey,
    newBalance,
    emailSent: mailRes.ok,
    emailError: mailRes.ok ? undefined : mailRes.error,
    message: isNewKey
      ? 'Đã cấp API Key mới và gửi email bàn giao.'
      : 'Đã cộng dồn số dư và gửi email xác nhận nạp tiền.',
  }
}

// ============================================================
// NẠP TIỀN QUA WEBHOOK: cấp key AstraFlow (nếu chưa có key thật)
// + gửi email xác nhận nạp tiền theo brand mitom.ai
// LƯU Ý: số dư đã được cộng ở route gọi hàm này (opts.newBalance)
// ============================================================
export interface DepositKeyResult {
  ok: boolean
  apiKey?: string
  keyId?: string
  isNewKey: boolean
  newBalance?: number
  emailSent: boolean
  emailError?: string
  message: string
}

export async function getOrCreateAstraFlowKey(
  payload: any,
  user: any,
  amount: number,
  opts: { transactionId?: string; gateway?: string; invoiceNumber?: string; newBalance?: number } = {},
): Promise<DepositKeyResult> {
  const email = String(user.email || '').toLowerCase().trim()
  const newBalance = opts.newBalance !== undefined ? opts.newBalance : Number(user.balance) || 0
  const invoiceNumber = opts.invoiceNumber || 'INV-DEPOSIT'
  const orderCode = invoiceNumber.replace(/^INV-/, '')

  if (!email || !email.includes('@')) {
    return { ok: false, isNewKey: false, emailSent: false, message: 'Email khách hàng không hợp lệ' }
  }

  // 1. Kiểm tra key hiện có: nếu user đã có apiKey hợp lệ thì tái sử dụng, không tạo mới
  let apiKey = String(user.apiKey || '').trim()
  let keyId = ''
  let isNewKey = false

  const isValidRealKey = apiKey.length >= 20

  // Hạn mức hiệu dụng (VNĐ): ưu tiên hạn mức user tự cấu hình, nếu chưa có thì theo số dư sau nạp
  const dailyProfileVnd = Number(user.dailyLimit) || 0
  const monthlyProfileVnd = Number(user.monthlyLimit) || 0
  const effectiveDailyVnd = dailyProfileVnd > 0 ? dailyProfileVnd : newBalance
  const effectiveMonthlyVnd = monthlyProfileVnd > 0 ? monthlyProfileVnd : newBalance

  if (!isValidRealKey) {
    // Key rác (mt_...) hoặc trống: gọi AstraFlow cấp key thật, gắn hạn mức USD theo số dư sau nạp làm tròn xuống
    const res = await callUCloudApi({
      Action: 'CreateUMInferAPIKey',
      Name: sanitizeKeyName(email, orderCode),
      DailyLimitAmount: formatUsdLimitForVnd(effectiveDailyVnd),
      MonthlyLimitAmount: formatUsdLimitForVnd(effectiveMonthlyVnd),
    })
    if (!res || !res.Data || !res.Data.Key) {
      throw new Error('AstraFlow không trả về API Key: ' + JSON.stringify(res).slice(0, 200))
    }
    apiKey = res.Data.Key
    keyId = res.Data.KeyId || ''
    isNewKey = true

    await payload.create({
      collection: 'api-keys',
      data: {
        name: `Key cho ${email}`,
        keyId: keyId || undefined,
        maskedKey: apiKey.length > 14 ? apiKey.slice(0, 10) + '...' + apiKey.slice(-4) : apiKey,
        secretKey: apiKey,
        rawResponse: res.Data,
        permissions: 'Sandbox, Modelverse',
        status: res.Data.Status === 2 ? 'Disabled' : 'Normal',
      },
    })

    await payload.update({ collection: 'users', id: user.id, data: { apiKey } })
  } else {
    // Nạp thêm vào key cũ: nâng hạn mức ngày/tháng trên AstraFlow theo số dư mới (quy đổi USD làm tròn xuống)
    try {
      const keyRes = await payload.find({
        collection: 'api-keys',
        where: { secretKey: { equals: apiKey } },
        limit: 1,
      })
      const existingKeyId = (keyRes?.docs?.[0] as any)?.keyId || ''
      if (existingKeyId) {
        await callUCloudApi({
          Action: 'UpdateUMInferAPIKey',
          KeyId: existingKeyId,
          DailyLimitAmount: formatUsdLimitForVnd(effectiveDailyVnd),
          MonthlyLimitAmount: formatUsdLimitForVnd(effectiveMonthlyVnd),
        })
      }
    } catch (err) {
      console.error('[AstraFlow] Khong nang duoc han muc key cu (nap tien van binh thuong):', err)
    }
  }

  // 2. Soạn email theo brand mitom.ai
  const customerLabel = user.name || email.split('@')[0]
  const rowsTable =
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.card};border:1px solid ${C.border};border-radius:2px;">` +
    row('Mã hóa đơn', esc(invoiceNumber), true) +
    row('Gói nạp', money(amount), true) +
    row('Thuế VAT (10%)', money(Math.round(amount * 0.1))) +
    (opts.transactionId ? row('Mã giao dịch', esc(opts.transactionId) + (opts.gateway ? ` (${esc(opts.gateway)})` : '')) : '') +
    row('Tổng đã chuyển khoản', money(Math.round(amount * 1.1))) +
    row('Mã khách hàng', esc(user.customerCode || '')) +
    row('Số dư khả dụng', money(newBalance), true) +
    '</table>'

  const bodyInner = isNewKey
    ? `<div style="padding:20px;background:${C.card};border:1px solid ${C.border};border-radius:2px;color:${C.text};font-size:14px;line-height:1.6;">` +
      `Kính gửi <strong style="color:${C.primary}">${esc(customerLabel)}</strong>,<br><br>` +
      `Hệ thống đã nhận thanh toán nạp tiền thành công. MiTom AI trân trọng bàn giao API Key của bạn:` +
      '</div>' +
      keyBox(apiKey) +
      rowsTable +
      noteBox('Hãy giữ bí mật API Key. Bạn có thể quản lý hạn mức và theo dõi chi tiêu bất kỳ lúc nào tại mitom.ai.')
    : `<div style="padding:20px;background:${C.card};border:1px solid ${C.border};border-radius:2px;color:${C.text};font-size:14px;line-height:1.6;">` +
      `Kính gửi <strong style="color:${C.primary}">${esc(customerLabel)}</strong>,<br><br>` +
      `Hệ thống đã nhận thanh toán nạp tiền thành công. Số dư tài khoản của bạn đã được cộng dồn.` +
      '</div>' +
      rowsTable +
      noteBox(`Tài khoản của bạn tiếp tục sử dụng API Key hiện có (không thay đổi). Số dư khả dụng mới: <strong style="color:${C.success}">${money(newBalance)}</strong>.`)

  const footerNote =
    `Đây là email tự động từ hệ thống MiTom AI. ` +
    (isNewKey
      ? 'Nếu bạn không thực hiện giao dịch này, vui lòng liên hệ support@mitom.ai ngay lập tức.'
      : 'Cảm ơn bạn đã tin tưởng sử dụng dịch vụ của MiTom AI.')

  const subject = isNewKey
    ? `[MiTom AI] Bàn giao API Key - Nạp tiền thành công - Hóa đơn ${invoiceNumber}`
    : `[MiTom AI] Nạp tiền thành công - Hóa đơn ${invoiceNumber}`

  const html = buildBrandEmail(
    isNewKey ? 'Bàn giao API Key và hóa đơn điện tử' : 'Xác nhận nạp tiền và hóa đơn điện tử',
    bodyInner,
    footerNote,
  )

  // 3. Gửi email (logo inline CID)
  const logo = getLogoAttachment()
  const mailRes = await sendMail(email, subject, html, logo ? [logo] : undefined)

  return {
    ok: true,
    apiKey,
    keyId: keyId || undefined,
    isNewKey,
    newBalance,
    emailSent: mailRes.ok,
    emailError: mailRes.ok ? undefined : mailRes.error,
    message: isNewKey
      ? 'Đã cấp API Key AstraFlow mới và gửi email bàn giao.'
      : 'Đã xác nhận nạp tiền, tái sử dụng API Key hiện có và gửi email.',
  }
}
