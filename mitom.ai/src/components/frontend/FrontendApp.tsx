'use client'

import React, { useState, type ReactNode } from 'react'
import Image from 'next/image'

export type Category = 'chat' | 'image' | 'code' | 'token'
export type Page = 'home' | 'topup' | 'success'

export interface Product {
  id: string
  name: string
  provider: string
  tag: Category
  badge?: string
  desc: string
  features: string[]
  accent: string
  initials: string
  eta: string
}

export interface TopUp {
  amount: number
  bonusPct: number
  label: string
  highlight: boolean
}

export const CATEGORIES: { id: Category | 'all'; label: string }[] = [
  { id: 'all', label: 'Tất cả' },
  { id: 'chat', label: 'Trợ lý Chat' },
  { id: 'image', label: 'Tạo ảnh' },
  { id: 'code', label: 'Lập trình' },
  { id: 'token', label: 'Gói Token' },
]

export const DEFAULT_PRODUCTS: Product[] = [
  {
    id: 'gpt-plus',
    name: 'ChatGPT Plus',
    provider: 'OpenAI',
    tag: 'chat',
    badge: 'Bán chạy',
    desc: 'Tài khoản chính chủ, dùng GPT-4o, o3 và các mô hình mới nhất không giới hạn.',
    features: ['Truy cập GPT-4o & o3', 'Bảo hành 1 đổi 1', 'Kích hoạt trong 5 phút'],
    accent: '#34d399',
    initials: 'AI',
    eta: 'Kích hoạt ~5 phút',
  },
  {
    id: 'claude-pro',
    name: 'Claude Pro',
    provider: 'Anthropic',
    tag: 'chat',
    desc: 'Cửa sổ ngữ cảnh 200K, Claude Opus & Sonnet cho viết lách và phân tích dài.',
    features: ['Context 200K token', 'Ưu tiên giờ cao điểm', 'Hỗ trợ tải file lớn'],
    accent: '#f5c451',
    initials: 'CL',
    eta: 'Kích hoạt ~5 phút',
  },
  {
    id: 'midjourney',
    name: 'Midjourney',
    provider: 'Midjourney',
    tag: 'image',
    badge: 'Hot',
    desc: 'Gói Basic 200 ảnh/tháng, chất lượng v6.1, dùng qua Discord riêng.',
    features: ['200 lượt tạo ảnh', 'Chế độ Fast', 'Bản quyền thương mại'],
    accent: '#c084fc',
    initials: 'MJ',
    eta: 'Kích hoạt ~15 phút',
  },
  {
    id: 'gemini',
    name: 'Gemini Advanced',
    provider: 'Google',
    tag: 'chat',
    desc: 'Gemini 2.5 Pro kèm 2TB Google One, tích hợp Gmail, Docs và NotebookLM.',
    features: ['Gemini 2.5 Pro', 'Kèm 2TB lưu trữ', 'Deep Research'],
    accent: '#60a5fa',
    initials: 'GE',
    eta: 'Kích hoạt ~10 phút',
  },
  {
    id: 'cursor',
    name: 'Cursor Pro',
    provider: 'Anysphere',
    tag: 'code',
    badge: 'Cho dev',
    desc: 'IDE lập trình AI với 500 request nhanh, autocomplete và agent viết code.',
    features: ['500 fast request', 'Agent Composer', 'Tab hoàn thiện code'],
    accent: '#e2e8f0',
    initials: 'CS',
    eta: 'Kích hoạt ~5 phút',
  },
  {
    id: 'token-5m',
    name: 'Gói API 5.000K Token',
    provider: 'Đa nền tảng',
    tag: 'token',
    desc: 'Credit API dùng chung cho OpenAI, Claude, Gemini qua cổng trung gian nội địa.',
    features: ['5 triệu token', 'Không hết hạn', 'Dashboard theo dõi'],
    accent: '#34d399',
    initials: 'TK',
    eta: 'Giao ngay lập tức',
  },
]

export const TOPUPS: TopUp[] = [
  { amount: 100000, bonusPct: 5, label: 'Khởi động', highlight: false },
  { amount: 200000, bonusPct: 5, label: 'Tiết kiệm', highlight: false },
  { amount: 500000, bonusPct: 10, label: 'Phổ biến', highlight: true },
  { amount: 1000000, bonusPct: 15, label: 'Đại lý', highlight: false },
]

export const PAY_METHODS = [
  { id: 'vietqr', label: 'VietQR / Chuyển khoản', note: 'Quét mã, tự động cộng số dư' },
  { id: 'momo', label: 'Ví Momo', note: 'Thanh toán nhanh qua app' },
  { id: 'zalopay', label: 'ZaloPay', note: 'Liên kết ngân hàng' },
]

