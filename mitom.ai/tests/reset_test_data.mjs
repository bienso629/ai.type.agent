import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function cleanTestData() {
  console.log('=== TIEN HANH RESET DU LIEU GIAO DICH / TEST ===')
  const payload = await getPayload({ config: configPromise })

  // 1. Xóa toàn bộ Orders
  const orders = await payload.find({ collection: 'orders', limit: 1000 })
  console.log(`Dang xoa ${orders.totalDocs} don hang...`)
  for (const doc of orders.docs) {
    await payload.delete({ collection: 'orders', id: doc.id })
  }

  // 2. Xóa toàn bộ Transactions
  const transactions = await payload.find({ collection: 'transactions', limit: 1000 })
  console.log(`Dang xoa ${transactions.totalDocs} giao dich...`)
  for (const doc of transactions.docs) {
    await payload.delete({ collection: 'transactions', id: doc.id })
  }

  // 3. Xóa toàn bộ Invoices
  const invoices = await payload.find({ collection: 'invoices', limit: 1000 })
  console.log(`Dang xoa ${invoices.totalDocs} hoa don...`)
  for (const doc of invoices.docs) {
    await payload.delete({ collection: 'invoices', id: doc.id })
  }

  // 4. Xóa các API Keys test
  const apiKeys = await payload.find({ collection: 'api-keys', limit: 1000 })
  console.log(`Dang kiem tra ${apiKeys.totalDocs} API Keys trong CMS...`)
  for (const doc of apiKeys.docs) {
    if (
      doc.name.startsWith('mitom-mt-') ||
      doc.name.startsWith('test-') ||
      doc.name.includes('buctuong2000')
    ) {
      console.log(`- Xoa key test: ${doc.name} (${doc.keyId})`)
      await payload.delete({ collection: 'api-keys', id: doc.id })
    }
  }

  // 5. Xóa user test buctuong2000@gmail.com
  const testUsers = await payload.find({
    collection: 'users',
    where: {
      email: {
        in: ['buctuong2000@gmail.com'],
      },
    },
    limit: 10,
  })
  for (const u of testUsers.docs) {
    console.log(`- Xoa user test: ${u.email} (ID: ${u.id})`)
    await payload.delete({ collection: 'users', id: u.id })
  }

  console.log('=== RESET DU LIEU TEST HOAN TAT! ===')
  process.exit(0)
}

cleanTestData().catch((err) => {
  console.error('Loi khi reset database:', err)
  process.exit(1)
})
