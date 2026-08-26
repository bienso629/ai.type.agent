import path from 'node:path'
import dotenv from 'dotenv'

dotenv.config()

export const CONFIG = {
  PORT: parseInt(process.env.BACKEND_PORT || '5001', 10),
  JWT_SECRET: process.env.JWT_SECRET || 'mitom_super_secret_jwt_key_2026_!@#$',
  JWT_EXPIRES_IN: '7d',
  DB_PATH: process.env.DB_PATH || path.resolve(process.cwd(), 'database.sqlite'),
  BANK_INFO: {
    BANK_ID: process.env.BANK_ID || 'MB', // MBBank, VCB, ACB, TPB, ICB
    ACCOUNT_NO: process.env.BANK_ACCOUNT_NO || '0908888888',
    ACCOUNT_NAME: process.env.BANK_ACCOUNT_NAME || 'NGUYEN VAN A',
    TEMPLATE: 'compact2',
  },
  ADMIN_EMAIL: process.env.ADMIN_EMAIL || 'admin@mitom.ai',
}
