import nodemailer from 'nodemailer'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function sendTestEmail() {
  const host = process.env.SMTP_HOST || 'smtp.hopthu.vn'
  const port = Number(process.env.SMTP_PORT) || 587
  const user = process.env.SMTP_USER || 'support@mitom.ai'
  const pass = process.env.SMTP_PASS || ''
  const recipient = 'buctuong2000@gmail.com'

  console.log('--- Bat dau kiem tra ket noi va gui mail test ---')
  console.log(`Server: ${host}:${port}`)
  console.log(`From: ${user}`)
  console.log(`Pass length: ${pass.length}`)
  console.log(`To: ${recipient}`)

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: {
      user,
      pass,
    },
    tls: {
      rejectUnauthorized: false,
    },
  })

  try {
    console.log('Dang xac thuc SMTP server...')
    await transporter.verify()
    console.log('Ket noi va xac thuc SMTP thanh cong!')

    console.log(`Dang gui email test toi ${recipient}...`)
    const info = await transporter.sendMail({
      from: `"Mì Tôm AI Support" <${user}>`,
      to: recipient,
      subject: 'Thư thử nghiệm từ hệ thống Mì Tôm AI (SMTP Test)',
      text: 'Chào bạn,\n\nĐây là email kiểm tra tính năng gửi thư qua giao thức SMTP (smtp.hopthu.vn) từ hệ thống Mì Tôm AI.\nNếu bạn nhận được email này, việc cấu hình SMTP đã thành công mỹ mãn!\n\nTrân trọng,\nĐội ngũ Kỹ thuật Mì Tôm AI',
      html: `
        <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 8px; overflow: hidden;">
          <div style="background-color: #f97316; color: white; padding: 20px; text-align: center;">
            <h1 style="margin: 0; font-size: 24px;">Mì Tôm AI - Email Test</h1>
          </div>
          <div style="padding: 24px;">
            <p>Chào bạn,</p>
            <p>Đây là email kiểm tra hệ thống gửi thư tự động qua giao thức SMTP từ <strong>Mì Tôm AI</strong>.</p>
            <div style="background: #f4f4f5; padding: 15px; border-radius: 6px; margin: 20px 0;">
              <p style="margin: 4px 0;"><strong>Hệ thống gửi:</strong> ${user}</p>
              <p style="margin: 4px 0;"><strong>Cổng SMTP:</strong> ${host}:${port} (STARTTLS)</p>
              <p style="margin: 4px 0;"><strong>Trạng thái:</strong> Hoạt động ổn định</p>
            </div>
            <p>Nếu bạn nhận được email này, cấu hình gửi thư trong Payload CMS Admin đã sẵn sàng cho tính năng gửi OTP, xác thực tài khoản và hóa đơn.</p>
            <p style="margin-top: 30px; font-size: 13px; color: #71717a;">Trân trọng,<br>Đội ngũ kỹ thuật Mì Tôm AI</p>
          </div>
        </div>
      `,
    })

    console.log('Email da gui thanh cong!')
    console.log('Message ID:', info.messageId)
    console.log('Phan hoi tu server:', info.response)
  } catch (error) {
    console.error('Loi khi gui email:', error)
    process.exit(1)
  }
}

sendTestEmail()
