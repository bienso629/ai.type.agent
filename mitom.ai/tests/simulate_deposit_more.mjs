import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function runDepositSimulation() {
  console.log('=== GIẢ LẬP GIAO DỊCH NẠP THÊM TIỀN TÀI KHOẢN QUA WEBHOOK ===')
  const payload = await getPayload({ config: configPromise })

  const email = 'buctuong2000@gmail.com'
  const customerCode = 'MITO68X3XJ'
  const depositPackageSubtotal = 200000 // Gói nạp 200.000đ
  const vatRate = 10
  const vatAmount = Math.round(depositPackageSubtotal * vatRate / 100) // 20.000đ
  const totalAmount = depositPackageSubtotal + vatAmount // 220.000đ

  // 1. Kiểm tra thông tin tài khoản hiện tại
  const userRes = await payload.find({
    collection: 'users',
    where: { email: { equals: email } },
    limit: 1,
  })

  if (userRes.docs.length === 0) {
    console.error(`Không tìm thấy user ${email}!`)
    process.exit(1)
  }

  const user = userRes.docs[0]
  const initialBalance = Number(user.balance) || 0
  console.log(`- Tài khoản: ${user.name || user.email} (${user.email})`)
  console.log(`- Mã khách hàng: ${user.customerCode}`)
  console.log(`- Số dư trước khi nạp: ${initialBalance.toLocaleString('vi-VN')} đ`)
  console.log(`- Gói nạp thêm: ${depositPackageSubtotal.toLocaleString('vi-VN')} đ (+ VAT 10%: ${vatAmount.toLocaleString('vi-VN')} đ = Tổng thanh toán ${totalAmount.toLocaleString('vi-VN')} đ)`)

  // 2. Giả lập callback ngân hàng nạp tiền trực tiếp theo mã khách hàng (Nhánh nạp tiền tài khoản MITO...)
  const fakeTxId = `ACB-DEP-${Date.now()}`
  const webhookPayload = {
    id: fakeTxId,
    gateway: 'ACB',
    transactionDate: new Date().toISOString(),
    transactionNumber: `TXN${Date.now()}`,
    accountNumber: '199878939',
    content: `NAP TIEN MITOM AI ${customerCode}`,
    transferType: 'IN',
    transferAmount: totalAmount,
  }

  console.log(`\n1. Gửi callback Webhook ngân hàng ACB vào backend...`)
  console.log(`- Nội dung chuyển khoản: "${webhookPayload.content}"`)
  console.log(`- Số tiền thực chuyển: ${webhookPayload.transferAmount.toLocaleString('vi-VN')} đ`)

  const { POST } = await import('../src/app/api/payment/webhook/route')
  const req = new Request('http://localhost:30000/api/payment/webhook', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(webhookPayload),
  })

  const res = await POST(req)
  const webhookResult = await res.json()
  console.log(`\n2. Phản hồi từ Webhook API (Status ${res.status}):`)
  console.log(JSON.stringify(webhookResult, null, 2))

  // 3. Kiểm tra số dư tài khoản sau khi nạp
  const updatedUser = await payload.findByID({ collection: 'users', id: user.id })
  const newBalance = Number(updatedUser.balance) || 0
  const creditedAmount = newBalance - initialBalance

  console.log(`\n3. Kết quả xác thực backend sau callback:`)
  console.log(`- Số dư trước nạp: ${initialBalance.toLocaleString('vi-VN')} đ`)
  console.log(`- Số dư thực tế được cộng: ${creditedAmount.toLocaleString('vi-VN')} đ`)
  console.log(`- Số dư tài khoản mới: ${newBalance.toLocaleString('vi-VN')} đ`)
  console.log(`- API Key hiện tại: ${updatedUser.apiKey || '(chưa cấp)'}`)

  // Kiểm tra đơn nạp tiền tự sinh
  const orders = await payload.find({
    collection: 'orders',
    where: { customerEmail: { equals: email } },
    sort: '-createdAt',
    limit: 1,
  })
  if (orders.docs.length > 0) {
    const o = orders.docs[0]
    console.log(`- Đơn nạp tiền ghi nhận: ${o.orderCode} | Gói: ${o.planName} | Subtotal: ${Number(o.subtotal).toLocaleString('vi-VN')} đ | VAT: ${Number(o.vatAmount).toLocaleString('vi-VN')} đ | Tổng: ${Number(o.totalAmount).toLocaleString('vi-VN')} đ`)
  }

  // Kiểm tra hóa đơn điện tử tự sinh
  const invoices = await payload.find({
    collection: 'invoices',
    where: { invoiceEmail: { equals: email } },
    sort: '-createdAt',
    limit: 1,
  })
  if (invoices.docs.length > 0) {
    const inv = invoices.docs[0]
    console.log(`- Hóa đơn điện tử xuất ra: ${inv.invoiceNumber} | Tổng tiền: ${Number(inv.totalAmount).toLocaleString('vi-VN')} đ | Trạng thái: ${inv.status}`)
  }

  console.log('\n=== HOÀN TẤT GIẢ LẬP CALLBACK NẠP THÊM TIỀN ===')
  process.exit(0)
}

runDepositSimulation().catch((err) => {
  console.error('Lỗi giả lập:', err)
  process.exit(1)
})
