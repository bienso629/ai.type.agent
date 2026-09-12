'use client'

import React, { useState, type ReactNode } from 'react'
import Image from 'next/image'
import { ApiModel, ALL_MODELS } from '@/data/models-parser'
import { ModelsSection } from './ModelsSection'
import { useAuth } from '@/context/AuthContext'
import { UserProfileModal } from './UserProfileModal'
import { LoginModal } from './LoginModal'
import { GuideTopupPage, ApiDocsPage, TermsPage, PrivacyPage } from './StaticPages'
import { User, ChevronLeft, ChevronRight, Sparkles, Copy, Check, X } from 'lucide-react'

export type Page = 'home' | 'models' | 'topup' | 'success' | 'guide-topup' | 'api-docs' | 'terms' | 'privacy'

export interface TopUp {
  amount: number
  bonusPct: number
  label: string
  highlight: boolean
}

export const TOPUPS: TopUp[] = [
  { amount: 100000, bonusPct: 5, label: 'Khởi động', highlight: false },
  { amount: 200000, bonusPct: 5, label: 'Tiết kiệm', highlight: false },
  { amount: 500000, bonusPct: 5, label: 'Phổ biến', highlight: true },
  { amount: 1000000, bonusPct: 5, label: 'Miệt mài (VIP)', highlight: false },
]

export const PAY_METHODS = [
  { id: 'vietqr', label: 'VietQR / Chuyển khoản', note: 'Quét mã, tự động cộng số dư' },
]

export const FAQS = [
  {
    q: 'Endpoint API của Mì Tôm AI kết nối thế nào?',
    a: 'Endpoint https://api-vn-sg.mitom.ai/v1 tương thích hoàn toàn với chuẩn OpenAI API. Bạn có thể sử dụng trực tiếp trong OpenAI Python/Node SDK, Next.js, Cline, Cursor, Roo Code, LibreChat, Dify hoặc OpenWebUI bằng cách cấu hình Base URL và API Key.',
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
    a: 'Chúng tôi hỗ trợ chuyển khoản ngân hàng tự động qua VietQR 24/7. Số dư được cộng tự động ngay sau khi xác nhận thanh toán thành công.',
  },
  {
    q: 'Chính sách hỗ trợ kỹ thuật thế nào?',
    a: 'Đội ngũ kỹ thuật hỗ trợ 24/7 qua Zalo. Nếu gặp sự cố khi tích hợp endpoint hoặc cần cấp key trải nghiệm, bạn chỉ cần liên hệ Zalo để được hỗ trợ tức thì.',
  },
]

export const ZALO = 'https://zalo.me/4275289637074408185'
export const formatVnd = (n: number) => n.toLocaleString('vi-VN') + 'đ'