export const FAQS = [
  {
    q: 'Số dư nạp vào có bị hết hạn không?',
    a: 'Không. Tiền bạn nạp được cộng vào số dư và dùng đến khi nào hết thì thôi, không có kỳ hạn. Mỗi lần kích hoạt tài khoản hay mua token sẽ trừ trực tiếp vào số dư này.',
  },
  {
    q: 'Mua công cụ AI thế nào?',
    a: 'Bạn chỉ cần nạp tiền vào số dư, sau đó nhắn Zalo cho shop công cụ muốn dùng. Shop kích hoạt và trừ đúng số tiền vào số dư của bạn — không cần đặt hàng từng món.',
  },
  {
    q: 'Thanh toán bằng cách nào?',
    a: 'Chúng tôi hỗ trợ chuyển khoản ngân hàng nội địa, Momo, ZaloPay và VietQR. Số dư được cộng tự động sau khi xác nhận thanh toán.',
  },
  {
    q: 'Chính sách bảo hành thế nào?',
    a: 'Bảo hành 1 đổi 1 trong suốt thời gian sử dụng. Nếu tài khoản gặp lỗi không do người dùng, chúng tôi đổi mới miễn phí trong 24 giờ.',
  },
]

export const ZALO = 'https://zalo.me/0908888888'
export const formatVnd = (n: number) => n.toLocaleString('vi-VN') + 'đ'

export function Logo({ onClick }: { onClick?: () => void }) {
  return (
    <a
      href="#"
      onClick={(e) => {
        if (onClick) {
          e.preventDefault()
          onClick()
        }
      }}
      className="flex items-center gap-2.5 group"
    >
      <span className="relative grid h-9 w-9 place-items-center rounded-xl bg-primary text-primary-foreground font-display font-black text-lg">
        M
        <span
          className="absolute -right-0.5 -top-0.5 h-2 w-2 rounded-full bg-emerald"
          style={{ animation: 'tokenpulse 2s ease-in-out infinite' }}
        />
      </span>
      <span className="font-display text-xl font-extrabold tracking-tight">
        Mì Tôm <span className="text-primary">AI</span>
      </span>
    </a>
  )
}

export function ProductCard({ p, onSelect }: { p: Product; onSelect?: () => void }) {
  return (
    <article className="group relative flex flex-col overflow-hidden rounded-xl border border-border bg-card p-5 transition-all duration-300 hover:border-primary/50 hover:-translate-y-1">
      <div
        className="pointer-events-none absolute -right-16 -top-16 h-40 w-40 rounded-xl opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-20"
        style={{ background: p.accent }}
      />
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <span
            className="grid h-11 w-11 place-items-center rounded-xl font-mono text-sm font-bold"
            style={{ background: `${p.accent}1a`, color: p.accent }}
          >
            {p.initials}
          </span>
          <div>
            <h3 className="font-display text-lg font-bold leading-none">{p.name}</h3>
            <span className="text-xs text-muted-foreground">{p.provider}</span>
          </div>
        </div>
        {p.badge && (
          <span className="rounded-sm bg-primary px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-primary-foreground">
            {p.badge}
          </span>
        )}
      </div>

      <p className="mt-4 text-sm leading-relaxed text-muted-foreground">{p.desc}</p>

      <ul className="mt-4 flex-1 space-y-2">
        {p.features.map((f) => (
          <li key={f} className="flex items-center gap-2 text-sm text-secondary-foreground">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="shrink-0 text-emerald">
              <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            {f}
          </li>
        ))}
      </ul>

      <div className="mt-5 flex items-center justify-between border-t border-border pt-4">
        <span className="inline-flex items-center gap-1.5 text-xs font-medium text-emerald">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald" style={{ animation: 'tokenpulse 2s ease-in-out infinite' }} /> Đang có sẵn
        </span>
        <span className="font-mono text-[11px] text-muted-foreground">{p.eta}</span>
      </div>

      <a
        href={ZALO}
        target="_blank"
        rel="noreferrer"
        className="glow-button-secondary mt-4 w-full rounded-sm bg-secondary py-2.5 text-center text-sm font-semibold text-secondary-foreground transition-all hover:bg-primary hover:text-primary-foreground focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
      >
        Nhắn Zalo để chọn
      </a>
    </article>
  )
}

export function QrMock({ amount }: { amount?: number }) {
  const bankId = 'MB'
  const accountNo = '0348731111'
  const accountName = 'MITOM AI'
  const memo = amount ? `NAP ${amount / 1000}K` : 'NAP TIEN MITOM AI'
  const qrUrl = amount
    ? `https://img.vietqr.io/image/${bankId}-${accountNo}-compact2.png?amount=${amount}&addInfo=${encodeURIComponent(memo)}&accountName=${encodeURIComponent(accountName)}`
    : null

  if (qrUrl) {
    return (
      <div className="h-28 w-28 shrink-0 overflow-hidden rounded-xl bg-white p-1 shadow-md">
        <img
          src={qrUrl}
          alt="Mã VietQR nạp tiền"
          className="h-full w-full object-contain"
        />
      </div>
    )
  }

  return (
    <div className="grid h-24 w-24 shrink-0 place-items-center rounded-xl bg-white p-2">
      <div className="grid h-full w-full grid-cols-5 grid-rows-5 gap-0.5">
        {Array.from({ length: 25 }).map((_, i) => (
          <span key={i} className="rounded-xs" style={{ background: (i * 7 + 3) % 3 ? '#0b0c0f' : 'transparent' }} />
        ))}
      </div>
    </div>
  )
}

