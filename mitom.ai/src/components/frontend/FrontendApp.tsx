'use client'

import React, { useState, type ReactNode } from 'react'
import Image from 'next/image'
import { ApiModel, ALL_MODELS } from '@/data/models-parser'
import { ModelsSection } from './ModelsSection'
import { useAuth } from '@/context/AuthContext'
import { UserProfileModal } from './UserProfileModal'
import { LoginModal } from './LoginModal'
import { User } from 'lucide-react'

export type Page = 'home' | 'topup' | 'success'

export interface TopUp {
  amount: number
  bonusPct: number
  label: string
  highlight: boolean
}

export const TOPUPS: TopUp[] = [
  { amount: 20000, bonusPct: 5, label: 'Thử nghiệm', highlight: false },
  { amount: 50000, bonusPct: 5, label: 'Nhẹ nhàng', highlight: false },
  { amount: 100000, bonusPct: 5, label: 'Khởi động', highlight: false },
  { amount: 200000, bonusPct: 5, label: 'Tiết kiệm', highlight: false },
  { amount: 500000, bonusPct: 5, label: 'Phổ biến', highlight: true },
  { amount: 1000000, bonusPct: 5, label: 'Miệt mài (VIP)', highlight: false },
]

export const PAY_METHODS = [
  { id: 'vietqr', label: 'VietQR / Chuyển khoản', note: 'Quét mã, tự động cộng số dư' },
  { id: 'momo', label: 'Ví Momo', note: 'Thanh toán nhanh qua app' },
  { id: 'zalopay', label: 'ZaloPay', note: 'Liên kết ngân hàng' },
]

export const FAQS = [
  {
    q: 'Endpoint API của Mì Tôm AI kết nối thế nào?',
    a: 'Endpoint https://api-us-ca.umodelverse.ai/v1 tương thích hoàn toàn với chuẩn OpenAI API. Bạn có thể sử dụng trực tiếp trong OpenAI Python/Node SDK, Next.js, Cline, Cursor, Roo Code, LibreChat, Dify hoặc OpenWebUI bằng cách cấu hình Base URL và API Key.',
  },
  {
    q: 'Số dư nạp vào có bị hết hạn không?',
    a: 'Không. Tiền bạn nạp được cộng vào số dư tài khoản và dùng đến khi nào hết thì thôi, không có kỳ hạn. Mọi yêu cầu gọi model API sẽ trừ trực tiếp vào số dư này theo bảng giá niêm yết.',
  },
  {
    q: 'Hệ thống hỗ trợ những dòng model AI nào?',
    a: 'Hệ thống hỗ trợ hơn 130 model tiên tiến bao gồm DeepSeek V3/V4, GLM-5.3, Alibaba Qwen (3.5/3.7/3.8/Coder), ByteDance Doubao, Kimi K3, MiniMax Hailuo/Speech, Kling Video, ShengShu Vidu, Wan-AI và nhiều model chuyên dụng khác.',
  },
  {
    q: 'Thanh toán và nạp tiền bằng cách nào?',
    a: 'Chúng tôi hỗ trợ chuyển khoản ngân hàng nội địa VietQR, Momo và ZaloPay. Số dư được cộng tự động ngay sau khi xác nhận thanh toán thành công.',
  },
  {
    q: 'Chính sách hỗ trợ kỹ thuật thế nào?',
    a: 'Đội ngũ kỹ thuật hỗ trợ 24/7 qua Zalo. Nếu gặp sự cố khi tích hợp endpoint hoặc cần cấp key trải nghiệm, bạn chỉ cần liên hệ Zalo để được hỗ trợ tức thì.',
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
      className="flex items-center gap-3 group"
    >
      <div className="relative h-9 w-9 flex items-center justify-center">
        <Image
          src="/logo.png"
          alt="Mì Tôm AI Logo"
          width={36}
          height={36}
          className="h-full w-full object-contain"
          priority
        />
      </div>
      <span className="font-display text-xl font-extrabold tracking-tight">
        Mì Tôm <span className="text-primary">AI</span>
      </span>
    </a>
  )
}

