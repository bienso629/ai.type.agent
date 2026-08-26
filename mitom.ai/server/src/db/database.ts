import Database from 'better-sqlite3'
import bcrypt from 'bcryptjs'
import { CONFIG } from '../config/env'

export const db = new Database(CONFIG.DB_PATH)

// Bật chế độ WAL để tăng tốc độ ghi và đọc đồng thời
db.pragma('journal_mode = WAL')
db.pragma('foreign_keys = ON')

export function initDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user',
      balance INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS products (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      provider TEXT NOT NULL,
      tag TEXT NOT NULL,
      badge TEXT,
      desc TEXT NOT NULL,
      cost_price INTEGER NOT NULL DEFAULT 0,
      price INTEGER NOT NULL,
      features TEXT NOT NULL,
      accent TEXT NOT NULL,
      initials TEXT NOT NULL,
      eta TEXT NOT NULL,
      stock INTEGER NOT NULL DEFAULT 99,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      user_email TEXT NOT NULL,
      product_id TEXT NOT NULL,
      product_name TEXT NOT NULL,
      cost_price INTEGER NOT NULL DEFAULT 0,
      amount INTEGER NOT NULL,
      profit INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      payment_method TEXT NOT NULL,
      delivery_content TEXT,
      qr_code_url TEXT,
      payment_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS inventory_keys (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      key_data TEXT NOT NULL,
      is_used INTEGER NOT NULL DEFAULT 0,
      order_id TEXT,
      created_at TEXT NOT NULL,
      used_at TEXT,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      balance_before INTEGER NOT NULL,
      balance_after INTEGER NOT NULL,
      description TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'success',
      payment_method TEXT,
      reference_code TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  `)

  // Auto-migration columns if existing DB
  try {
    db.exec('ALTER TABLE products ADD COLUMN cost_price INTEGER NOT NULL DEFAULT 0')
  } catch {}
  try {
    db.exec('ALTER TABLE orders ADD COLUMN cost_price INTEGER NOT NULL DEFAULT 0')
  } catch {}
  try {
    db.exec('ALTER TABLE orders ADD COLUMN profit INTEGER NOT NULL DEFAULT 0')
  } catch {}

  seedInitialData()
}

function seedInitialData() {
  // 1. Seed Admin User
  const adminExists = db.prepare('SELECT id FROM users WHERE email = ?').get(CONFIG.ADMIN_EMAIL)
  if (!adminExists) {
    const salt = bcrypt.genSaltSync(10)
    const hash = bcrypt.hashSync('admin123456', salt)
    const now = new Date().toISOString()
    db.prepare(`
      INSERT INTO users (id, email, password_hash, name, role, balance, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run('usr_admin', CONFIG.ADMIN_EMAIL, hash, 'Quản Trị Viên (Admin)', 'admin', 5000000, now, now)
    console.log('✅ Đã khởi tạo tài khoản Admin mặc định: admin@mitom.ai / admin123456')
  }

  // 2. Seed Demo User
  const demoExists = db.prepare('SELECT id FROM users WHERE email = ?').get('demo@mitom.ai')
  if (!demoExists) {
    const salt = bcrypt.genSaltSync(10)
    const hash = bcrypt.hashSync('demo123456', salt)
    const now = new Date().toISOString()
    db.prepare(`
      INSERT INTO users (id, email, password_hash, name, role, balance, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run('usr_demo', 'demo@mitom.ai', hash, 'Khách Hàng Demo', 'user', 1000000, now, now)
    console.log('✅ Đã khởi tạo tài khoản Khách Demo: demo@mitom.ai / demo123456 (Số dư sẵn: 1.000.000đ)')
  }

  // 3. Seed / Update Products with Cost Price (Giá gốc)
  const initialProducts = [
    {
      id: 'gpt-plus',
      name: 'ChatGPT Plus',
      provider: 'OpenAI',
      tag: 'chat',
      badge: 'Bán chạy',
      desc: 'Tài khoản chính chủ, dùng GPT-4o, o3 và các mô hình mới nhất không giới hạn.',
      cost_price: 200000, // Giá vốn nhập sỉ
      price: 480000, // Giá bán cho khách (Lãi: 280.000đ)
      features: JSON.stringify(['Truy cập GPT-4o & o3', 'Bảo hành 1 đổi 1', 'Kích hoạt trong 5 phút']),
      accent: '#34d399',
      initials: 'AI',
      eta: 'Kích hoạt ~5 phút',
      stock: 50,
    },
    {
      id: 'claude-pro',
      name: 'Claude Pro',
      provider: 'Anthropic',
      tag: 'chat',
      badge: 'Khuyên dùng',
      desc: 'Cửa sổ ngữ cảnh 200K, Claude Opus & Sonnet cho viết lách và phân tích dài.',
      cost_price: 220000, // Giá vốn
      price: 490000, // Giá bán (Lãi: 270.000đ)
      features: JSON.stringify(['Context 200K token', 'Ưu tiên giờ cao điểm', 'Hỗ trợ tải file lớn']),
      accent: '#f5c451',
      initials: 'CL',
      eta: 'Kích hoạt ~5 phút',
      stock: 35,
    },
    {
      id: 'midjourney',
      name: 'Midjourney Basic',
      provider: 'Midjourney',
      tag: 'image',
      badge: 'Hot',
      desc: 'Gói Basic 200 ảnh/tháng, chất lượng v6.1, dùng qua Discord riêng.',
      cost_price: 100000, // Giá vốn
      price: 250000, // Giá bán (Lãi: 150.000đ)
      features: JSON.stringify(['200 lượt tạo ảnh', 'Chế độ Fast', 'Bản quyền thương mại']),
      accent: '#c084fc',
      initials: 'MJ',
      eta: 'Kích hoạt ~15 phút',
      stock: 20,
    },
    {
      id: 'gemini',
      name: 'Gemini Advanced',
      provider: 'Google',
      tag: 'chat',
      badge: 'Tiết kiệm',
      desc: 'Gemini 2.5 Pro kèm 2TB Google One, tích hợp Gmail, Docs và NotebookLM.',
      cost_price: 180000, // Giá vốn
      price: 420000, // Giá bán (Lãi: 240.000đ)
      features: JSON.stringify(['Gemini 2.5 Pro', 'Kèm 2TB lưu trữ', 'Deep Research']),
      accent: '#60a5fa',
      initials: 'GE',
      eta: 'Kích hoạt ~10 phút',
      stock: 40,
    },
    {
      id: 'cursor',
      name: 'Cursor Pro',
      provider: 'Anysphere',
      tag: 'code',
      badge: 'Cho Dev',
      desc: 'IDE lập trình AI với 500 request nhanh, autocomplete và agent viết code.',
      cost_price: 200000, // Giá vốn
      price: 480000, // Giá bán (Lãi: 280.000đ)
      features: JSON.stringify(['500 fast request', 'Agent Composer', 'Tab hoàn thiện code']),
      accent: '#e2e8f0',
      initials: 'CS',
      eta: 'Kích hoạt ~5 phút',
      stock: 30,
    },
    {
      id: 'token-5m',
      name: 'Gói API 5.000K Token',
      provider: 'Đa nền tảng',
      tag: 'token',
      badge: 'Tự động',
      desc: 'Credit API dùng chung cho OpenAI, Claude, Gemini qua cổng trung gian nội địa.',
      cost_price: 120000, // Giá vốn
      price: 350000, // Giá bán (Lãi: 230.000đ)
      features: JSON.stringify(['5 triệu token', 'Không hết hạn', 'Dashboard theo dõi']),
      accent: '#34d399',
      initials: 'TK',
      eta: 'Giao ngay lập tức',
      stock: 100,
    },
  ]

  const countProducts = (db.prepare('SELECT COUNT(*) as count FROM products').get() as { count: number }).count
  if (countProducts === 0) {
    const insertStmt = db.prepare(`
      INSERT INTO products (id, name, provider, tag, badge, desc, cost_price, price, features, accent, initials, eta, stock, is_active, created_at)
      VALUES (@id, @name, @provider, @tag, @badge, @desc, @cost_price, @price, @features, @accent, @initials, @eta, @stock, 1, datetime('now'))
    `)

    for (const p of initialProducts) {
      insertStmt.run(p)
    }
  } else {
    // Cập nhật giá gốc cho các sản phẩm đã có sẵn
    const updateCostStmt = db.prepare('UPDATE products SET cost_price = ? WHERE id = ? AND (cost_price = 0 OR cost_price IS NULL)')
    for (const p of initialProducts) {
      updateCostStmt.run(p.cost_price, p.id)
    }
  }

  // 4. Seed Inventory Keys
  const countKeys = (db.prepare('SELECT COUNT(*) as count FROM inventory_keys').get() as { count: number }).count
  if (countKeys === 0) {
    const insertKey = db.prepare(`
      INSERT INTO inventory_keys (id, product_id, key_data, is_used, created_at)
      VALUES (?, ?, ?, 0, datetime('now'))
    `)

    insertKey.run('key_1', 'token-5m', 'sk-mitom-token-5m-a98f12cb849102efbca87210')
    insertKey.run('key_2', 'token-5m', 'sk-mitom-token-5m-7bc19280ef1294801acbc991')
    insertKey.run('key_3', 'gpt-plus', 'Email: gpt_plus_vip1@mitom.ai | Pass: MitomAI@2026 | Exp: 30 ngày')
    insertKey.run('key_4', 'claude-pro', 'Email: claude_pro_pro1@mitom.ai | Pass: ClaudeSafe@2026 | Exp: 30 ngày')
    insertKey.run('key_5', 'cursor', 'Key: CURSOR-PRO-SUBSCRIPTION-MITOM-883912')
  }
}
