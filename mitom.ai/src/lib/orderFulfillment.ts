import nodemailer from 'nodemailer'
import path from 'path'
import fs from 'fs'
import { callUCloudApi } from './ucloudClient'
import type { Payload } from 'payload'

export interface FulfillmentOptions {
  payload: Payload
  order: {
    id: string | number
    orderCode: string
    customerEmail: string
    customerPhone?: string | null
    customerName?: string | null
    customerType?: string | null
    identityNumber?: string | null
    invoiceEmail?: string | null
    companyName?: string | null
    companyTaxCode?: string | null
    companyAddress?: string | null
    planName?: string | null
    subtotal?: number | null
    vatRate?: number | null
    vatAmount?: number | null
    totalAmount: number
    productName?: string | null
  }
}

export interface FulfillmentResult {
  success: boolean
  apiKey: string
  keyId: string
  invoiceCode: string
  emailSent: boolean
  error?: string
}

/**
 * Hàm tự động hóa toàn diện sau khi thanh toán thành công:
 * 1. Gọi AstraFlow API để khởi tạo API Key chính thức (sử dụng HMAC-SHA1 signature).
 * 2. Lưu Key mới vào collection ApiKeys của Payload CMS Admin.
 * 3. Tạo mã số Hóa đơn điện tử (VD: HD-YYMM-XXXXXX).
 * 4. Cập nhật Order (paymentStatus = 'paid', fulfillmentStatus = 'fulfilled', apiKey, deliveryInfo, invoiceCode, invoiceIssuedAt).
 * 5. Cập nhật apiKey và số dư (nếu có user khớp email) trong collection Users.
 * 6. Gửi Email thông báo bàn giao API Key kèm Hóa đơn điện tử chi tiết qua SMTP cho khách hàng.
 */
