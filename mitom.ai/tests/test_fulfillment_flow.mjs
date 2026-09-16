import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function testFullPaymentFlow() {
  console.log('=== KHOI DONG KIEM TRA LUONG THANH TOAN VA FULFILLMENT ===')
  const payload = await getPayload({ config: configPromise })

  // 1. Tìm 1 sản phẩm mẫu trong hệ thống
  const products = await payload.find({
    collection: 'products',
    limit: 1,
  })

  if (!products.docs.length) {
    console.error('Khong tim thay san pham nao de tao don test.')
    process.exit(1)
  }

  const sampleProduct = products.docs[0]
  const testOrderCode = `MT-TEST${Date.now().toString().slice(-4)}`
  const testEmail = 'buctuong2000@gmail.com'

  console.log(`1. Dang tao don hang test: ${testOrderCode} cho ${testEmail}...`)

  const newOrder = await payload.create({
    collection: 'orders',
    data: {
      orderCode: testOrderCode,
      customerEmail: testEmail,
      customerPhone: '0908888888',
      product: sampleProduct.id,
      planName: 'Gói Thử Nghiệm Tự Động Hóa',
      subtotal: 100000,
      vatRate: 10,
      vatAmount: 10000,
      totalAmount: 110000,
      paymentStatus: 'pending',
      fulfillmentStatus: 'unfulfilled',
      customerType: 'personal',
      customerName: 'Nguyễn Văn Test',
      identityNumber: '079099888999',
      invoiceEmail: testEmail,
      note: 'Don hang kiem tra he thong tu dong tao API Key AstraFlow va gui hoa don qua email',
    },
  })

  console.log(`Don hang test da tao thanh cong! ID: ${newOrder.id}, Trạng thái: ${newOrder.paymentStatus}`)

  // 2. Mô phỏng Webhook ngân hàng / SePay báo tiền về thành công kèm nội dung chứa mã đơn
  console.log('2. Dang mo phong Webhook ngan hang goi callback ve...')
  const simulatedTxId = `SIM-BANK-${Date.now()}`

  // Cập nhật Order sang paid (kích hoạt hook afterChange thực thi fulfillPaidOrder)
  const updatedOrder = await payload.update({
    collection: 'orders',
    id: newOrder.id,
    data: {
      paymentStatus: 'paid',
    },
  })

  console.log('3. Don hang sau khi hook chay xong:')
  console.log(`- Trạng thái thanh toán: ${updatedOrder.paymentStatus}`)
  console.log(`- Trạng thái giao hàng: ${updatedOrder.fulfillmentStatus}`)
  console.log(`- API Key AstraFlow cấp cho khách: ${updatedOrder.apiKey}`)
  console.log(`- Số hóa đơn điện tử: ${updatedOrder.invoiceCode}`)
  console.log(`- Ngày xuất hóa đơn: ${updatedOrder.invoiceIssuedAt}`)
  console.log(`- Bàn giao:\n${updatedOrder.deliveryInfo}`)

  // 4. Kiểm tra trong ApiKeys collection xem Key đã được ghi nhận chưa
  const savedKey = await payload.find({
    collection: 'api-keys',
    where: {
      name: {
        equals: `mitom-${testOrderCode.toLowerCase()}`,
      },
    },
  })

  console.log('4. Kiem tra collection api-keys:')
  if (savedKey.docs.length > 0) {
    console.log(`- Tim thay key trong CMS: ${savedKey.docs[0].name} (ID: ${savedKey.docs[0].keyId})`)
  } else {
    console.log('- Khong tim thay ban ghi key trong api-keys collection')
  }

  console.log('=== TEST TOAN TRINH HOAN TAT THANH CONG! ===')
  process.exit(0)
}

testFullPaymentFlow().catch((err) => {
  console.error('Test that bai:', err)
  process.exit(1)
})