export function QrMock({ amount }: { amount?: number }) {
  const bankId = 'MBBank'
  const accountNo = '0938414436'
  const accountName = 'NGUYEN NGOC THANH VY'
  const memo = amount ? `NAP ${amount / 1000}K` : 'NAP TIEN MITOM AI'
  const qrUrl = amount
    ? `https://vietqr.app/img?bank=${bankId}&acc=${accountNo}&template=&showinfo=true&holder=${encodeURIComponent(accountName)}&amount=${amount}&memo=${encodeURIComponent(memo)}`
    : null

  if (qrUrl) {
    return (
      <div className="w-full max-w-xs aspect-square shrink-0 overflow-hidden rounded-2xl bg-white p-3 md:p-4 shadow-lg ring-1 ring-border flex items-center justify-center">
        <img
          src={qrUrl}
          alt="Mã VietQR nạp tiền"
          className="h-full w-full object-contain"
        />
      </div>
    )
  }

  return (
    <div className="flex w-full max-w-xs aspect-square shrink-0 flex-col items-center justify-center rounded-2xl bg-primary/10 text-center font-mono text-xs text-primary ring-1 ring-border">
      <span className="font-bold text-base">VietQR</span>
      <span className="text-xs text-muted-foreground">Tự động cộng</span>
    </div>
  )
}