export function HeroModelSlider({
  models,
  goModels,
}: {
  models: ApiModel[]
  goModels: () => void
}) {
  // Lấy các model mới nhất hoặc nổi bật nhất
  const latestModels = React.useMemo(() => {
    const featured = models.filter(
      (m) =>
        m.badge === 'Mới nhất' ||
        m.id.toLowerCase().includes('deepseek-v4') ||
        m.id.toLowerCase().includes('glm-5.3') ||
        m.id.toLowerCase().includes('wan3.0') ||
        m.id.toLowerCase().includes('qwen3.8') ||
        m.id.toLowerCase().includes('kimi-k3') ||
        m.id.toLowerCase().includes('minimax-hailuo')
    )
    return featured.length > 0 ? featured : models.slice(0, 10)
  }, [models])

  const [currentIndex, setCurrentIndex] = useState(0)

  const currentModel = latestModels[currentIndex] || models[0]

  const handleNext = () => {
    setCurrentIndex((prev) => (prev + 1) % latestModels.length)
  }

  const handlePrev = () => {
    setCurrentIndex((prev) => (prev - 1 + latestModels.length) % latestModels.length)
  }

  if (!currentModel) return null

  return (
    <div className="w-full max-w-md lg:max-w-lg rounded-2xl border border-border bg-card p-6 md:p-7 shadow-2xl shadow-black/40 relative overflow-hidden transition-all duration-300">
      {/* Background glow theo màu accent của model */}
      <div
        className="pointer-events-none absolute -right-16 -top-16 h-56 w-56 rounded-full opacity-20 blur-3xl transition-all duration-500"
        style={{ background: currentModel.accent || '#f5c451' }}
      />

      {/* Header thanh điều hướng Slide */}
      <div className="flex items-center justify-between pb-4 border-b border-border">
        <span className="font-mono text-xs uppercase tracking-wider text-primary font-bold">
          Mô hình mới nhất
        </span>
        <div className="flex items-center gap-2">
          <span className="font-mono text-xs text-muted-foreground mr-1">
            {currentIndex + 1} / {latestModels.length}
          </span>
          <button
            type="button"
            onClick={handlePrev}
            title="Model trước"
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-secondary/80 text-foreground transition-all hover:border-primary hover:text-primary active:scale-90"
          >
            <ChevronLeft size={18} />
          </button>
          <button
            type="button"
            onClick={handleNext}
            title="Model tiếp theo"
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-secondary/80 text-foreground transition-all hover:border-primary hover:text-primary active:scale-90"
          >
            <ChevronRight size={18} />
          </button>
        </div>
      </div>

      {/* Model Info Card */}
      <div className="mt-5">
        <div className="flex items-start justify-between gap-4">
          <div className="overflow-hidden">
            <h3 className="truncate font-mono text-lg md:text-xl font-bold text-foreground" title={currentModel.id}>
              {currentModel.id}
            </h3>
            <span className="text-xs text-muted-foreground font-medium">{currentModel.provider}</span>
          </div>
          {currentModel.badge && (
            <span className="inline-flex h-6 shrink-0 items-center rounded-sm bg-primary/15 px-2.5 font-mono text-[11px] font-bold text-primary">
              {currentModel.badge}
            </span>
          )}
        </div>

        {/* Mô tả model */}
        <p className="mt-4 text-xs md:text-sm leading-relaxed text-muted-foreground line-clamp-3 min-h-[3.8rem]">
          {currentModel.description}
        </p>

      </div>
    </div>
  )
}

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
      <div className="relative h-12 w-12 flex items-center justify-center transition-transform group-hover:scale-105">
        <Image
          src="/logo.png"
          alt="Mì Tôm AI Logo"
          width={48}
          height={48}
          className="h-full w-full object-contain drop-shadow-sm"
          priority
        />
      </div>
      <span className="font-display text-2xl font-bold tracking-tight">
        Mì Tôm <span className="text-primary">AI</span>
      </span>
    </a>
  )
}