export function TopUpPage({
  topup,
  onDone,
  onNavigate,
}: {
  topup: TopUp
  onDone: (orderInfo?: any) => void
  onNavigate: (p: Page) => void
}) {
  const [pay, setPay] = useState('vietqr')
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [errorMsg, setErrorMsg] = useState('')

  const bonus = Math.round((topup.amount * topup.bonusPct) / 100)
  const balance = topup.amount + bonus

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsSubmitting(true)
    setErrorMsg('')

    try {
      const res = await fetch('/api/orders/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          productId: `topup-${topup.amount}`,
          planName: `Gói Nạp ${formatVnd(topup.amount)} (+${topup.bonusPct}% tặng ${formatVnd(bonus)})`,
          totalAmount: topup.amount,
          customerEmail: email.trim(),
          customerPhone: phone.trim(),
          note: `Khách hàng: ${name} | Phương thức: ${pay}`,
        }),
      })

      const data = await res.json()
      if (res.ok && data.success) {
        onDone(data.order)
      } else {
        // Vẫn điều hướng tới màn hình hoàn tất
        onDone()
      }
    } catch {
      onDone()
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <section className="mx-auto max-w-4xl px-5 py-14 md:px-8">
      <button
        onClick={() => onNavigate('home')}
        className="mb-6 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-primary"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
          <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Chọn mức nạp khác
      </button>
      <h1 className="font-display text-3xl font-extrabold tracking-tight">Nạp {formatVnd(topup.amount)} vào số dư</h1>

      {errorMsg && (
        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-400">
          {errorMsg}
        </div>
      )}

      <form onSubmit={handleSubmit} className="mt-8 grid gap-6 lg:grid-cols-[1.6fr_1fr]">
        <div className="space-y-6">
          <fieldset className="rounded-xl border border-border bg-card p-6">
            <legend className="px-2 font-display text-lg font-bold">Thông tin tài khoản</legend>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-sm font-medium text-secondary-foreground">
                  Họ và tên <span className="text-primary">*</span>
                </span>
                <input
                  name="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Nguyễn Văn A"
                  required
                  className="w-full rounded-sm border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
              </label>

              <label className="block">
                <span className="mb-1.5 block text-sm font-medium text-secondary-foreground">
                  Số điện thoại / Zalo <span className="text-primary">*</span>
                </span>
                <input
                  name="phone"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="0908 123 456"
                  required
                  className="w-full rounded-sm border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
              </label>

              <div className="sm:col-span-2">
                <label className="block">
                  <span className="mb-1.5 block text-sm font-medium text-secondary-foreground">
                    Email nhận biên nhận & thông tin <span className="text-primary">*</span>
                  </span>
                  <input
                    name="email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="ban@email.com"
                    required
                    className="w-full rounded-sm border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </label>
              </div>
            </div>
          </fieldset>

          <fieldset className="rounded-xl border border-border bg-card p-6">
            <legend className="px-2 font-display text-lg font-bold">Phương thức nạp tiền</legend>
            <div className="space-y-3">
              {PAY_METHODS.map((m) => (
                <label
                  key={m.id}
                  className={`flex cursor-pointer items-center gap-3 rounded-xl border p-4 transition-colors ${
                    pay === m.id ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'
                  }`}
                >
                  <input
                    type="radio"
                    name="pay"
                    checked={pay === m.id}
                    onChange={() => setPay(m.id)}
                    className="sr-only"
                  />
                  <span
                    className={`grid h-5 w-5 place-items-center rounded-sm border-2 ${
                      pay === m.id ? 'border-primary' : 'border-border'
                    }`}
                  >
                    {pay === m.id && <span className="h-2.5 w-2.5 rounded-xs bg-primary" />}
                  </span>
                  <div className="flex-1">
                    <div className="text-sm font-semibold">{m.label}</div>
                    <div className="text-xs text-muted-foreground">{m.note}</div>
                  </div>
                </label>
              ))}
            </div>
            {pay === 'vietqr' && (
              <div className="mt-4 flex items-center gap-4 rounded-xl border border-dashed border-border bg-secondary/40 p-4">
                <QrMock amount={topup.amount} />
                <div className="text-sm">
                  <div className="font-semibold">Quét mã, số dư cộng tự động</div>
                  <p className="mt-1 font-mono text-xs text-muted-foreground">
                    Mì Tôm AI<br />
                    STK 0348731111 · MB Bank<br />
                    Nội dung: NAP {topup.amount / 1000}K
                  </p>
                </div>
              </div>
            )}
          </fieldset>
        </div>

        <aside className="h-fit rounded-xl border border-border bg-card p-6">
          <h2 className="font-display text-lg font-bold">Tóm tắt đơn nạp</h2>
          <dl className="mt-5 space-y-3 text-sm">
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Số tiền nạp</dt>
              <dd className="font-mono">{formatVnd(topup.amount)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Khuyến mãi (+{topup.bonusPct}%)</dt>
              <dd className="font-mono text-emerald">{bonus > 0 ? `+${formatVnd(bonus)}` : '—'}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Phí giao dịch</dt>
              <dd className="font-mono text-emerald">Miễn phí</dd>
            </div>
          </dl>
          <div className="mt-5 flex items-baseline justify-between border-t border-border pt-5">
            <span className="text-sm text-muted-foreground">Số dư nhận được</span>
            <span className="font-mono text-2xl font-bold text-primary">{formatVnd(balance)}</span>
          </div>
          <button
            type="submit"
            disabled={isSubmitting}
            className="glow-button mt-5 w-full rounded-sm bg-primary py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50"
          >
            {isSubmitting ? 'Đang khởi tạo...' : 'Xác nhận đã chuyển'}
          </button>
          <p className="mt-4 text-center text-xs text-muted-foreground">
            Số dư dùng dần cho mọi công cụ, không hết hạn.
          </p>
        </aside>
      </form>
    </section>
  )
}

