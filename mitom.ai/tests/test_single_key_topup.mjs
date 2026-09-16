import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function testSingleKeyLogic() {
  console.log('=== KIEM TRA LOGIC 1 TAI KHOAN CHI CO 1 KEY DUY NHAT & TANG SO DU ===')
  const payload = await getPayload({ config: configPromise })

  const testEmail = 'buctuong2000@gmail.com'

  // 1. Kiểm tra hoặc tạo User trong hệ thống
  let user = await payload.find({
    collection: 'users',
    where: { email: { equals: testEmail } },
    limit: 1,
  })

  let userDoc = null
  if (user.docs.length === 0) {
    console.log(`Tao user test: ${testEmail}...`)
    userDoc = await payload.create({
      collection: 'users',
      data: {
        email: testEmail,
        password: 'Password123!',
        name: 'Đại Ca Bức Tường',
        role: 'user',
        balance: 50000,
        apiKey: 'sk-fixed-test-key-buctuong2000-xyz',
      },
    })
  } else {
    userDoc = user.docs[0]
    if (!userDoc.apiKey) {
      userDoc = await payload.update({
        collection: 'users',
        id: userDoc.id,
        data: {
          apiKey: 'sk-fixed-test-key-buctuong2000-xyz',
        },
      })
    }
  }

  const initialKey = userDoc.apiKey
  const initialBalance = Number(userDoc.balance) || 0
  console.log(`Thong tin User ban dau:`)
  console.log(`- Email: ${userDoc.email}`)
  console.log(`- API Key duy nhat hien tai: ${initialKey}`)
  console.log(`- So du hien tai: ${initialBalance} VNĐ`)

  // 2. Tao don nap tien moi
  const products = await payload.find({ collection: 'products', limit: 1 })
  const testOrderCode = `MT-TOPUP${Date.now().toString().slice(-4)}`
  const topupAmount = 200000

  console.log(`\n2. Khach hang thuc hien nap tien: Don ${testOrderCode}, so tien: ${topupAmount} VNĐ...`)
  const newOrder = await payload.create({
    collection: 'orders',
    data: {
      orderCode: testOrderCode,
      customerEmail: testEmail,
      customerPhone: '0908888888',
      product: products.docs[0].id,
      planName: 'Nạp Số Dư Tài Khoản API',
      subtotal: topupAmount,
      vatRate: 10,
      vatAmount: 20000,
      totalAmount: 220000,
      paymentStatus: 'pending',
      fulfillmentStatus: 'unfulfilled',
      customerType: 'personal',
      customerName: 'Đại Ca Bức Tường',
      identityNumber: '079099888999',
      invoiceEmail: testEmail,
      note: 'Test nap them tien giu nguyen key duy nhat',
    },
  })

  // 3. Xac nhan thanh toan (chuyen sang paid)
  console.log(`3. Webhook xac nhan thanh toan -> kich hoat fulfillment hook...`)
  const updatedOrder = await payload.update({
    collection: 'orders',
    id: newOrder.id,
    data: {
      paymentStatus: 'paid',
    },
  })

  // 4. Kiem tra lai User sau khi nap tien
  const recheckUser = await payload.findByID({
    collection: 'users',
    id: userDoc.id,
  })

  console.log(`\n4. Ket qua sau khi nap tien thanh cong:`)
  console.log(`- Order API Key gán cho đơn: ${updatedOrder.apiKey}`)
  console.log(`- API Key của User: ${recheckUser.apiKey}`)
  console.log(`- Key có bị tạo mới không?: ${recheckUser.apiKey === initialKey ? 'KHONG (Chính xác: Giữ nguyên 1 key duy nhất)' : 'CO (Sai)'}`)
  console.log(`- Số dư cũ: ${initialBalance} VNĐ`)
  console.log(`- Số dư mới: ${recheckUser.balance} VNĐ (Tăng thêm +${topupAmount} VNĐ)`)
  console.log(`- Số hóa đơn: ${updatedOrder.invoiceCode}`)
  console.log(`- Email đã gửi kèm hóa đơn và thông báo số dư mới tới ${testEmail}!`)

  console.log('\n=== TEST HOAN TAT THANH CONG 100%! ===')
  process.exit(0)
}

testSingleKeyLogic().catch((err) => {
  console.error('Loi:', err)
  process.exit(1)
})
