// Gửi email qua SMTP hopthu.vn bằng nodemailer
// Cấu hình đọc từ biến môi trường: SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_USER, SMTP_PASS, SMTP_FROM
import nodemailer from 'nodemailer'
import type { Transporter } from 'nodemailer'
import { execFile } from 'child_process'

export interface MailResult {
  ok: boolean
  error?: string
}

const SMTP_HOST = process.env.SMTP_HOST || 'smtp.hopthu.vn'
const SMTP_PORT = Number(process.env.SMTP_PORT || '587')
const SMTP_SECURE = (process.env.SMTP_SECURE || 'false') === 'true'
const SMTP_USER = process.env.SMTP_USER || 'support@mitom.ai'
const SMTP_PASS = process.env.SMTP_PASS || ''
const SMTP_FROM = process.env.SMTP_FROM || '"MiTom AI" <support@mitom.ai>'

let cachedTransporter: Transporter | null = null

export function getTransporter(): Transporter {
  if (!cachedTransporter) {
    cachedTransporter = nodemailer.createTransport({
      host: SMTP_HOST,
      port: SMTP_PORT,
      secure: SMTP_SECURE,
      requireTLS: !SMTP_SECURE,
      auth: { user: SMTP_USER, pass: SMTP_PASS },
      connectionTimeout: 20000,
      greetingTimeout: 15000,
      socketTimeout: 25000,
      tls: { rejectUnauthorized: true },
    })
  }
  return cachedTransporter
}

function encodeRfc2047(text: string): string {
  return '=?UTF-8?B?' + Buffer.from(text, 'utf8').toString('base64') + '?='
}

function buildHtmlEmail(title: string, rows: Array<[string, string]>, footerNote: string): string {
  const rowHtml = rows
    .map(([label, value]) => {
      const strong = value.startsWith('BOLD:')
      const val = strong ? value.slice(5) : value
      return (
        '<tr>' +
        '<td style="padding:8px 12px;color:#6b7280;font-size:13px;white-space:nowrap">' + label + '</td>' +
        '<td style="padding:8px 12px;text-align:right;font-size:14px;' + (strong ? 'font-weight:700;color:#111827' : 'color:#111827') + '">' + val + '</td>' +
        '</tr>'
      )
    })
    .join('')
  return (
    '<div style="font-family:Segoe UI,Arial,sans-serif;max-width:560px;margin:0 auto;border:1px solid #e5e7eb;border-radius:12px;overflow:hidden">' +
    '<div style="background:#4f46e5;padding:20px 24px">' +
    '<div style="color:#ffffff;font-size:20px;font-weight:800">MiTom AI</div>' +
    '<div style="color:#e0e7ff;font-size:13px;margin-top:4px">' + title + '</div>' +
    '</div>' +
    '<div style="padding:24px">' +
    '<table style="width:100%;border-collapse:collapse">' + rowHtml + '</table>' +
    '</div>' +
    '<div style="padding:16px 24px;background:#f9fafb;color:#9ca3af;font-size:12px">' + footerNote + '</div>' +
    '</div>'
  )
}

export { buildHtmlEmail }

export interface MailAttachment {
  filename: string
  content: Buffer
  cid: string
}

export async function sendMail(
  to: string,
  subject: string,
  html: string,
  attachments: MailAttachment[] = [],
): Promise<MailResult> {
  if (!to || !to.includes('@')) {
    return { ok: false, error: 'Email người nhận không hợp lệ' }
  }
  if (!SMTP_PASS) {
    return { ok: false, error: 'Chưa cấu hình SMTP_PASS' }
  }
  const mailOptions: any = {
    from: SMTP_FROM,
    to,
    subject,
    text: subject,
    html,
  }
  if (attachments && attachments.length > 0) {
    mailOptions.attachments = attachments.map((a) => ({
      filename: a.filename,
      content: a.content,
      cid: a.cid,
      encoding: 'base64',
      contentDisposition: 'inline',
    }))
  }
  try {
    const transporter = getTransporter()
    await transporter.sendMail(mailOptions)
    return { ok: true }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    console.error('[mailer] SMTP send failed, fallback to local sendmail:', message)
    // Fallback: gửi qua Postfix local nếu SMTP ngoài lỗi
    return sendMailViaSendmail(to, subject, html)
  }
}

function sendMailViaSendmail(to: string, subject: string, html: string): Promise<MailResult> {
  return new Promise((resolve) => {
    const boundary = '----=_Part_MITOM_' + Date.now()
    const message = [
      'From: MiTom AI <support@mitom.ai>',
      'To: <' + to + '>',
      'Subject: ' + encodeRfc2047(subject),
      'Date: ' + new Date().toUTCString(),
      'MIME-Version: 1.0',
      'Content-Type: multipart/alternative; boundary="' + boundary + '"',
      '',
      '--' + boundary,
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      subject,
      '',
      '--' + boundary,
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      html,
      '',
      '--' + boundary + '--',
      '',
    ].join('\r\n')
    const child = execFile('/usr/sbin/sendmail', ['-t', '-i'], { timeout: 15000 }, (error) => {
      if (error) resolve({ ok: false, error: error.message })
      else resolve({ ok: true })
    })
    if (child.stdin) {
      child.stdin.end(message, 'utf8')
    } else {
      resolve({ ok: false, error: 'Khong mo duoc stdin toi sendmail' })
    }
  })
}

export interface OrderPaidEmailParams {
  customerName: string
  orderCode: string
  planName: string
  invoiceNumber: string
  subtotal: number
  vatRate: number
  vatAmount: number
  totalAmount: number
  transactionId: string
  gateway: string
  paidAt: string
}

export function buildOrderPaidEmail(p: OrderPaidEmailParams): string {
  const money = (n: number) => n.toLocaleString('vi-VN') + ' đ'
  return buildHtmlEmail(
    'Xác nhận thanh toán thành công',
    [
      ['Mã đơn hàng', 'BOLD:' + p.orderCode],
      ['Sản phẩm / Gói', p.planName],
      ['Mã hóa đơn', 'BOLD:' + p.invoiceNumber],
      ['Tiền trước thuế', money(p.subtotal)],
      ['VAT (' + p.vatRate + '%)', money(p.vatAmount)],
      ['Tổng thanh toán', 'BOLD:' + money(p.totalAmount)],
      ['Mã giao dịch ngân hàng', p.transactionId + ' (' + p.gateway + ')'],
      ['Thời gian thanh toán', p.paidAt],
    ],
    'Kính gửi ' +
      (p.customerName || 'Quý khách') +
      ' — Hệ thống đã nhận được thanh toán cho đơn hàng của bạn. ' +
      'Hóa đơn điện tử VAT sẽ được gửi kèm trong vòng 24h làm việc. Email tự động từ hệ thống Mitom AI — mitom.ai'
  )
}