export function QrMock({ amount, memo: customMemo }: { amount?: number; memo?: string }) {
  const bankId = 'ACB'
  const accountNo = '199878939'
  const accountName = 'CTY CP CN TADU'
  const addInfo = customMemo || (amount ? `NAP ${amount / 1000}K` : 'NAP TIEN MITOM AI')
  const qrUrl = amount
    ? `https://img.vietqr.io/image/${bankId}-${accountNo}-compact.jpg?amount=${amount}&addInfo=${encodeURIComponent(addInfo)}&accountName=${encodeURIComponent(accountName)}`
    : `https://img.vietqr.io/image/${bankId}-${accountNo}-compact.jpg?accountName=${encodeURIComponent(accountName)}`

  if (qrUrl) {
    return (
      <div className="w-full max-w-sm sm:max-w-md aspect-square shrink-0 overflow-hidden flex items-center justify-center">
        <img
          src={qrUrl}
          alt="Mã VietQR nạp tiền công ty TADU"
          className="h-full w-full object-contain"
        />
      </div>
    )
  }

  return (
    <div className="flex w-full max-w-sm sm:max-w-md aspect-square shrink-0 flex-col items-center justify-center rounded-2xl bg-primary/10 text-center font-mono text-xs text-primary ring-1 ring-border">
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
  const { user, openLoginModal } = useAuth()
  const [pay, setPay] = useState('vietqr')
  const [phone, setPhone] = useState('')
  const [name, setName] = useState(user?.name || '')
  const [email, setEmail] = useState(user?.email || '')
  const [note, setNote] = useState('')
  const [customerType, setCustomerType] = useState<'personal' | 'company'>('personal')
  const [identityNumber, setIdentityNumber] = useState('')
  const [invoiceEmail, setInvoiceEmail] = useState(user?.email || '')
  const [companyName, setCompanyName] = useState('')
  const [taxCode, setTaxCode] = useState('')
  const [companyAddress, setCompanyAddress] = useState('')
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

  if (!user) {
    return (
      <main className="mx-auto max-w-7xl px-5 py-16 md:px-8">
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

        <div className="mx-auto max-w-lg rounded-2xl border border-border bg-card p-8 text-center shadow-2xl">
          <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-primary/10 text-primary">
            <User size={28} />
          </div>
          <h1 className="mt-5 font-display text-2xl font-black">Yêu cầu đăng nhập</h1>
          <p className="mt-2 text-sm text-muted-foreground leading-relaxed">
            Bạn cần đăng nhập tài khoản trước khi nạp số dư để hệ thống có thể cộng tiền và cấp API Key chính xác vào tài khoản của bạn.
          </p>
          <div className="mt-6 flex flex-col sm:flex-row gap-3 justify-center">
            <button
              onClick={openLoginModal}
              className="glow-button rounded-md bg-primary px-6 py-3 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02]"
            >
              Đăng nhập ngay
            </button>
            <button
              onClick={() => onNavigate('home')}
              className="glow-button-secondary rounded-md border border-border bg-secondary px-6 py-3 text-sm font-semibold text-secondary-foreground hover:border-primary/60"
            >
              Xem các gói khác
            </button>
          </div>
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
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

      <form onSubmit={handleSubmit} className="overflow-hidden rounded-xl border border-border bg-card shadow-2xl">
        <div className="grid lg:grid-cols-3 divide-y lg:divide-y-0 lg:divide-x divide-border">
          {/* Cột 1: Thông tin khách hàng */}
          <div className="p-6 md:p-8 flex flex-col justify-between space-y-6">
            <div>
              <h2 className="font-display text-lg font-bold">1. Thông tin khách hàng & Hóa đơn</h2>
              <p className="text-xs text-muted-foreground mt-1">Thông tin kích hoạt tài khoản và nhận hóa đơn VAT điện tử</p>
              
              <div className="mt-6 space-y-4">
                {/* Chọn đối tượng khách hàng - Tab Tone Màu Đen không viền */}
                <div>
                  <span className="block text-xs font-semibold text-muted-foreground mb-2">
                    Đối tượng xuất hóa đơn VAT (10%)
                  </span>
                  <div className="flex rounded-xl bg-black/80 p-1.5 gap-1.5 shadow-inner">
                    <button
                      type="button"
                      onClick={() => setCustomerType('personal')}
                      className={`flex-1 rounded-lg py-2.5 text-xs font-bold ${
                        customerType === 'personal'
                          ? 'bg-gradient-to-b from-neutral-800 to-neutral-950 text-white shadow-md'
                          : 'text-neutral-400 hover:text-neutral-200'
                      }`}
                    >
                      Cá nhân
                    </button>
                    <button
                      type="button"
                      onClick={() => setCustomerType('company')}
                      className={`flex-1 rounded-lg py-2.5 text-xs font-bold ${
                        customerType === 'company'
                          ? 'bg-gradient-to-b from-neutral-800 to-neutral-950 text-white shadow-md'
                          : 'text-neutral-400 hover:text-neutral-200'
                      }`}
                    >
                      Doanh nghiệp / Công ty
                    </button>
                  </div>
                </div>

                {/* Số điện thoại / Zalo (Chung cho cả 2) */}
                <div>
                  <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                    Số điện thoại / Zalo <span className="text-primary">*</span>
                    <input
                      type="tel"
                      required
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      placeholder="0908888888"
                      className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                    />
                  </label>
                </div>

                {customerType === 'personal' ? (
                  <>
                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Số CCCD / CMND <span className="text-primary">*</span>
                        <input
                          type="text"
                          required
                          value={identityNumber}
                          onChange={(e) => setIdentityNumber(e.target.value)}
                          placeholder="079099xxxxxx"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>

                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Họ và tên cá nhân
                        <input
                          type="text"
                          value={name}
                          onChange={(e) => setName(e.target.value)}
                          placeholder="Nguyễn Văn A"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>

                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Email nhận hóa đơn & API Key <span className="text-primary">*</span>
                        <input
                          type="email"
                          required
                          value={email}
                          onChange={(e) => {
                            setEmail(e.target.value)
                            setInvoiceEmail(e.target.value)
                          }}
                          placeholder="ban@gmail.com"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>
                  </>
                ) : (
                  <>
                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Mã số thuế (MST) <span className="text-primary">*</span>
                        <input
                          type="text"
                          required
                          value={taxCode}
                          onChange={(e) => setTaxCode(e.target.value)}
                          placeholder="0312345678"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>

                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Tên công ty / Doanh nghiệp <span className="text-primary">*</span>
                        <input
                          type="text"
                          required
                          value={companyName}
                          onChange={(e) => setCompanyName(e.target.value)}
                          placeholder="Công ty TNHH Công Nghệ..."
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>

                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Địa chỉ công ty xuất hóa đơn <span className="text-primary">*</span>
                        <input
                          type="text"
                          required
                          value={companyAddress}
                          onChange={(e) => setCompanyAddress(e.target.value)}
                          placeholder="Số 123 Đường ABC, Quận 1, TP. Hồ Chí Minh"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>

                    <div>
                      <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        Email nhận hóa đơn công ty <span className="text-primary">*</span>
                        <input
                          type="email"
                          required
                          value={email}
                          onChange={(e) => {
                            setEmail(e.target.value)
                            setInvoiceEmail(e.target.value)
                          }}
                          placeholder="ketoan@congty.com"
                          className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                        />
                      </label>
                    </div>
                  </>
                )}

                <div>
                  <label className="block text-xs font-medium uppercase tracking-wider text-muted-foreground">
                    Ghi chú
                    <textarea
                      rows={2}
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      placeholder="Model cần tư vấn hoặc ghi chú thêm..."
                      className="mt-1.5 w-full rounded-lg border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
                    />
                  </label>
                </div>
              </div>
            </div>
          </div>

          {/* Cột 2: Quét mã VietQR */}
          <div className="p-6 md:p-8 flex flex-col justify-between space-y-6">
            <div>
              <h2 className="font-display text-lg font-bold">2. Thanh toán VietQR</h2>
              <p className="text-xs text-muted-foreground mt-1">Quét mã bằng ứng dụng ngân hàng bất kỳ để thanh toán</p>
              <div className="mt-6 flex flex-col items-center justify-center">
                <QrMock
                  amount={Math.round(topup.amount * 1.1)}
                  memo={user?.customerCode || (user?.id ? `MITO${String(user.id).padStart(6, '0')}` : 'MITO')}
                />
              </div>
            </div>
            <p className="text-center text-xs text-muted-foreground font-mono">
              Hệ thống tự động ghi nhận và cộng tiền 24/7
            </p>
          </div>

          {/* Cột 3: Tóm tắt đơn nạp */}
          <div className="p-6 md:p-8 flex flex-col justify-between bg-secondary/10 space-y-6">
            <div>
              <h2 className="font-display text-lg font-bold">3. Tóm tắt đơn nạp</h2>
              <p className="text-xs text-muted-foreground mt-1">Thông tin chi tiết đơn hàng của bạn</p>

              {/* Bảng chi tiết đơn hàng - Phẳng, không viền, không padding thừa */}
              <div className="mt-6 space-y-4">
                <div className="space-y-3 text-sm">
                  <div className="flex justify-between items-center">
                    <span className="text-muted-foreground">Gói nạp:</span>
                    <span className="font-semibold text-foreground">{topup.label} ({formatVnd(topup.amount)})</span>
                  </div>

                  <div className="flex justify-between items-center border-t border-border/40 pt-3">
                    <span className="text-muted-foreground">Thuế VAT (10%):</span>
                    <span className="font-mono text-muted-foreground">+{formatVnd(Math.round(topup.amount * 0.1))}</span>
                  </div>
                </div>

                {/* Tổng thanh toán căn phải */}
                <div className="border-t border-border/80 pt-4 text-right">
                  <span className="block text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                    Tổng tiền cần quét mã
                  </span>
                  <span className="mt-1 block font-display text-3xl font-black text-primary font-mono">
                    {formatVnd(Math.round(topup.amount * 1.1))}
                  </span>
                  <span className="mt-0.5 block text-[11px] text-muted-foreground">
                    (Đã bao gồm thuế VAT 10%)
                  </span>
                </div>
              </div>

              {/* Ghi chú ngắn gọn */}
              <div className="mt-6 flex items-center justify-between text-xs text-muted-foreground font-mono">
                <span>Phương thức: VietQR</span>
                <span>Phí: 0đ</span>
                <span>Hạn dùng: Vĩnh viễn</span>
              </div>
            </div>
          </div>
        </div>
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

function ModelsPage({
  models,
  onNavigate,
  onTopup,
}: {
  models: ApiModel[]
  onNavigate: (p: Page) => void
  onTopup: (t: TopUp) => void
}) {
  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
      {/* Breadcrumb / Back button */}
      <div className="mb-6 flex items-center justify-between">
        <button
          onClick={() => onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
        <span className="font-mono text-xs text-muted-foreground">
          Cổng kết nối AI: <strong className="text-primary font-bold">1 Endpoint · {models.length} Model</strong>
        </span>
      </div>

      {/* Hero banner của trang Models - Không border, không padding thừa */}
      <div className="mb-8 pb-6 border-b border-border/60 relative overflow-hidden">
        <div className="pointer-events-none absolute -right-20 -top-20 h-64 w-64 rounded-full bg-primary/10 blur-3xl" />
        <div className="max-w-3xl relative z-10">
          <span className="font-mono text-xs uppercase tracking-widest text-primary font-bold">
            // Danh mục & Bảng giá Model API
          </span>
          <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-5xl">
            Toàn bộ mô hình AI sẵn sàng kết nối
          </h1>
          <p className="mt-3 text-sm leading-relaxed text-muted-foreground md:text-base">
            Tra cứu thông số, đơn giá token/lượt gọi và sao chép mã Model ID để tích hợp trực tiếp qua chuẩn OpenAI API.
          </p>
        </div>
      </div>

      {/* Models Section hiển thị toàn bộ danh sách */}
      <ModelsSection models={models} />
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
            type="button"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground cursor-pointer shrink-0"
            aria-label="Đóng"
          >
            <X size={18} />
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
  adminRoute = '/101',
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
    if (!user) {
      setIsLoginOpen(true)
      openLoginModal()
      return
    }
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
    navigate('models')
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
  } else if (page === 'guide-topup') {
    content = <GuideTopupPage onNavigate={navigate} />
  } else if (page === 'api-docs') {
    content = <ApiDocsPage onNavigate={navigate} />
  } else if (page === 'terms') {
    content = <TermsPage onNavigate={navigate} />
  } else if (page === 'privacy') {
    content = <PrivacyPage onNavigate={navigate} />
  } else if (page === 'models') {
    content = (
      <ModelsPage
        models={models}
        onNavigate={navigate}
        onTopup={startTopup}
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
              Models
            </button>
            <button onClick={() => navigate('guide-topup')} className="transition-colors hover:text-primary">
              Hướng dẫn
            </button>
            <button onClick={() => navigate('api-docs')} className="transition-colors hover:text-primary">
              Tài liệu
            </button>
          </nav>
          <div className="flex items-center gap-3">
            {user ? (
              <div className="flex items-center gap-2">
                {user.role === 'admin' && (
                  <button
                    onClick={() => setIsProfileOpen(true)}
                    className="hidden sm:flex items-center gap-1.5 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs font-bold text-amber-400 hover:bg-amber-500/20 transition-all cursor-pointer"
                    title="Mở bảng điều khiển Admin & Đồng bộ Cookie AstraFlow"
                  >
                    <span className="h-2 w-2 rounded-full bg-amber-400 animate-pulse" />
                    <span>AstraFlow Cookie</span>
                  </button>
                )}
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
              </div>
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
          <div>
            <h4 className="font-display text-sm font-bold uppercase tracking-wide">Model nổi bật</h4>
            <ul className="mt-4 space-y-2.5 text-sm text-muted-foreground">
              {['DeepSeek V3 / V4', 'GLM-5.3 Flash & Pro', 'Qwen 3.8 / Coder', 'Kling Video & Wan-AI'].map((l) => (
                <li key={l}>
                  <button onClick={goModels} className="text-left transition-colors hover:text-primary">
                    {l}
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h4 className="font-display text-sm font-bold uppercase tracking-wide">Hỗ trợ</h4>
            <ul className="mt-4 space-y-2.5 text-sm text-muted-foreground">
              <li>
                <button onClick={() => navigate('guide-topup')} className="text-left transition-colors hover:text-primary">
                  Hướng dẫn nạp tiền
                </button>
              </li>
              <li>
                <button onClick={() => navigate('api-docs')} className="text-left transition-colors hover:text-primary">
                  Tài liệu tích hợp API
                </button>
              </li>
              <li>
                <button onClick={() => navigate('terms')} className="text-left transition-colors hover:text-primary">
                  Điều khoản sử dụng
                </button>
              </li>
              <li>
                <button onClick={() => navigate('privacy')} className="text-left transition-colors hover:text-primary">
                  Bảo mật thông tin
                </button>
              </li>
            </ul>
          </div>
          <div>
            <h4 className="font-display text-sm font-bold uppercase tracking-wide">Liên hệ</h4>
            <ul className="mt-4 space-y-2.5 text-sm text-muted-foreground">
              <li>
                <a href={ZALO} target="_blank" rel="noreferrer" className="transition-colors hover:text-primary">
                  Zalo: Hỗ trợ kỹ thuật
                </a>
              </li>
              <li>
                <a href="mailto:support@mitom.ai" className="transition-colors hover:text-primary">
                  Email: support@mitom.ai
                </a>
              </li>
              <li>
                <span className="text-muted-foreground">Cộng đồng AI Việt Nam</span>
              </li>
              <li>
                <span className="text-muted-foreground">Hỗ trợ kỹ thuật 24/7</span>
              </li>
            </ul>
          </div>
        </div>
        <div className="border-t border-border">
          <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-2 px-5 py-6 text-xs text-muted-foreground md:flex-row md:px-8">
            <span>© 2026 Mì Tôm AI. Hệ thống API & Model AI hiệu năng cao.</span>
            <span className="font-mono">Made in Vietnam 🇻🇳</span>
          </div>
        </div>
      </footer>

      <OrderLookupModal isOpen={isLookupOpen} onClose={() => setIsLookupOpen(false)} />
      <UserProfileModal
        isOpen={isProfileOpen}
        onClose={() => setIsProfileOpen(false)}
        onLogout={() => navigate('home')}
      />
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

          {/* Slide Model Mới Nhất */}
          <div className="flex items-center justify-center lg:justify-end">
            <HeroModelSlider models={models} goModels={goModels} />
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

      {/* FAQ */}
      <section id="faq" className="bg-secondary/30">
        <div className="mx-auto grid max-w-7xl gap-10 px-5 py-20 md:px-8 lg:grid-cols-2">
          <div>
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Hỏi đáp</span>
            <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Câu hỏi thường gặp</h2>
            <p className="mt-4 text-muted-foreground">
              Chưa tìm thấy câu trả lời? <a href={ZALO} target="_blank" rel="noreferrer" className="font-semibold text-primary underline underline-offset-4 hover:opacity-80">Nhắn Zalo hỗ trợ ngay</a> để được đội ngũ kỹ thuật hỗ trợ.
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
