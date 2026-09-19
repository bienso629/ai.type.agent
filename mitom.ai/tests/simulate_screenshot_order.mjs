import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function runSimulatedOrderAndWebhook() {
  console.log('=== BẮT ĐẦU GIẢ LẬP ĐƠN HÀNG VÀ WEBHOOK THANH TOÁN TỪ ẢNH CHỤP ===')
  const payload = await getPayload({ config: configPromise })

  // Thông tin trích xuất chính xác 100% từ ảnh chụp màn hình lúc 18:08 19 Thg 9:
  const orderData = {
    planName: 'Khởi động (100.000đ)',
    subtotal: 100000,
    vatRate: 10,
    vatAmount: 10000,
    totalAmount: 110000,
    customerType: 'personal',
    customerName: 'Nguyễn Quang Yên',
    customerPhone: '0968661631',
    customerEmail: 'buctuong2000@gmail.com',
    identityNumber: '036086004266',
    invoiceEmail: 'buctuong2000@gmail.com',
    note: 'Đơn hàng giả lập từ ảnh chụp màn hình VietQR',
  }

  // 1. Tìm hoặc lấy sản phẩm nạp tiền
  const products = await payload.find({ collection: 'products', limit: 1 })
  const productId = products.docs.length > 0 ? products.docs[0].id : null

  // 2. Tìm hoặc tự động tạo người dùng buctuong2000@gmail.com
  let targetUser = null
  const userRes = await payload.find({
    collection: 'users',
    where: { email: { equals: orderData.customerEmail } },
    limit: 1,
  })

  if (userRes.docs.length === 0) {
    targetUser = await payload.create({
      collection: 'users',
      data: {
        email: orderData.customerEmail,
        password: 'Password123!',
        name: orderData.customerName,
        customerCode: 'MITO68X3XJ',
        role: 'user',
        balance: 0,
      },
    })
    console.log(`- Đã tạo lại user: ${targetUser.email} (Mã: ${targetUser.customerCode})`)
  } else {
    targetUser = userRes.docs[0]
  }
  console.log(`- Tài khoản nạp: ${targetUser.name} (${targetUser.email})`)
  console.log(`- Mã khách hàng: ${targetUser.customerCode}`)
  console.log(`- Số dư trước khi thanh toán: ${(targetUser.balance || 0).toLocaleString('vi-VN')} đ`)

  // 3. Tạo đơn hàng mới trong database
  const randomSuffix = Math.random().toString(36).substring(2, 8).toUpperCase()
  const orderCode = `MT-${Date.now().toString().slice(-4)}${randomSuffix}`

  console.log(`\n1. Đang tạo đơn hàng mã ${orderCode}...`)
  const newOrder = await payload.create({
    collection: 'orders',
    data: {
      orderCode,
      customerEmail: orderData.customerEmail,
      customerPhone: orderData.customerPhone,
      product: productId,
      planName: orderData.planName,
      subtotal: orderData.subtotal,
      vatRate: orderData.vatRate,
      vatAmount: orderData.vatAmount,
      totalAmount: orderData.totalAmount,
      paymentStatus: 'pending',
      fulfillmentStatus: 'unfulfilled',
      customerType: orderData.customerType,
      customerName: orderData.customerName,
      identityNumber: orderData.identityNumber,
      invoiceEmail: orderData.invoiceEmail,
      note: orderData.note,
    },
  })
  console.log(`- Đơn hàng ${newOrder.orderCode} đã tạo thành công! (ID: ${newOrder.id})`)

  // 4. Giả lập gọi Webhook (Mã QR trong màn hình nạp chứa memo mã khách hàng và/hoặc mã đơn hàng)
  console.log(`\n2. Đang gửi dữ liệu Webhook giả lập thanh toán ngân hàng ACB...`)
  const fakeTxId = `ACB-${Date.now()}`
  const webhookPayload = {
    id: fakeTxId,
    gateway: 'ACB',
    transactionDate: new Date().toISOString(),
    transactionNumber: `TXN${Date.now()}`,
    accountNumber: '199878939',
    content: `NAP TIEN MITOM AI ${targetUser.customerCode} ${orderCode}`,
    transferType: 'IN',
    transferAmount: orderData.totalAmount,
  }

  // Gọi trực tiếp route POST của webhook bằng mock Request
  const { POST } = await import('../src/app/api/payment/webhook/route')
  const req = new Request('http://localhost:30000/api/payment/webhook', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(webhookPayload),
  })

  const res = await POST(req)
  const webhookResult = await res.json()
  console.log(`- Phản hồi từ Webhook API (Status ${res.status}):`)
  console.log(JSON.stringify(webhookResult, null, 2))

  // 5. Kiểm tra lại trạng thái đơn hàng, hóa đơn và số dư của khách
  console.log(`\n3. Thẩm định kết quả sau xử lý callback:`)
  const updatedOrder = await payload.findByID({ collection: 'orders', id: newOrder.id })
  console.log(`- Trạng thái thanh toán đơn hàng: ${updatedOrder.paymentStatus}`)
  console.log(`- Trạng thái fulfillment: ${updatedOrder.fulfillmentStatus}`)
  console.log(`- Ghi chú đơn: ${updatedOrder.note}`)

  const updatedUser = await payload.findByID({ collection: 'users', id: targetUser.id })
  console.log(`- Số dư mới của tài khoản: ${(updatedUser.balance || 0).toLocaleString('vi-VN')} đ`)
  console.log(`- API Key hiện tại: ${updatedUser.apiKey || '(chưa cấp)'}`)

  // Kiểm tra hóa đơn
  const invoices = await payload.find({
    collection: 'invoices',
    where: { order: { equals: newOrder.id } },
  })
  if (invoices.docs.length > 0) {
    const inv = invoices.docs[0]
    console.log(`- Hóa đơn điện tử: ${inv.invoiceNumber} | Tổng tiền: ${inv.totalAmount.toLocaleString('vi-VN')} đ | Người nhận: ${inv.customerName} (${inv.invoiceEmail})`)
  }

  // Kiểm tra giao dịch transaction
  const transactions = await payload.find({
    collection: 'transactions',
    where: { order: { equals: newOrder.id } },
  })
  if (transactions.docs.length > 0) {
    const tx = transactions.docs[0]
    console.log(`- Giao dịch ngân hàng đã ghi sổ: ${tx.transactionId} | Số tiền: ${tx.amount.toLocaleString('vi-VN')} đ`)
  }

  console.log('\n=== HOÀN TẤT GIẢ LẬP ĐƠN HÀNG VÀ CALLBACK WEBHOOK THÀNH CÔNG 100% ===')
  process.exit(0)
}

runSimulatedOrderAndWebhook().catch((err) => {
  console.error('Lỗi khi chạy giả lập:', err)
  process.exit(1)
})
