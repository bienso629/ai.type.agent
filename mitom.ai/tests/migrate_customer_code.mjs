import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import { generateCustomerCode } from '../src/lib/customerCode'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function updateExistingUsersCustomerCode() {
  console.log('=== CHUYEN DOI MA KHACH HANG SANG MA NGAU NHIEN BAO MAT ===')
  const payload = await getPayload({ config: configPromise })

  const users = await payload.find({
    collection: 'users',
    limit: 1000,
  })

  console.log(`Tim thay ${users.totalDocs} nguoi dung trong he thong:`)
  for (const u of users.docs) {
    const oldCode = u.customerCode
    // Nếu mã cũ đang dùng dạng MITO + 6 số (pad ID) hoặc chưa có mã
    if (!oldCode || /^MITO\d{6}$/i.test(oldCode)) {
      const newCode = generateCustomerCode()
      await payload.update({
        collection: 'users',
        id: u.id,
        data: {
          customerCode: newCode,
        },
      })
      console.log(`- User ID ${u.id} (${u.email}): ${oldCode || 'Chua co'} -> ${newCode}`)
    } else {
      console.log(`- User ID ${u.id} (${u.email}): Giu nguyen ma hien tai (${oldCode})`)
    }
  }

  console.log('=== CHUYEN DOI HOAN TAT! ===')
  process.exit(0)
}

updateExistingUsersCustomerCode().catch((e) => {
  console.error(e)
  process.exit(1)
})