function TopUpPage({
  topup,
  onDone,
  onNavigate,
}: {
  topup: TopUp
  onDone: (order: any) => void
  onNavigate: (p: Page) => void
}) {
  const { user } = useAuth()
  const [pay, setPay] = useState('vietqr')
  const [phone, setPhone] = useState('')
  const [name, setName] = useState(user?.name || '')
  const [email, setEmail] = useState(user?.email || '')
  const [note, setNote] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  React.useEffect(() => {
    if (user) {
      if (user.email && !email) setEmail(user.email)
      if (user.name && !name) setName(user.name)
    }
  }, [user])

  const bonus = Math.round((topup.amount * topup.bonusPct) / 100)
  const total = topup.amount

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!phone && !email) {
      setError('Vui lòng nhập số điện thoại hoặc email để nhận thông báo.')
      return
    }

    setLoading(true)
    setError(null)

    try {
      const res = await fetch('/api/orders/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          amount: topup.amount,
          bonusPct: topup.bonusPct,
          paymentMethod: pay,
          customerName: name || 'Khách nạp số dư',
          customerPhone: phone,
          customerEmail: email,
          customerNote: note,
        }),
      })

      const data = await res.json()
      if (!res.ok || !data.success) {
        throw new Error(data.message || 'Không thể tạo đơn nạp, vui lòng thử lại sau.')
      }

      onDone({
        code: data.order.orderCode,
        amount: total,
        totalBalance: topup.amount + bonus,
        payMethod: PAY_METHODS.find((m) => m.id === pay)?.label || pay,
        phone,
        email,
        qrCodeUrl: data.order.qrCodeUrl,
        bankDetails: data.order.bankDetails,
      })
    } catch (err: any) {
      setError(err.message || 'Đã có lỗi xảy ra.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="mx-auto max-w-6xl px-5 py-12 md:px-8">
      <button
        onClick={() => onNavigate('home')}
        className="group mb-8 inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
      >
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className="transition-transform group-hover:-translate-x-1"
        >
          <path d="M19 12H5M12 19l-7-7 7-7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Quay lại trang chủ
      </button>

      <div className="mb-8">
        <span className="font-mono text-xs uppercase tracking-widest text-primary">// Xác nhận nạp tiền</span>
        <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Nạp số dư API</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Nạp tiền vào tài khoản để gọi trực tiếp các mô hình AI hoặc nhận hỗ trợ tích hợp.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="grid gap-8 lg:grid-cols-[1fr_360px]">
        <div className="grid gap-6 md:grid-cols-2">
          <fieldset className="rounded-xl border border-border bg-card p-6">
            <legend className="px-2 font-display text-lg font-bold">Thông tin nhận mã / tài khoản</legend>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                  Số điện thoại / Zalo <span className="text-primary">*</span>
                  <input
                    type="tel"
                    required
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="0908888888"
                    className="mt-1.5 w-full rounded-md border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </label>
              </div>

              <div>
                <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                  Họ và tên
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Nguyễn Văn A"
                    className="mt-1.5 w-full rounded-md border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </label>
              </div>

              <div>
                <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                  Email (để nhận biên lai & API Key)
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="ban@gmail.com"
                    className="mt-1.5 w-full rounded-md border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </label>
              </div>

              <div>
                <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                  Ghi chú
                  <textarea
                    rows={2}
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="Model cần tư vấn hoặc ghi chú thêm..."
                    className="mt-1.5 w-full rounded-md border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
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
              <div className="mt-4 flex flex-col items-center gap-5 rounded-2xl border border-dashed border-border bg-secondary/30 p-6 md:p-8">
                <QrMock amount={topup.amount} />
                <div className="text-center md:text-left w-full space-y-2">
                  <div className="font-bold text-foreground text-base">Quét mã VietQR tự động</div>
                  <p className="font-mono text-xs leading-relaxed text-muted-foreground bg-secondary/50 p-4 rounded-xl border border-border">
                    <span className="text-foreground font-semibold">Chủ TK:</span> NGUYEN NGOC THANH VY<br />
                    <span className="text-foreground font-semibold">STK:</span> 0938414436 · MB Bank<br />
                    <span className="text-foreground font-semibold">Nội dung:</span> <span className="font-bold text-primary">NAP {topup.amount / 1000}K</span>
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
            <span className="font-display text-base font-bold">Số dư nhận được</span>
            <span className="font-display text-2xl font-black text-primary">
              {formatVnd(topup.amount + bonus)}
            </span>
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            Số dư dùng trực tiếp cho toàn bộ model AI trên hệ thống, không hết hạn.
          </p>

          {error && (
            <div className="mt-4 rounded-sm border border-rose-500/40 bg-rose-500/10 p-3 text-xs text-rose-400">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="glow-button mt-6 w-full rounded-md bg-primary py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50"
          >
            {loading ? 'Đang tạo đơn...' : `Thanh toán ${formatVnd(total)}`}
          </button>
        </aside>
      </form>
    </main>
  )
}

function SuccessPage({
  topup,
  orderInfo,
  onNavigate,
}: {
  topup: TopUp | null
  orderInfo: any
  onNavigate: (p: Page) => void
}) {
  const [copied, setCopied] = useState(false)

  const handleCopyCode = () => {
    if (orderInfo?.code) {
      navigator.clipboard.writeText(orderInfo.code)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  return (
    <main className="mx-auto max-w-2xl px-5 py-16 text-center md:px-8">
      <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-emerald/15 text-emerald">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none">
          <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>

      <span className="mt-6 inline-block font-mono text-xs uppercase tracking-widest text-primary">
        // Nạp tiền thành công
      </span>
      <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
        Đơn nạp đã được khởi tạo!
      </h1>
      <p className="mx-auto mt-3 max-w-md text-sm text-muted-foreground">
        Đơn nạp đã được ghi nhận. Quý khách vui lòng quét mã chuyển khoản hoặc nhắn tin qua Zalo để kích hoạt API Key.
      </p>

      {orderInfo && (
        <div className="mt-8 rounded-xl border border-border bg-card p-6 text-left shadow-lg">
          <div className="flex items-center justify-between border-b border-border pb-4">
            <span className="font-mono text-xs uppercase text-muted-foreground">Mã đơn nạp</span>
            <div className="flex items-center gap-2">
              <span className="font-mono text-sm font-bold text-primary">{orderInfo.code}</span>
              <button
                onClick={handleCopyCode}
                className="rounded border border-border px-2 py-1 font-mono text-[10px] text-muted-foreground hover:text-foreground"
              >
                {copied ? 'Đã chép' : 'Sao chép'}
              </button>
            </div>
          </div>

          <dl className="mt-4 space-y-2.5 text-sm">
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Số tiền thanh toán</dt>
              <dd className="font-mono font-bold">{formatVnd(orderInfo.amount)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Số dư nhận được</dt>
              <dd className="font-mono font-bold text-emerald">{formatVnd(orderInfo.totalBalance)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Phương thức</dt>
              <dd>{orderInfo.payMethod}</dd>
            </div>
          </dl>

          {orderInfo.qrCodeUrl && (
            <div className="mt-6 flex flex-col items-center justify-center rounded-2xl border border-border bg-secondary/30 p-6 md:p-8">
              <div className="w-full max-w-sm aspect-square relative flex items-center justify-center">
                <img src={orderInfo.qrCodeUrl} alt="Mã thanh toán VietQR" className="w-full h-full object-contain rounded-xl" />
              </div>
              <p className="mt-4 text-center text-sm font-medium text-muted-foreground px-4 py-2">
                Mở ứng dụng ngân hàng bất kỳ để quét mã thanh toán tự động
              </p>
            </div>
          )}
        </div>
      )}

      <div className="mt-8 flex flex-col sm:flex-row justify-center gap-3">
        <a
          href={ZALO}
          target="_blank"
          rel="noreferrer"
          className="glow-button rounded-md bg-primary px-6 py-3 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
        >
          Nhắn Zalo hỗ trợ tức thì
        </a>
        <button
          onClick={() => onNavigate('home')}
          className="glow-button-secondary rounded-md border border-border bg-card px-6 py-3 text-sm font-semibold text-secondary-foreground hover:border-primary/60"
        >
          Về trang chủ
        </button>
      </div>
    </main>
  )
}

function OrderLookupModal({
  isOpen,
  onClose,
}: {
  isOpen: boolean
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<any>(null)

  if (!isOpen) return null

  const handleLookup = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!query.trim()) return

    setLoading(true)
    setError(null)
    setResult(null)

    try {
      const res = await fetch(`/api/orders/lookup?query=${encodeURIComponent(query.trim())}`)
      const data = await res.json()
      if (!res.ok || !data.success) {
        throw new Error(data.message || 'Không tìm thấy đơn hàng phù hợp.')
      }
      setResult(data.order)
    } catch (err: any) {
      setError(err.message || 'Lỗi khi tra cứu.')
    } finally {
      setLoading(false)
    }
  }

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return <span className="rounded bg-emerald/20 px-2 py-0.5 text-xs text-emerald font-semibold">Đã hoàn thành</span>
      case 'paid':
        return <span className="rounded bg-blue-500/20 px-2 py-0.5 text-xs text-blue-400 font-semibold">Đã thanh toán</span>
      case 'cancelled':
        return <span className="rounded bg-rose-500/20 px-2 py-0.5 text-xs text-rose-400 font-semibold">Đã hủy</span>
      default:
        return <span className="rounded bg-amber-500/20 px-2 py-0.5 text-xs text-amber-400 font-semibold">Chờ thanh toán</span>
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div className="w-full max-w-lg rounded-2xl border border-border bg-card p-6 shadow-2xl">
        <div className="flex items-center justify-between border-b border-border pb-4">
          <h3 className="font-display text-lg font-bold">Tra cứu đơn nạp</h3>
          <button
            onClick={onClose}
            className="rounded p-1 text-muted-foreground hover:bg-secondary hover:text-foreground"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
              <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        <form onSubmit={handleLookup} className="mt-4 flex gap-2">
          <input
            type="text"
            required
            placeholder="Nhập mã đơn (MT...), SĐT hoặc Email"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="flex-1 rounded-md border border-border bg-secondary/40 px-3.5 py-2 text-sm text-foreground focus:border-primary focus:outline-none"
          />
          <button
            type="submit"
            disabled={loading}
            className="glow-button rounded-md bg-primary px-4 py-2 text-sm font-bold text-primary-foreground disabled:opacity-50"
          >
            {loading ? 'Đang tìm...' : 'Tra cứu'}
          </button>
        </form>

        {error && (
          <div className="mt-4 rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-400">
            {error}
          </div>
        )}

        {result && (
          <div className="mt-5 space-y-3 rounded-xl border border-border bg-secondary/20 p-4 text-sm">
            <div className="flex items-center justify-between">
              <span className="font-mono text-xs text-muted-foreground">Mã đơn</span>
              <span className="font-mono font-bold text-primary">{result.orderCode}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Trạng thái</span>
              {getStatusBadge(result.status)}
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Số tiền thanh toán</span>
              <span className="font-mono font-semibold">{formatVnd(result.totalAmount)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Số dư nhận</span>
              <span className="font-mono font-bold text-emerald">{formatVnd(result.totalBalanceAdded)}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export function FrontendApp({
  models = ALL_MODELS,
  adminRoute = '/admin',
}: {
  models?: ApiModel[]
  adminRoute?: string
}) {
  const { user, openLoginModal } = useAuth()
  const [page, setPage] = useState<Page>('home')
  const [topup, setTopup] = useState<TopUp | null>(null)
  const [orderInfo, setOrderInfo] = useState<any>(null)
  const [openFaq, setOpenFaq] = useState<number | null>(0)
  const [isLookupOpen, setIsLookupOpen] = useState(false)
  const [isProfileOpen, setIsProfileOpen] = useState(false)
  const [isLoginOpen, setIsLoginOpen] = useState(false)

  const navigate = (p: Page) => {
    setPage(p)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const startTopup = (t: TopUp) => {
    setTopup(t)
    navigate('topup')
  }

  const scrollToElement = (id: string) => {
    const el = document.getElementById(id)
    if (el) {
      const offset = 80 // khoảng cách trừ hao header sticky
      const bodyRect = document.body.getBoundingClientRect().top
      const elementRect = el.getBoundingClientRect().top
      const elementPosition = elementRect - bodyRect
      const offsetPosition = elementPosition - offset

      window.scrollTo({
        top: offsetPosition,
        behavior: 'smooth',
      })
    }
  }

  const goPricing = () => {
    if (page !== 'home') {
      setPage('home')
      setTimeout(() => scrollToElement('pricing'), 100)
    } else {
      scrollToElement('pricing')
    }
  }

  const goModels = () => {
    if (page !== 'home') {
      setPage('home')
      setTimeout(() => scrollToElement('models'), 100)
    } else {
      scrollToElement('models')
    }
  }

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
        models={models}
        openFaq={openFaq}
        setOpenFaq={setOpenFaq}
        onTopup={startTopup}
        goPricing={goPricing}
        goModels={goModels}
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
            <button onClick={goModels} className="transition-colors hover:text-primary">
              Model API ({models.length})
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
          </nav>
          <div className="flex items-center gap-3">
            <button
              onClick={() => setIsLookupOpen(true)}
              className="glow-button-secondary rounded-md border border-border bg-secondary px-3 py-2 text-xs font-semibold text-secondary-foreground hover:border-primary/50 lg:hidden"
            >
              Tra cứu
            </button>
            {user ? (
              <button
                onClick={() => setIsProfileOpen(true)}
                className="flex items-center gap-2 rounded-lg border border-border bg-secondary/60 px-3.5 py-2 text-xs font-bold text-foreground transition-all hover:border-primary/50"
              >
                <div className="flex h-6 w-6 items-center justify-center rounded-full bg-primary/20 text-[11px] text-primary overflow-hidden font-mono font-bold">
                  {user.avatar ? (
                    <img src={user.avatar} alt="Avatar" className="h-full w-full object-cover" />
                  ) : (
                    (user.name || user.email).charAt(0).toUpperCase()
                  )}
                </div>
                <span className="max-w-[120px] truncate">{user.name || user.email.split('@')[0]}</span>
                <span className="rounded bg-primary/10 px-1.5 py-0.5 font-mono text-[10px] text-primary">
                  {user.balance.toLocaleString('vi-VN')}đ
                </span>
              </button>
            ) : (
              <button
                onClick={() => {
                  setIsLoginOpen(true)
                  openLoginModal()
                }}
                className="glow-button flex items-center gap-1.5 rounded-md bg-primary px-4 py-2.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
              >
                <User size={16} className="shrink-0" />
                <span>Đăng nhập</span>
              </button>
            )}
          </div>
        </div>
      </header>

      {content}

      <footer className="border-t border-border">
        <div className="mx-auto grid max-w-7xl gap-8 px-5 py-14 md:grid-cols-4 md:px-8">
          <div className="md:col-span-1">
            <Logo onClick={() => navigate('home')} />
            <p className="mt-4 max-w-xs text-sm text-muted-foreground">
              Cổng API AI hiệu năng cao, cung cấp hơn 130 model tiên tiến. Nạp số dư một lần, dùng mọi model qua OpenAI SDK.
            </p>
          </div>
          {[
            ['Model nổi bật', ['DeepSeek V3 / V4', 'GLM-5.3 Flash & Pro', 'Qwen 3.8 / Coder', 'Kling Video & Wan-AI']],
            ['Hỗ trợ', ['Hướng dẫn nạp tiền', 'Tài liệu tích hợp API', 'Điều khoản sử dụng', 'Bảo mật thông tin']],
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
            <span>© 2026 Mì Tôm AI. Hệ thống API & Model AI hiệu năng cao.</span>
            <span className="font-mono">Made in Vietnam 🇻🇳</span>
          </div>
        </div>
      </footer>

      <OrderLookupModal isOpen={isLookupOpen} onClose={() => setIsLookupOpen(false)} />
      <UserProfileModal isOpen={isProfileOpen} onClose={() => setIsProfileOpen(false)} />
      <LoginModal isOpen={isLoginOpen} onClose={() => setIsLoginOpen(false)} />
    </div>
  )
}

function HomePage({
  models,
  openFaq,
  setOpenFaq,
  onTopup,
  goPricing,
  goModels,
}: {
  models: ApiModel[]
  openFaq: number | null
  setOpenFaq: (n: number | null) => void
  onTopup: (t: TopUp) => void
  goPricing: () => void
  goModels: () => void
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
              <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> Hơn 130 Model AI · Chuẩn OpenAI API · Sẵn sàng 24/7
            </span>
            <h1 className="font-display text-4xl font-black leading-[1.05] tracking-tight md:text-6xl">
              Một số dư,
              <br />
              <span className="text-primary">mọi model</span> AI.
            </h1>
            <p className="mt-6 max-w-lg text-base leading-relaxed text-muted-foreground md:text-lg">
              Tích hợp trực tiếp các mô hình AI mạnh mẽ nhất từ DeepSeek, Zhipu GLM, Alibaba Qwen, ByteDance Doubao, Kling và Wan-AI qua duy nhất một API Endpoint tốc độ cao.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <button
                onClick={goPricing}
                className="glow-button rounded-md bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]"
              >
                Các gói thẻ
              </button>
              <button
                onClick={goModels}
                className="glow-button-secondary rounded-md border border-border bg-card px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60"
              >
                Khám phá {models.length} Model có sẵn
              </button>
            </div>
            <div className="mt-10 grid max-w-md grid-cols-3 gap-6 border-t border-border pt-8">
              {[
                [`${models.length}+`, 'Model sẵn sàng'],
                ['99.9%', 'Uptime API'],
                ['24/7', 'Hỗ trợ kỹ thuật'],
              ].map(([n, l]) => (
                <div key={l}>
                  <div className="font-display text-2xl font-extrabold text-foreground">{n}</div>
                  <div className="text-xs text-muted-foreground">{l}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Wallet balance & API Endpoint mockup */}
          <div className="flex items-center justify-center lg:justify-end">
            <div className="w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-2xl shadow-black/40">
              <div className="flex items-center justify-between">
                <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">Số dư API Mì Tôm</span>
                <span className="rounded-sm bg-emerald/15 font-mono text-[11px] font-bold text-emerald">
                  Đang hoạt động
                </span>
              </div>
              <div className="mt-3 font-display text-4xl font-black text-primary">550.000đ</div>
              <div className="mt-1 font-mono text-xs text-muted-foreground">Dùng linh hoạt cho hơn 130 model AI</div>
              <div className="mt-5 space-y-3 border-t border-border pt-5">
                <span className="font-mono text-[11px] uppercase tracking-wide text-muted-foreground">Tác vụ gọi gần đây</span>
                {[
                  ['DeepSeek-V4 Pro Request', '−2.400đ', '#0066ff', 'DS'],
                  ['GLM-5.3 Flash Batch', '−850đ', '#3b82f6', 'GL'],
                  ['Nạp số dư VietQR', '+1.000.000đ', '#f5c451', '＋'],
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
                className="glow-button mt-5 w-full rounded-md bg-primary py-3 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02]"
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
          {['OpenAI Compatible', 'DeepSeek', 'Zhipu GLM', 'Alibaba Qwen', 'ByteDance Doubao', 'Kling Video', 'ShengShu Vidu', 'MiniMax'].map((b) => (
            <span key={b} className="transition-colors hover:text-foreground">
              {b}
            </span>
          ))}
        </div>
      </div>

      {/* Models Section */}
      <ModelsSection models={models} />

      {/* Pricing — nạp tiền */}
      <section id="pricing" className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-7xl px-5 py-20 md:px-8">
          <div className="text-center">
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Nạp tiền số dư</span>
            <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
              Nạp một lần, gọi API linh hoạt
            </h2>
            <p className="mx-auto mt-3 max-w-xl text-muted-foreground">
              Không mua theo tháng, không lo hết hạn. Nạp tiền vào số dư, gọi model tới đâu trừ tới đó — hết thì nạp thêm. Nạp càng nhiều, tặng thưởng càng lớn.
            </p>
          </div>

          <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
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
                    <div className="mt-2 inline-flex h-6 w-fit items-center gap-1.5 rounded-sm bg-emerald/15 px-2.5 text-xs font-bold text-emerald">
                      +{t.bonusPct}% tặng {formatVnd(bonus)}
                    </div>
                  ) : (
                    <div className="mt-2 inline-flex h-6 w-fit items-center text-xs text-muted-foreground">
                      Nạp tối thiểu, không kỳ hạn
                    </div>
                  )}
                  <div className="mt-5 border-t border-border pt-4 text-xs text-muted-foreground">Số dư nhận được</div>
                  <div className="font-mono text-lg font-bold text-primary">{formatVnd(t.amount + bonus)}</div>
                  <button
                    onClick={() => onTopup(t)}
                    className={`glow-button mt-6 rounded-md py-3 text-sm font-bold transition-transform hover:scale-[1.02] ${
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
              ['Số dư không hết hạn', 'Tiền trong tài khoản dùng bao lâu tuỳ bạn, bảo lưu vĩnh viễn.'],
              ['Tính theo lượt gọi thực tế', 'Mỗi lượt gọi API được trừ chính xác vào số dư theo bảng giá niêm yết.'],
              ['Nạp thêm tự động trong 30 giây', 'Nạp qua VietQR, Momo hay ZaloPay được kích hoạt tức thì 24/7.'],
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
          <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Sử dụng API trong 4 bước</h2>
        </div>
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
          {[
            ['01', 'Nạp số dư tài khoản', 'Chọn gói nạp và quét mã thanh toán qua VietQR, Momo hoặc ZaloPay.'],
            ['02', 'Lấy API Key & Endpoint', 'Nhận API Key kích hoạt và cấu hình Endpoint vào ứng dụng của bạn.'],
            ['03', 'Chọn Model tương thích', 'Sao chép mã Model từ danh mục (hơn 130 models) và đưa vào cấu hình.'],
            ['04', 'Gọi API & Tối ưu', 'Trừ theo lượng token/lượt sinh thực tế, hỗ trợ kỹ thuật 24/7 khi cần.'],
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
              Chưa tìm thấy câu trả lời? Nhắn Zalo <span className="font-mono text-primary">0908.888.888</span> để được đội ngũ kỹ thuật hỗ trợ ngay.
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
    </>
  )
}
