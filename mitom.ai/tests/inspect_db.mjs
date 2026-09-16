import { getPayload } from 'payload'
import configPromise from '../src/payload.config'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

dotenv.config({ path: path.resolve(__dirname, '../.env') })

async function inspectDb() {
  const payload = await getPayload({ config: configPromise })
  const users = await payload.find({ collection: 'users', limit: 100 })
  const categories = await payload.find({ collection: 'categories', limit: 100 })
  const products = await payload.find({ collection: 'products', limit: 100 })
  const orders = await payload.find({ collection: 'orders', limit: 100 })
  const transactions = await payload.find({ collection: 'transactions', limit: 100 })
  const apiKeys = await payload.find({ collection: 'api-keys', limit: 100 })

  console.log(JSON.stringify({
    users: users.docs.map(u => ({ id: u.id, email: u.email, role: u.role, name: u.name })),
    categories: categories.docs.map(c => ({ id: c.id, name: c.name, slug: c.slug })),
    productsCount: products.totalDocs,
    ordersCount: orders.totalDocs,
    transactionsCount: transactions.totalDocs,
    apiKeysCount: apiKeys.totalDocs,
  }, null, 2))
  process.exit(0)
}

inspectDb().catch((e) => {
  console.error(e)
  process.exit(1)
})
