import { sqliteAdapter } from '@payloadcms/db-sqlite'
import { lexicalEditor } from '@payloadcms/richtext-lexical'
import { nodemailerAdapter } from '@payloadcms/email-nodemailer'
import path from 'path'
import { buildConfig } from 'payload'
import { fileURLToPath } from 'url'
import sharp from 'sharp'

import { Users } from './collections/Users'
import { Media } from './collections/Media'
import { Categories } from './collections/Categories'
import { Products } from './collections/Products'
import { Orders } from './collections/Orders'
import { Transactions } from './collections/Transactions'
import { ApiKeys } from './collections/ApiKeys'
import { SystemSettings } from './globals/SystemSettings'

import nodemailer from 'nodemailer'

const filename = fileURLToPath(import.meta.url)
const dirname = path.dirname(filename)

export default buildConfig({
  routes: {
    admin: '/101',
  },
  admin: {
    user: Users.slug,
    importMap: {
      baseDir: path.resolve(dirname),
    },
    components: {
      graphics: {
        Logo: '/components/Logo#Logo',
        Icon: '/components/Logo#Icon',
      },
    },
  },
  collections: [Users, Media, Categories, Products, Orders, Transactions, ApiKeys],
  globals: [SystemSettings],
  editor: lexicalEditor(),
  secret: process.env.PAYLOAD_SECRET || '',
  typescript: {
    outputFile: path.resolve(dirname, 'payload-types.ts'),
  },
  db: sqliteAdapter({
    client: {
      url: process.env.DATABASE_URL || '',
    },
  }),
  sharp,
  email: nodemailerAdapter({
    defaultFromAddress: process.env.SMTP_FROM_ADDRESS || 'support@mitom.ai',
    defaultFromName: process.env.SMTP_FROM_NAME || 'Mì Tôm AI Support',
    transport: nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.hopthu.vn',
      port: Number(process.env.SMTP_PORT) || 587,
      secure: false, // Port 587 uses STARTTLS
      auth: {
        user: process.env.SMTP_USER || 'support@mitom.ai',
        pass: process.env.SMTP_PASS || 'l@w£3P51ATT2',
      },
      tls: {
        rejectUnauthorized: false,
      },
    }),
  }),
  plugins: [],
})