export function SuccessPage({
  topup,
  orderInfo,
  onNavigate,
}: {
  topup: TopUp | null
  orderInfo?: any
  onNavigate: (p: Page) => void
}) {
  const ref = orderInfo?.orderCode || 'NAP-' + Math.floor(2000 + Math.random() * 8000)
  const balance = topup ? topup.amount + Math.round((topup.amount * topup.bonusPct) / 100) : 0

  return (
    <section className="mx-auto max-w-2xl px-5 py-20 md:px-8">
      <div className="rounded-xl border border-emerald/30 bg-card p-10 text-center md:p-14">
        <div
          className="mx-auto grid h-16 w-16 place-items-center rounded-xl bg-emerald/15"
          style={{ animation: 'tokenpulse 2.4s ease-in-out infinite' }}
        >
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" className="text-emerald">
            <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h1 className="mt-6 font-display text-3xl font-black tracking-tight">Nạp tiền thành công!</h1>
        <p className="mx-auto mt-3 max-w-md text-muted-foreground">
          Đơn nạp đã được ghi nhận. Giờ chỉ cần nhắn Zalo cho shop công cụ AI bạn muốn dùng — shop sẽ kích hoạt và trừ vào số dư.
        </p>
        <div className="mx-auto mt-8 max-w-xs space-y-3">
          <div className="flex items-center justify-between rounded-xl border border-border bg-secondary/40 px-5 py-4">
            <span className="text-sm text-muted-foreground">Số dư nhận được</span>
            <span className="font-mono text-lg font-bold text-primary">{formatVnd(balance)}</span>
          </div>
          <div className="flex items-center justify-between rounded-xl border border-border bg-secondary/40 px-5 py-4">
            <span className="text-sm text-muted-foreground">Mã giao dịch</span>
            <span className="font-mono font-bold">#{ref}</span>
          </div>
        </div>
        <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
          <a
            href={ZALO}
            target="_blank"
            rel="noreferrer"
            className="glow-button rounded-sm bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
          >
            Nhắn Zalo chọn công cụ
          </a>
          <button
            onClick={() => onNavigate('home')}
            className="glow-button-secondary rounded-sm border border-border px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60"
          >
            Về trang chủ
          </button>
        </div>
      </div>
    </section>
  )
}