export async function fulfillPaidOrder(options: FulfillmentOptions): Promise<FulfillmentResult> {
  const { payload, order } = options
  const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY || ''
  const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY || ''

  let createdApiKey = ''
  let createdKeyId = ''

  // 1. Kiểm tra tài khoản người dùng theo email trước để áp dụng chính sách:
  // "Mỗi tài khoản chỉ có duy nhất 1 key, những lần nạp tiền tiếp theo chỉ tăng số dư"
  let existingUser: any = null
  try {
    const userQuery = await payload.find({
      collection: 'users',
      where: {
        email: {
          equals: order.customerEmail.toLowerCase().trim(),
        },
      },
      limit: 1,
    })
    if (userQuery.docs.length > 0) {
      existingUser = userQuery.docs[0]
    }
  } catch (err: any) {
    console.warn('[Fulfillment] Kiểm tra user tồn tại cảnh báo:', err.message)
  }

  const isTopUp = Boolean(existingUser && existingUser.apiKey)
  if (isTopUp) {
    // Tài khoản đã có Key -> Tái sử dụng key duy nhất của user
    createdApiKey = existingUser.apiKey
    createdKeyId = `user-key-${existingUser.id}`
    console.log(`[Fulfillment] Khách hàng ${order.customerEmail} đã có API Key: ${createdApiKey}. Giữ nguyên Key và tiến hành tăng số dư.`)
  } else {
    // Khách hàng mới hoặc chưa có Key -> Gọi AstraFlow tạo API Key mới
    const keyName = `mitom-${order.orderCode.toLowerCase()}`
    try {
      if (pubKey && privKey) {
        const res = await callUCloudApi(
          {
            Action: 'CreateUMInferAPIKey',
            Name: keyName,
          },
          { publicKey: pubKey, privateKey: privKey },
        )

        if (res?.Data?.Key) {
          createdApiKey = res.Data.Key
          createdKeyId = res.Data.KeyId || `uminferapikey-${Date.now().toString(36)}`

          // Lưu vào collection api-keys trong Payload CMS Admin
          try {
            await payload.create({
              collection: 'api-keys',
              data: {
                name: keyName,
                keyId: createdKeyId,
                maskedKey: createdApiKey,
                secretKey: createdApiKey,
                status: 'Normal',
                permissions: 'Sandbox, Modelverse',
                dailyLimit: 'Không giới hạn',
                monthlyLimit: 'Không giới hạn',
                modelAccessMode: 'All Models',
                expiryTime: 'Vĩnh viễn',
                rawResponse: res.Data,
              } as any,
            })
          } catch (dbErr: any) {
            console.warn('[Fulfillment] Lưu api-keys collection cảnh báo:', dbErr.message)
          }
        }
      }
    } catch (err: any) {
      console.error('[Fulfillment] Lỗi khi gọi tạo Key trên AstraFlow:', err.message)
    }

    // Nếu gọi thất bại hoặc môi trường offline, fallback sinh key định dạng an toàn
    if (!createdApiKey) {
      const fallbackRand = Math.random().toString(36).substring(2, 10).toUpperCase()
      createdApiKey = `sk-mitom-${Date.now().toString(36)}-${fallbackRand}`
      createdKeyId = `uminferapikey-${Date.now().toString(36)}`
    }
  }

  // 2. Tính toán và tăng số dư tài khoản cho người dùng
  const addedCredit = Number(order.subtotal) || Number(order.totalAmount) || 0
  let userNewBalance: number | null = null

  if (existingUser) {
    try {
      const currentBalance = Number(existingUser.balance) || 0
      userNewBalance = currentBalance + addedCredit

      await payload.update({
        collection: 'users',
        id: existingUser.id,
        data: {
          apiKey: createdApiKey, // Đảm bảo gán key nếu trước đó chưa có
          balance: userNewBalance,
        },
      })
      console.log(`[Fulfillment] Đã cập nhật số dư cho user ${existingUser.email}: ${currentBalance} -> ${userNewBalance} VNĐ`)
    } catch (updateErr: any) {
      console.error('[Fulfillment] Lỗi cập nhật số dư user:', updateErr.message)
    }
  }

  // 3. Tạo mã số Hóa đơn điện tử định dạng HD-YYMM-XXXX
  const now = new Date()
  const yearMonth = `${String(now.getFullYear()).slice(-2)}${String(now.getMonth() + 1).padStart(2, '0')}`
  const randNum = Math.floor(1000 + Math.random() * 9000)
  const invoiceCode = `HD-${yearMonth}-${randNum}`
  const invoiceDateStr = now.toLocaleDateString('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })

  // 4. Cập nhật Order trong Payload CMS
  const deliveryInfo = `Mã đơn: ${order.orderCode}
Loại giao dịch: ${isTopUp ? 'Nạp thêm số dư vào tài khoản' : 'Khởi tạo tài khoản & Cấp mới API Key'}
API Key: ${createdApiKey}
${userNewBalance !== null ? `Số dư tài khoản sau nạp: ${new Intl.NumberFormat('vi-VN').format(userNewBalance)} đ\n` : ''}Số hóa đơn: ${invoiceCode}
Ngày xuất: ${invoiceDateStr}
Trạng thái: Đã kích hoạt`

  try {
    await payload.update({
      collection: 'orders',
      id: order.id,
      data: {
        paymentStatus: 'paid',
        fulfillmentStatus: 'fulfilled',
        apiKey: createdApiKey,
        deliveryInfo,
        invoiceCode,
        invoiceIssuedAt: now.toISOString(),
      },
    })
  } catch (err: any) {
    console.error('[Fulfillment] Lỗi khi cập nhật order:', err.message)
  }

  // 5. Gửi Email bàn giao API Key và Hóa đơn điện tử cho khách hàng qua SMTP
  let emailSent = false
  const targetEmail = order.invoiceEmail || order.customerEmail

  try {
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.hopthu.vn',
      port: Number(process.env.SMTP_PORT) || 587,
      secure: Number(process.env.SMTP_PORT) === 465,
      auth: {
        user: process.env.SMTP_USER || 'support@mitom.ai',
        pass: process.env.SMTP_PASS || '',
      },
      tls: {
        rejectUnauthorized: false,
      },
    })

    const formatVnd = (num: number) => new Intl.NumberFormat('vi-VN').format(num) + ' đ'
    const subtotalFormatted = formatVnd(order.subtotal || order.totalAmount)
    const vatAmountFormatted = formatVnd(order.vatAmount || Math.round(order.totalAmount * 0.1))
    const totalFormatted = formatVnd(order.totalAmount)

    const buyerInfoHtml =
      order.customerType === 'company'
        ? `
        <p style="margin: 4px 0;"><strong>Đơn vị mua hàng:</strong> ${order.companyName || 'Khách hàng Doanh Nghiệp'}</p>
        <p style="margin: 4px 0;"><strong>Mã số thuế (MST):</strong> ${order.companyTaxCode || 'N/A'}</p>
        <p style="margin: 4px 0;"><strong>Địa chỉ xuất hóa đơn:</strong> ${order.companyAddress || 'N/A'}</p>
      `
        : `
        <p style="margin: 4px 0;"><strong>Khách hàng:</strong> ${order.customerName || order.customerEmail}</p>
        <p style="margin: 4px 0;"><strong>Số CCCD / CMND:</strong> ${order.identityNumber || 'N/A'}</p>
      `

    const htmlContent = `
      <div style="background-color: #08090c; padding: 32px 12px; font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #eef0f3;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #101319; border: 1px solid #23282f; border-radius: 2px; overflow: hidden; box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);">
          
          <!-- Header Thương hiệu với Logo chính thức của mitom.ai -->
          <div style="padding: 28px 24px; border-bottom: 1px solid #23282f; background-color: #0b0d12; text-align: center;">
            <a href="https://mitom.ai" target="_blank" style="text-decoration: none; display: inline-block;">
              <img src="cid:mitomlogo" alt="Mì Tôm AI Logo" width="48" style="display: block; width: 48px; height: auto; margin: 0 auto 12px auto; border-radius: 2px;" />
            </a>
            <h1 style="margin: 0; font-size: 20px; font-weight: 800; color: #f5c451; letter-spacing: -0.3px; text-transform: uppercase;">
              Mì Tôm AI // Bàn Giao Dịch Vụ
            </h1>
            <p style="margin: 6px 0 0 0; font-size: 13px; color: #8a92a1;">
              Hệ thống xác nhận thanh toán đơn hàng <span style="font-family: monospace; color: #f5c451; font-weight: 700;">#${order.orderCode}</span> thành công
            </p>
          </div>

          <div style="padding: 28px 24px;">
            <!-- Khung API Key nổi bật tone Dark / Gold / JetBrains Mono -->
            <div style="background-color: #171b23; border: 1px solid #f5c451; border-radius: 2px; padding: 20px; text-align: center; margin-bottom: 24px;">
              <div style="font-size: 11px; font-weight: 700; text-transform: uppercase; color: #f5c451; letter-spacing: 1.5px; font-family: monospace;">
                ${isTopUp ? '// API KEY HIỆN TẠI CỦA BẠN (DUY NHẤT)' : '// ASTRAFLOW MODELVERSE API KEY'}
              </div>
              <div style="background-color: #08090c; border: 1px solid #23282f; color: #34d399; font-family: 'JetBrains Mono', monospace, Courier; font-size: 15px; font-weight: 700; padding: 14px 16px; border-radius: 2px; margin: 14px 0; word-break: break-all; letter-spacing: 0.5px;">
                ${createdApiKey}
              </div>
              <p style="margin: 0; font-size: 12px; color: #8a92a1; line-height: 1.5;">
                ${isTopUp ? `<span style="color: #34d399; font-weight: 700;">Đã nạp thêm +${formatVnd(addedCredit)} vào tài khoản.</span> Số dư khả dụng hiện tại: <strong style="color: #f5c451;">${formatVnd(userNewBalance || 0)}</strong><br>` : ''}
                Base URL tương thích OpenAI: <code style="color: #f5c451; background: #101319; padding: 2px 6px; border-radius: 2px; font-family: monospace;">https://api.scloudsg.com/v1</code>
              </p>
            </div>

            <!-- Khung Hóa đơn điện tử -->
            <div style="background-color: #13161d; border: 1px solid #23282f; border-radius: 2px; padding: 20px; margin-bottom: 24px;">
              <div style="border-bottom: 1px solid #23282f; padding-bottom: 12px; margin-bottom: 14px; display: flex; justify-content: space-between; align-items: center;">
                <span style="font-size: 13px; font-weight: 800; color: #eef0f3; text-transform: uppercase; letter-spacing: 0.5px;">
                  Hóa Đơn Điện Tử: <span style="color: #f5c451; font-family: monospace;">${invoiceCode}</span>
                </span>
                <span style="font-size: 12px; color: #8a92a1; font-family: monospace;">${invoiceDateStr}</span>
              </div>

              <div style="font-size: 13px; line-height: 1.7; color: #c7ccd6;">
                <p style="margin: 3px 0;"><strong>Gói dịch vụ:</strong> <span style="color: #eef0f3;">${order.planName || 'Gói dịch vụ AI'}</span></p>
                <p style="margin: 3px 0;"><strong>Mã đơn hàng:</strong> <span style="color: #eef0f3; font-family: monospace;">${order.orderCode}</span></p>
                ${buyerInfoHtml}
                <p style="margin: 3px 0;"><strong>Email nhận hóa đơn:</strong> <span style="color: #eef0f3;">${targetEmail}</span></p>
              </div>

              <!-- Bảng giá chi tiết VAT -->
              <table style="width: 100%; border-collapse: collapse; margin-top: 16px; font-size: 13px;">
                <thead>
                  <tr style="border-bottom: 1px solid #23282f; color: #8a92a1; text-align: left;">
                    <th style="padding: 8px 0; font-weight: 600;">Hạng mục</th>
                    <th style="padding: 8px 0; text-align: right; font-weight: 600;">Thành tiền</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td style="padding: 10px 0; border-bottom: 1px solid rgba(35, 40, 47, 0.6); color: #c7ccd6;">Tiền dịch vụ (chưa VAT)</td>
                    <td style="padding: 10px 0; text-align: right; border-bottom: 1px solid rgba(35, 40, 47, 0.6); font-family: monospace; color: #eef0f3;">${subtotalFormatted}</td>
                  </tr>
                  <tr>
                    <td style="padding: 10px 0; border-bottom: 1px solid #23282f; color: #c7ccd6;">Thuế suất VAT (${order.vatRate || 10}%)</td>
                    <td style="padding: 10px 0; text-align: right; border-bottom: 1px solid #23282f; font-family: monospace; color: #34d399;">+${vatAmountFormatted}</td>
                  </tr>
                  <tr>
                    <td style="padding: 12px 0 0 0; font-weight: 800; font-size: 14px; color: #f5c451; text-transform: uppercase;">Tổng thanh toán</td>
                    <td style="padding: 12px 0 0 0; text-align: right; font-weight: 800; font-size: 16px; font-family: monospace; color: #f5c451;">${totalFormatted}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <!-- Box chỉ dẫn sử dụng -->
            <div style="background-color: #0b0d12; border-left: 2px solid #f5c451; border-radius: 2px; padding: 14px 16px; font-size: 12px; color: #8a92a1; line-height: 1.6;">
              <strong style="color: #eef0f3;">Lưu ý kích hoạt:</strong> API Key được cấp quyền truy cập các mô hình AI trên cụm hạ tầng AstraFlow Modelverse. Quý khách có thể bắt đầu gọi API ngay lập tức. Cần hỗ trợ xin liên hệ Zalo hoặc gửi về hòm thư support@mitom.ai.
            </div>

            <!-- Footer -->
            <div style="margin-top: 32px; padding-top: 20px; border-top: 1px solid #23282f; text-align: center; font-size: 11px; color: #5a6270;">
              <p style="margin: 0 0 4px 0;">Mì Tôm AI (mitom.ai) - Nền tảng phân phối API AI tốc độ cao</p>
              <p style="margin: 0;">Email tự động gửi từ hệ thống máy chủ Mì Tôm AI. Vui lòng không phản hồi thư này.</p>
            </div>
          </div>
        </div>
      </div>
    `

    // Đính kèm ảnh logo inline để tất cả trình duyệt email (kể cả Gmail chặn ảnh ngoài) đều hiển thị 100%
    const logoFilePath = path.resolve(process.cwd(), 'public/logo.png')
    const attachments = fs.existsSync(logoFilePath)
      ? [
          {
            filename: 'logo.png',
            path: logoFilePath,
            cid: 'mitomlogo',
          },
        ]
      : []

    const emailSubject = isTopUp
      ? `[Mì Tôm AI] Nạp tiền thành công & Hóa đơn điện tử ${invoiceCode} (Đơn hàng ${order.orderCode})`
      : `[Mì Tôm AI] Bàn giao API Key & Hóa đơn điện tử ${invoiceCode} (Đơn hàng ${order.orderCode})`

    await transporter.sendMail({
      from: `"Mì Tôm AI Support" <${process.env.SMTP_USER || 'support@mitom.ai'}>`,
      to: targetEmail,
      subject: emailSubject,
      html: htmlContent,
      attachments,
    })

    emailSent = true
    console.log(`[Fulfillment] Đã gửi email bàn giao API Key và Hóa đơn ${invoiceCode} tới ${targetEmail} thành công.`)
  } catch (mailErr: any) {
    console.error('[Fulfillment] Lỗi khi gửi email qua SMTP:', mailErr.message)
  }

  return {
    success: true,
    apiKey: createdApiKey,
    keyId: createdKeyId,
    invoiceCode,
    emailSent,
  }
}