export function OrderLookupModal({
  isOpen,
  onClose,
}: {
  isOpen: boolean
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [result, setResult] = useState<any[] | null>(null)
  const [errorMsg, setErrorMsg] = useState('')

  if (!isOpen) return null

  const handleLookup = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!query.trim()) return

    setIsLoading(true)
    setErrorMsg('')
    try {
      const res = await fetch(`/api/orders/lookup?q=${encodeURIComponent(query.trim())}`)
      const data = await res.json()
      if (res.ok && data.success) {
        setResult(data.orders || [])
        if (!data.orders || data.orders.length === 0) {
          setErrorMsg('Không tìm thấy đơn hàng nào với thông tin đã nhập.')
        }
      } else {
        setErrorMsg(data.error || 'Có lỗi xảy ra khi tra cứu.')
      }
    } catch {
      setErrorMsg('Không thể kết nối đến máy chủ.')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm" onClick={onClose}>
      <div
        className="relative w-full max-w-lg rounded-xl border border-border bg-card p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-border pb-4">
          <h3 className="font-display text-xl font-bold">Tra Cứu Đơn Hàng & Số Dư</h3>
          <button onClick={onClose} className="rounded-sm p-1.5 text-muted-foreground hover:bg-secondary hover:text-foreground">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
          </button>
        </div>

        <form onSubmit={handleLookup} className="mt-4 flex gap-2">
          <input
            type="text"
            placeholder="Nhập mã đơn hàng (MT-...) hoặc Email"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="flex-1 rounded-sm border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:outline-none"
            required
          />
          <button
            type="submit"
            disabled={isLoading}
            className="glow-button rounded-sm bg-primary px-4 py-2.5 text-sm font-bold text-primary-foreground hover:opacity-90 disabled:opacity-50"
          >
            {isLoading ? 'Đang tìm...' : 'Tra cứu'}
          </button>
        </form>

        {errorMsg && (
          <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-xs text-red-400">
            {errorMsg}
          </div>
        )}

        {result && result.length > 0 && (
          <div className="mt-4 max-h-60 space-y-3 overflow-y-auto pr-1">
            {result.map((o) => (
              <div key={o.id} className="rounded-xl border border-border bg-secondary/30 p-3 text-sm">
                <div className="flex items-center justify-between font-mono font-bold">
                  <span className="text-primary">#{o.orderCode}</span>
                  <span>{formatVnd(o.totalAmount)}</span>
                </div>
                <div className="mt-1 text-xs text-muted-foreground">{o.planName}</div>
                <div className="mt-2 flex items-center justify-between text-xs">
                  <span className={`rounded-sm px-2 py-0.5 font-medium ${o.paymentStatus === 'paid' ? 'bg-emerald/15 text-emerald' : 'bg-amber-500/15 text-amber-400'}`}>
                    {o.paymentStatus === 'paid' ? 'Đã thanh toán' : 'Chờ thanh toán'}
                  </span>
                  <span className="text-muted-foreground">{new Date(o.createdAt).toLocaleDateString('vi-VN')}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export function FrontendApp({
  products = DEFAULT_PRODUCTS,
  adminRoute = '/admin',
}: {
  products?: Product[]
  adminRoute?: string
}) {
  const [active, setActive] = useState<Category | 'all'>('all')
  const [page, setPage] = useState<Page>('home')
  const [topup, setTopup] = useState<TopUp | null>(null)
  const [orderInfo, setOrderInfo] = useState<any>(null)
  const [openFaq, setOpenFaq] = useState<number | null>(0)
  const [isLookupOpen, setIsLookupOpen] = useState(false)

  const navigate = (p: Page) => {
    setPage(p)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const startTopup = (t: TopUp) => {
    setTopup(t)
    navigate('topup')
  }

  const goPricing = () => {
    if (page !== 'home') {
      navigate('home')
      setTimeout(() => document.getElementById('pricing')?.scrollIntoView({ behavior: 'smooth' }), 60)
    } else {
      document.getElementById('pricing')?.scrollIntoView({ behavior: 'smooth' })
    }
  }

  const goProducts = () => {
    if (page !== 'home') {
      navigate('home')
      setTimeout(() => document.getElementById('products')?.scrollIntoView({ behavior: 'smooth' }), 60)
    } else {
      document.getElementById('products')?.scrollIntoView({ behavior: 'smooth' })
    }
  }

  const filtered = active === 'all' ? products : products.filter((p) => p.tag === active)

  let content: ReactNode
  if (page === 'topup' && topup) {
    content = (
      <TopUpPage
        topup={topup}
        onDone={(order) => {
          setOrderInfo(order)
          navigate('success')
        }}
        onNavigate={navigate}
      />
    )
  } else if (page === 'success') {
    content = <SuccessPage topup={topup} orderInfo={orderInfo} onNavigate={navigate} />
  } else {
    content = (
      <HomePage
        active={active}
        setActive={setActive}
        filtered={filtered}
        openFaq={openFaq}
        setOpenFaq={setOpenFaq}
        onTopup={startTopup}
        goPricing={goPricing}
        goProducts={goProducts}
      />
    )
  }

  return (
    <div className="min-h-screen w-full bg-background text-foreground font-sans">
      <header className="sticky top-0 z-50 border-b border-border bg-background/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 md:px-8">
          <Logo onClick={() => navigate('home')} />
          <nav className="hidden items-center gap-8 text-sm font-medium text-secondary-foreground lg:flex">
            <button onClick={() => navigate('home')} className="transition-colors hover:text-primary">
              Trang chủ
            </button>
            <button onClick={goProducts} className="transition-colors hover:text-primary">
              Công cụ AI
            </button>
            <button onClick={goPricing} className="transition-colors hover:text-primary">
              Nạp tiền
            </button>
            <button onClick={() => setIsLookupOpen(true)} className="transition-colors hover:text-primary">
              Tra cứu đơn
            </button>
            <a href={ZALO} target="_blank" rel="noreferrer" className="transition-colors hover:text-primary">
              Liên hệ Zalo
            </a>
            <a
              href={adminRoute}
              target="_blank"
              rel="noreferrer"
              className="rounded-sm border border-border px-3 py-1 text-xs text-muted-foreground hover:border-primary/50 hover:text-foreground"
            >
              Admin
            </a>
          </nav>
          <div className="flex items-center gap-3">
            <button
              onClick={() => setIsLookupOpen(true)}
              className="glow-button-secondary rounded-sm border border-border bg-secondary px-3 py-2 text-xs font-semibold text-secondary-foreground hover:border-primary/50 lg:hidden"
            >
              Tra cứu
            </button>
            <button
              onClick={goPricing}
              className="glow-button rounded-sm bg-primary px-4 py-2.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
            >
              Nạp tiền ngay
            </button>
          </div>
        </div>
      </header>

      {content}

      <footer className="border-t border-border">
        <div className="mx-auto grid max-w-7xl gap-8 px-5 py-14 md:grid-cols-4 md:px-8">
          <div className="md:col-span-1">
            <Logo onClick={() => navigate('home')} />
            <p className="mt-4 max-w-xs text-sm text-muted-foreground">
              Đại lý phân phối tài khoản và token AI uy tín hàng đầu Việt Nam. Nạp tiền một lần, dùng dần mọi công cụ.
            </p>
          </div>
          {[
            ['Công cụ', ['ChatGPT Plus', 'Claude Pro', 'Midjourney', 'Gói Token API']],
            ['Hỗ trợ', ['Hướng dẫn nạp tiền', 'Chính sách bảo hành', 'Điều khoản sử dụng', 'Bảo mật thông tin']],
            ['Liên hệ', ['Zalo: 0908.888.888', 'Email: support@mitom.ai', 'Cộng đồng AI Việt Nam', 'Hỗ trợ kỹ thuật 24/7']],
          ].map(([title, links]) => (
            <div key={title as string}>
              <h4 className="font-display text-sm font-bold uppercase tracking-wide">{title as string}</h4>
              <ul className="mt-4 space-y-2.5 text-sm text-muted-foreground">
                {(links as string[]).map((l) => (
                  <li key={l}>
                    <a href="#" className="transition-colors hover:text-primary">
                      {l}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="border-t border-border">
          <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-2 px-5 py-6 text-xs text-muted-foreground md:flex-row md:px-8">
            <span>© 2026 Mì Tôm AI. Hệ thống nạp thẻ & công cụ AI tự động.</span>
            <span className="font-mono">Made in Vietnam 🇻🇳</span>
          </div>
        </div>
      </footer>

      <OrderLookupModal isOpen={isLookupOpen} onClose={() => setIsLookupOpen(false)} />
    </div>
  )
}

function HomePage({
  active,
  setActive,
  filtered,
  openFaq,
  setOpenFaq,
  onTopup,
  goPricing,
  goProducts,
}: {
  active: Category | 'all'
  setActive: (c: Category | 'all') => void
  filtered: Product[]
  openFaq: number | null
  setOpenFaq: (n: number | null) => void
  onTopup: (t: TopUp) => void
  goPricing: () => void
  goProducts: () => void
}) {
  return (
    <>
      {/* Hero */}
      <section
        className="relative overflow-hidden border-b border-border"
        style={{
          backgroundImage:
            'linear-gradient(var(--grid-line) 1px, transparent 1px), linear-gradient(90deg, var(--grid-line) 1px, transparent 1px)',
          backgroundSize: '56px 56px',
        }}
      >
        <div className="pointer-events-none absolute -top-40 left-1/2 h-96 w-[46rem] -translate-x-1/2 rounded-full bg-primary/10 blur-[120px]" />
        <div className="mx-auto grid max-w-7xl gap-12 px-5 py-20 md:px-8 lg:grid-cols-[1.1fr_0.9fr] lg:py-28">
          <div className="flex flex-col justify-center">
            <span className="mb-5 inline-flex w-fit items-center gap-2 rounded-sm border border-border bg-card px-3 py-1.5 font-mono text-xs text-muted-foreground">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> Nạp một lần · Dùng dần · Không hết hạn
            </span>
            <h1 className="font-display text-4xl font-black leading-[1.05] tracking-tight md:text-6xl">
              Một số dư,
              <br />
              <span className="text-primary">mọi công cụ</span> AI.
            </h1>
            <p className="mt-6 max-w-lg text-base leading-relaxed text-muted-foreground md:text-lg">
              Nạp tiền vào tài khoản Mì Tôm AI rồi dùng dần cho ChatGPT Plus, Claude, Midjourney, Gemini và gói token API. Dùng tới đâu trừ tới đó — hết thì nạp thêm.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <button
                onClick={goPricing}
                className="glow-button rounded-sm bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
              >
                Nạp tiền ngay
              </button>
              <button
                onClick={goProducts}
                className="glow-button-secondary rounded-sm border border-border bg-card px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60"
              >
                Xem công cụ có sẵn
              </button>
            </div>
            <div className="mt-10 grid max-w-md grid-cols-3 gap-6 border-t border-border pt-8">
              {[
                ['12.400+', 'Khách đã nạp'],
                ['4.9/5', 'Đánh giá'],
                ['24/7', 'Hỗ trợ'],
              ].map(([n, l]) => (
                <div key={l}>
                  <div className="font-display text-2xl font-extrabold text-foreground">{n}</div>
                  <div className="text-xs text-muted-foreground">{l}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Wallet balance mockup */}
          <div className="flex items-center justify-center">
            <div className="w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-2xl shadow-black/40">
              <div className="flex items-center justify-between">
                <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">Số dư Mì Tôm AI</span>
                <span className="rounded-sm bg-emerald/15 px-2.5 py-1 font-mono text-[11px] font-bold text-emerald">
                  Đang hoạt động
                </span>
              </div>
              <div className="mt-3 font-display text-4xl font-black text-primary">550.000đ</div>
              <div className="mt-1 font-mono text-xs text-muted-foreground">Không kỳ hạn · dùng cho mọi công cụ</div>
              <div className="mt-5 space-y-3 border-t border-border pt-5">
                <span className="font-mono text-[11px] uppercase tracking-wide text-muted-foreground">Lịch sử gần đây</span>
                {[
                  ['Kích hoạt ChatGPT Plus', '−289.000đ', '#34d399', 'AI'],
                  ['Mua 5M Token API', '−149.000đ', '#60a5fa', 'TK'],
                  ['Nạp qua VietQR', '+1.000.000đ', '#f5c451', '＋'],
                ].map(([name, amt, c, ini]) => (
                  <div key={name} className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <span
                        className="grid h-9 w-9 place-items-center rounded-xl font-mono text-xs font-bold"
                        style={{ background: `${c}1a`, color: c }}
                      >
                        {ini}
                      </span>
                      <span className="text-sm font-medium">{name}</span>
                    </div>
                    <span className={`font-mono text-sm ${amt.startsWith('+') ? 'text-emerald' : 'text-foreground'}`}>
                      {amt}
                    </span>
                  </div>
                ))}
              </div>
              <button
                onClick={goPricing}
                className="glow-button mt-5 w-full rounded-sm bg-primary py-3 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02]"
              >
                Nạp thêm số dư
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Trust bar */}
      <div className="border-b border-border bg-secondary/40">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-center gap-x-10 gap-y-3 px-5 py-4 font-mono text-xs text-muted-foreground md:px-8">
          {['VietQR', 'Momo', 'ZaloPay', 'MB Bank', 'Vietcombank', 'Techcombank'].map((b) => (
            <span key={b} className="transition-colors hover:text-foreground">
              {b}
            </span>
          ))}
        </div>
      </div>

      {/* Products — showcase */}
      <section id="products" className="mx-auto max-w-7xl px-5 py-20 md:px-8">
        <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
          <div>
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Công cụ có sẵn</span>
            <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Những gì bạn dùng được</h2>
            <p className="mt-2 max-w-lg text-sm text-muted-foreground">
              Nạp tiền vào số dư, rồi nhắn Zalo chọn công cụ bên dưới. Shop kích hoạt và trừ vào số dư của bạn.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            {CATEGORIES.map((c) => (
              <button
                key={c.id}
                onClick={() => setActive(c.id)}
                className={`glow-button-secondary rounded-sm border px-4 py-2 text-sm font-medium transition-colors ${
                  active === c.id
                    ? 'border-primary bg-primary text-primary-foreground'
                    : 'border-border bg-card text-secondary-foreground hover:border-primary/50'
                }`}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((p) => (
            <ProductCard key={p.id} p={p} />
          ))}
        </div>
      </section>

      {/* Pricing — nạp tiền */}
      <section id="pricing" className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-7xl px-5 py-20 md:px-8">
          <div className="text-center">
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Nạp tiền</span>
            <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
              Nạp một lần, dùng dần thoải mái
            </h2>
            <p className="mx-auto mt-3 max-w-xl text-muted-foreground">
              Không mua theo tháng, không lo hết hạn. Nạp tiền vào số dư, dùng tới đâu trừ tới đó — hết thì nạp thêm. Nạp càng nhiều, tặng càng nhiều.
            </p>
          </div>

          <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {TOPUPS.map((t) => {
              const bonus = Math.round((t.amount * t.bonusPct) / 100)
              return (
                <div
                  key={t.amount}
                  className={`relative flex flex-col rounded-xl border p-6 transition-transform hover:-translate-y-1 ${
                    t.highlight ? 'border-primary bg-card shadow-2xl shadow-primary/10' : 'border-border bg-card'
                  }`}
                >
                  {t.highlight && (
                    <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-sm bg-primary px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-primary-foreground">
                      Chọn nhiều nhất
                    </span>
                  )}
                  <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">{t.label}</span>
                  <div className="mt-3 font-display text-3xl font-black">{formatVnd(t.amount)}</div>
                  {t.bonusPct > 0 ? (
                    <div className="mt-2 inline-flex w-fit items-center gap-1.5 rounded-sm bg-emerald/15 px-2.5 py-1 text-xs font-bold text-emerald">
                      +{t.bonusPct}% tặng {formatVnd(bonus)}
                    </div>
                  ) : (
                    <div className="mt-2 text-xs text-muted-foreground">Nạp tối thiểu, không kỳ hạn</div>
                  )}
                  <div className="mt-5 border-t border-border pt-4 text-xs text-muted-foreground">Số dư nhận được</div>
                  <div className="font-mono text-lg font-bold text-primary">{formatVnd(t.amount + bonus)}</div>
                  <button
                    onClick={() => onTopup(t)}
                    className={`glow-button mt-6 rounded-sm py-3 text-sm font-bold transition-transform hover:scale-[1.02] ${
                      t.highlight
                        ? 'bg-primary text-primary-foreground'
                        : 'border border-border bg-secondary text-secondary-foreground hover:border-primary/60'
                    }`}
                  >
                    Nạp {formatVnd(t.amount)}
                  </button>
                </div>
              )
            })}
          </div>

          <div className="mt-8 grid gap-4 sm:grid-cols-3">
            {[
              ['Số dư không hết hạn', 'Tiền trong tài khoản dùng bao lâu tuỳ bạn, không mất khi để lâu.'],
              ['Trả theo mức dùng', 'Mỗi lần kích hoạt tài khoản hoặc mua token sẽ trừ trực tiếp vào số dư.'],
              ['Nạp thêm bất cứ lúc nào', 'Gần hết? Nạp thêm chỉ trong 30 giây qua VietQR, Momo hay ZaloPay.'],
            ].map(([t, d]) => (
              <div key={t} className="flex gap-3 rounded-xl border border-border bg-card p-5">
                <span className="mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-sm bg-primary/15 text-primary">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                    <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
                <div>
                  <h3 className="font-display text-sm font-bold">{t}</h3>
                  <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{d}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how" className="mx-auto max-w-7xl px-5 py-20 md:px-8">
        <div className="mb-12">
          <span className="font-mono text-xs uppercase tracking-widest text-primary">// Quy trình</span>
          <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Dùng AI trong 4 bước</h2>
        </div>
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
          {[
            ['01', 'Nạp tiền vào số dư', 'Chọn mức nạp và thanh toán qua VietQR, Momo hoặc ZaloPay.'],
            ['02', 'Nhắn Zalo chọn công cụ', 'Báo shop công cụ AI bạn muốn dùng từ danh sách có sẵn.'],
            ['03', 'Trừ số dư & kích hoạt', 'Shop kích hoạt tài khoản và trừ đúng số tiền vào số dư của bạn.'],
            ['04', 'Dùng & bảo hành', 'Dùng ngay, có lỗi được đổi mới 1-1 trọn đời. Gần hết thì nạp thêm.'],
          ].map(([n, t, d]) => (
            <div key={n} className="relative rounded-xl border border-border bg-card p-6">
              <span className="font-mono text-3xl font-bold text-primary/30">{n}</span>
              <h3 className="mt-3 font-display text-lg font-bold">{t}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{d}</p>
            </div>
          ))}
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="border-t border-border bg-secondary/30">
        <div className="mx-auto grid max-w-7xl gap-10 px-5 py-20 md:px-8 lg:grid-cols-[0.8fr_1.2fr]">
          <div>
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Hỏi đáp</span>
            <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Câu hỏi thường gặp</h2>
            <p className="mt-4 text-muted-foreground">
              Chưa tìm thấy câu trả lời? Nhắn Zalo <span className="font-mono text-primary">0908.888.888</span> để được hỗ trợ ngay.
            </p>
          </div>
          <div className="divide-y divide-border rounded-xl border border-border bg-card">
            {FAQS.map((item, i) => (
              <button
                key={item.q}
                onClick={() => setOpenFaq(openFaq === i ? null : i)}
                className="flex w-full flex-col px-6 py-5 text-left"
              >
                <div className="flex items-center justify-between gap-4">
                  <span className="font-display font-bold">{item.q}</span>
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    className={`shrink-0 text-primary transition-transform ${openFaq === i ? 'rotate-45' : ''}`}
                  >
                    <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                  </svg>
                </div>
                <div className={`grid transition-all duration-300 ${openFaq === i ? 'mt-3 grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                  <p className="overflow-hidden text-sm leading-relaxed text-muted-foreground">{item.a}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="mx-auto max-w-7xl px-5 py-20 md:px-8">
        <div className="relative overflow-hidden rounded-xl border border-primary/30 bg-card px-8 py-14 text-center md:py-20">
          <div className="pointer-events-none absolute inset-0 bg-primary/5" />
          <div className="pointer-events-none absolute -bottom-24 left-1/2 h-64 w-[40rem] -translate-x-1/2 rounded-full bg-primary/10 blur-[100px]" />
          <div className="relative">
            <h2 className="font-display text-3xl font-black tracking-tight md:text-5xl">Sẵn sàng tăng tốc với AI?</h2>
            <p className="mx-auto mt-4 max-w-lg text-muted-foreground">
              Nạp một lần, dùng dần mọi công cụ. Hàng nghìn người Việt đã tiết kiệm chi phí AI mỗi tháng cùng Mì Tôm AI.
            </p>
            <button
              onClick={goPricing}
              className="glow-button mt-8 inline-block rounded-sm bg-primary px-8 py-4 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
            >
              Nạp tiền ngay
            </button>
          </div>
        </div>
      </section>
    </>
  )
}
