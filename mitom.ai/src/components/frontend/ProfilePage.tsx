'use client'

import React, { useState, useEffect } from 'react'
import { useAuth } from '@/context/AuthContext'
import {
  User,
  LogOut,
  Wallet,
  Shield,
  ExternalLink,
  RefreshCw,
  Lock,
  Globe,
  Gauge,
  ArrowLeft,
  ChevronLeft,
  Receipt,
  KeyRound,
  LayoutDashboard,
  SlidersHorizontal,
  Calendar,
} from 'lucide-react'

interface UsageAstraflow {
  connected: boolean
  keyName: string
  maskedKey: string
  status: string
  dailyUsedVnd: number
  monthlyUsedVnd: number
  dailyLimitVnd: number
  monthlyLimitVnd: number
  updateTime: string
  dailyHistory?: { date: string; usedVnd: number }[]
  selectedDate?: string | null
  selectedDateUsedVnd?: number | null
}

interface UsageHistoryItem {
  id: number
  orderCode: string
  planName: string
  subtotal: number
  vatAmount: number
  totalAmount: number
  invoiceNumber: string
  date: string
  status: string
}

interface UsageData {
  astraflow: UsageAstraflow
  history: UsageHistoryItem[]
  stats: { totalDeposited: number; depositCount: number }
}

const formatVnd = (n: number) => (Number(n) || 0).toLocaleString('vi-VN', { maximumFractionDigits: 2 }) + 'đ'

type ProfileTab = 'overview' | 'config' | 'history' | 'security'

const PROFILE_TABS: { id: ProfileTab; label: string; icon: React.ElementType }[] = [
  { id: 'overview', label: 'TỔNG QUAN', icon: LayoutDashboard },
  { id: 'config', label: 'CẤU HÌNH API', icon: SlidersHorizontal },
  { id: 'history', label: 'LỊCH SỬ NẠP', icon: Receipt },
  { id: 'security', label: 'BẢO MẬT', icon: Lock },
]


export function ProfilePage({ onNavigate }: { onNavigate?: (p: any) => void }) {
  const { user, logout, refreshUser } = useAuth()
  const [refreshing, setRefreshing] = useState(false)
  const [activeTab, setActiveTab] = useState<ProfileTab>('overview')

  // State AstraFlow Cookies (Admin)
  const [astraLoading, setAstraLoading] = useState(false)
  const [astraMsg, setAstraMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // State doi mat khau
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordMsg, setPasswordMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // State han muc chi tieu API
  const [limits, setLimits] = useState<{ balance: number; dailyLimit: number; monthlyLimit: number } | null>(null)
  const [limitsLoading, setLimitsLoading] = useState(false)
  const [limitsSaving, setLimitsSaving] = useState(false)
  const [dailyInput, setDailyInput] = useState('')
  const [monthlyInput, setMonthlyInput] = useState('')
  const [limitsMsg, setLimitsMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // Muc tieu thu API + lich su nap
  const [usage, setUsage] = useState<UsageData | null>(null)
  const [usageLoading, setUsageLoading] = useState(false)

  const loadLimits = async () => {
    setLimitsLoading(true)
    try {
      const res = await fetch('/api/account/limits', { cache: 'no-store' })
      const data = await res.json()
      if (res.ok && data.success) {
        setLimits({ balance: data.balance, dailyLimit: data.dailyLimit, monthlyLimit: data.monthlyLimit })
        setDailyInput(String(data.dailyLimit ?? 0))
        setMonthlyInput(String(data.monthlyLimit ?? 0))
      }
    } catch {
      // bo qua loi mang tam thoi
    } finally {
      setLimitsLoading(false)
    }
  }

  const [selectedCustomDate, setSelectedCustomDate] = useState<string>('')
  const [customDateLoading, setCustomDateLoading] = useState(false)

  const loadUsage = async (targetDate?: string) => {
    if (targetDate) {
      setCustomDateLoading(true)
    } else {
      setUsageLoading(true)
    }
    try {
      const url = targetDate ? `/api/user/usage?date=${encodeURIComponent(targetDate)}` : '/api/user/usage'
      const res = await fetch(url, { cache: 'no-store' })
      const data = await res.json()
      if (res.ok && data.success) {
        setUsage({ astraflow: data.astraflow, history: data.history || [], stats: data.stats })
      }
    } catch {
      // bo qua loi mang tam thoi
    } finally {
      setUsageLoading(false)
      setCustomDateLoading(false)
    }
  }

  const handleCustomDateChange = (newDate: string) => {
    setSelectedCustomDate(newDate)
    if (newDate) {
      loadUsage(newDate)
    } else {
      loadUsage()
    }
  }

  const reloadAll = async () => {
    await Promise.all([loadLimits(), loadUsage(selectedCustomDate || undefined)])
  }

  useEffect(() => {
    if (!user) return
    reloadAll()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id])

  const handleSaveLimits = async () => {
    setLimitsSaving(true)
    setLimitsMsg(null)
    const curBalance = limits?.balance ?? user?.balance ?? 0
    const dVal = Number(dailyInput) || 0
    const mVal = Number(monthlyInput) || 0

    if (dVal > curBalance) {
      setLimitsMsg({
        type: 'error',
        text: `Hạn mức ngày (${formatVnd(dVal)}) không được vượt quá số dư hiện có (${formatVnd(curBalance)}).`,
      })
      setLimitsSaving(false)
      return
    }

    if (mVal > curBalance) {
      setLimitsMsg({
        type: 'error',
        text: `Hạn mức tháng (${formatVnd(mVal)}) không được vượt quá số dư hiện có (${formatVnd(curBalance)}).`,
      })
      setLimitsSaving(false)
      return
    }

    try {
      const res = await fetch('/api/account/limits', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dailyLimit: dVal, monthlyLimit: mVal }),
      })
      const data = await res.json()
      if (res.ok && data.success) {
        setLimits({ balance: data.balance, dailyLimit: data.dailyLimit, monthlyLimit: data.monthlyLimit })
        setLimitsMsg({ type: 'success', text: data.message || 'Đã lưu hạn mức thành công.' })
        refreshUser()
        loadUsage()
      } else {
        setLimitsMsg({ type: 'error', text: data.error || 'Lưu hạn mức thất bại.' })
      }
    } catch (e: any) {
      setLimitsMsg({ type: 'error', text: e.message || 'Lỗi kết nối máy chủ.' })
    } finally {
      setLimitsSaving(false)
    }
  }

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault()
    setPasswordMsg(null)

    if (newPassword.length < 6) {
      setPasswordMsg({ type: 'error', text: 'Mật khẩu mới phải có tối thiểu 6 ký tự.' })
      return
    }
    if (newPassword !== confirmPassword) {
      setPasswordMsg({ type: 'error', text: 'Mật khẩu xác nhận không khớp.' })
      return
    }

    setPasswordLoading(true)
    try {
      const res = await fetch('/api/auth/change-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ currentPassword, newPassword }),
      })
      const data = await res.json()
      if (!res.ok || !data.success) {
        setPasswordMsg({ type: 'error', text: data.message || 'Đổi mật khẩu thất bại.' })
      } else {
        setPasswordMsg({ type: 'success', text: 'Đổi mật khẩu thành công!' })
        setCurrentPassword('')
        setNewPassword('')
        setConfirmPassword('')
        setTimeout(() => setPasswordMsg(null), 2500)
      }
    } catch (err: any) {
      setPasswordMsg({ type: 'error', text: err.message || 'Lỗi mạng khi đổi mật khẩu.' })
    } finally {
      setPasswordLoading(false)
    }
  }

  const handleRefreshBalance = async () => {
    setRefreshing(true)
    await refreshUser()
    setRefreshing(false)
  }

  const handleLogout = async () => {
    await logout()
    if (onNavigate) {
      onNavigate('home')
    } else {
      window.location.href = '/'
    }
  }

  if (!user) {
    return (
      <div className="mx-auto flex max-w-3xl flex-col items-center justify-center gap-4 px-5 py-24 text-center">
        <User size={40} className="text-muted-foreground" />
        <h2 className="font-display text-xl font-bold text-foreground">Chưa đăng nhập</h2>
        <p className="text-sm text-muted-foreground">Vui lòng đăng nhập để xem trang tài khoản cá nhân.</p>
        <button
          type="button"
          onClick={() => (onNavigate ? onNavigate('home') : (window.location.href = '/'))}
          className="glow-button rounded-md bg-primary px-6 py-2.5 text-sm font-bold text-primary-foreground transition-all hover:scale-[1.02] cursor-pointer"
        >
          Về trang chủ
        </button>
      </div>
    )
  }

  return (
    <div className="mx-auto w-full max-w-7xl px-5 py-8 md:px-8">
      {/* Nut quay lai */}
      <div className="mb-6 flex items-center justify-between">
        <button
          type="button"
          onClick={() => onNavigate && onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors cursor-pointer"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
      </div>

      {/* Header ho so - khong border, khong padding */}
      <div className="mb-8 flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-4">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary/20 text-primary font-display text-2xl font-bold overflow-hidden">
            {user.avatar ? (
              <img src={user.avatar} alt={user.name || user.email} className="h-full w-full object-cover" />
            ) : (
              (user.name || user.email).charAt(0).toUpperCase()
            )}
          </div>
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="font-display text-xl font-bold text-foreground md:text-2xl">
                {user.name || 'Người dùng Mì Tôm AI'}
              </h1>
              {user.role === 'admin' && (
                <span className="rounded bg-amber-500/15 px-2 py-0.5 font-mono text-[10px] font-bold text-amber-400">
                  ADMIN
                </span>
              )}
            </div>
            <p className="text-sm text-muted-foreground">{user.email}</p>
            <div className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
              <Shield size={12} className="text-primary" />
              <span>Mã khách hàng:</span>
              <span className="font-mono font-bold text-primary select-all">{user.customerCode || '---'}</span>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div>
            <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
              <span className="flex items-center gap-1.5 font-medium">
                <Wallet size={14} className="text-emerald" />
                Số dư API
              </span>
              <button
                onClick={handleRefreshBalance}
                disabled={refreshing}
                className="flex items-center gap-1 rounded border border-border/60 bg-secondary/40 px-2 py-1 text-xs text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors cursor-pointer"
                title="Làm mới số dư"
              >
                <RefreshCw size={13} className={refreshing ? 'animate-spin text-primary' : ''} />
                <span>Làm mới</span>
              </button>
            </div>
            <div className="mt-0.5 font-display text-2xl font-extrabold text-emerald">{formatVnd(user.balance || 0)}</div>
          </div>
        </div>
      </div>

      {/* Tabs dieu huong 3D skeuomorphic */}
      <div className="mb-8 overflow-x-auto no-scrollbar py-1">
        <div className="skeuo-tabs-bar">
          {PROFILE_TABS.map((t) => {
            const Icon = t.icon
            const active = activeTab === t.id
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => setActiveTab(t.id)}
                className={`skeuo-tab-item ${active ? 'active' : ''}`}
              >
                <Icon size={14} className={active ? 'text-white' : 'text-neutral-400'} />
                <span>{t.label}</span>
              </button>
            )
          })}
        </div>
      </div>

      {/* Tab: overview */}
      {activeTab === 'overview' && (
        <div className="space-y-6">
          {/* Muc tieu thu API AstraFlow - khong border, khong padding card */}
          <section>
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <h2 className="flex items-center gap-2 font-display text-base font-bold text-foreground">
                <Gauge size={17} className="text-primary" />
                Mức tiêu thụ API
              </h2>
              <div className="flex items-center gap-2">
                <label className="relative inline-flex items-center gap-2 rounded-lg border border-border bg-secondary/80 px-3 py-1.5 hover:border-primary/60 transition-colors cursor-pointer">
                  <Calendar size={15} className="text-primary shrink-0 pointer-events-none" />
                  <span className="font-mono text-sm text-foreground select-none pointer-events-none">
                    {selectedCustomDate || 'mm/dd/yyyy'}
                  </span>
                  <input
                    type="date"
                    title="Bấm để chọn ngày tháng năm"
                    value={selectedCustomDate}
                    onClick={(e) => {
                      try {
                        ;(e.currentTarget as any).showPicker?.()
                      } catch {}
                    }}
                    onChange={(e) => handleCustomDateChange(e.target.value)}
                    className="absolute inset-0 h-full w-full opacity-0 cursor-pointer z-10"
                  />
                </label>
              </div>
            </div>

            {usage?.astraflow?.connected ? (
              <div className="space-y-4">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div className="rounded-xl border border-border bg-secondary/30 p-4">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs text-muted-foreground">
                        {selectedCustomDate ? `Tiêu thụ ngày ${selectedCustomDate}` : 'Tiêu thụ hôm nay'}
                      </span>
                      {selectedCustomDate && (
                        <button
                          type="button"
                          onClick={() => handleCustomDateChange('')}
                          className="rounded border border-primary/40 bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary hover:bg-primary hover:text-primary-foreground transition-all cursor-pointer"
                        >
                          Về hôm nay
                        </button>
                      )}
                    </div>
                    <div className="font-display text-lg font-bold text-foreground">
                      {customDateLoading ? (
                        <div className="flex items-center gap-2 py-0.5">
                          <span className="spinner-modern-primary" />
                          <span className="loading-shimmer-bar" />
                        </div>
                      ) : (
                        formatVnd(selectedCustomDate ? (usage.astraflow.selectedDateUsedVnd ?? 0) : (usage.astraflow.dailyUsedVnd || 0))
                      )}
                    </div>
                    <div className="mt-1 text-[11px] text-muted-foreground">
                      Hạn mức: {formatVnd(usage.astraflow.dailyLimitVnd || 0)}
                    </div>
                  </div>
                  <div className="rounded-xl border border-border bg-secondary/30 p-4">
                    <div className="mb-1 text-xs text-muted-foreground">Tiêu thụ tháng này</div>
                    <div className="font-display text-lg font-bold text-foreground">
                      {formatVnd(usage.astraflow.monthlyUsedVnd || 0)}
                    </div>
                    <div className="mt-1 text-[11px] text-muted-foreground">
                      Hạn mức: {formatVnd(usage.astraflow.monthlyLimitVnd || 0)}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Chưa phát hiện API Key hoạt động.</p>
            )}
          </section>

        </div>
      )}

      {/* Tab: config */}
      {activeTab === 'config' && (
        <div className="space-y-8">
          {/* Han muc chi tieu API - khong border, khong padding card, max-w-sm can giua giong form doi mat khau */}
          <section className="max-w-sm mx-auto">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="flex items-center gap-2 font-display text-base font-bold text-foreground">
                <Gauge size={17} className="text-primary" />
                Hạn mức chi tiêu API
              </h2>
              <span className="font-mono text-[11px] text-muted-foreground">
                Số dư: {formatVnd(limits?.balance ?? user.balance ?? 0)}
              </span>
            </div>

            <div className="space-y-4">
              <div>
                <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
                  Hạn mức ngày (VNĐ)
                </label>
                <input
                  type="number"
                  min={0}
                  max={limits?.balance ?? user?.balance ?? 0}
                  value={dailyInput}
                  onChange={(e) => setDailyInput(e.target.value)}
                  placeholder="0 = theo số dư"
                  className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
                  Hạn mức tháng (VNĐ)
                </label>
                <input
                  type="number"
                  min={0}
                  max={limits?.balance ?? user?.balance ?? 0}
                  value={monthlyInput}
                  onChange={(e) => setMonthlyInput(e.target.value)}
                  placeholder="0 = theo số dư"
                  className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                />
              </div>
            </div>

            <p className="mt-3 text-[11px] leading-relaxed text-muted-foreground">
              Nhập 0 để dùng toàn bộ số dư. Hạn mức ngày và tháng không được vượt quá số dư tài khoản hiện có.
            </p>

            {limitsMsg && (
              <div
                className={`mt-3 rounded-lg p-3 text-xs font-medium ${
                  limitsMsg.type === 'success'
                    ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                    : 'border border-rose-500/30 bg-rose-500/10 text-rose-400'
                }`}
              >
                {limitsMsg.text}
              </div>
            )}

            <button
              type="button"
              onClick={handleSaveLimits}
              disabled={limitsSaving || limitsLoading}
              className="glow-button mt-4 w-full rounded-md py-3 text-sm font-bold bg-primary text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
            >
              {limitsSaving ? (
                <span className="flex items-center justify-center gap-2">
                  <span className="spinner-modern" />
                  <span>Đang lưu hạn mức</span>
                  <span className="loading-dots-wave">
                    <span />
                    <span />
                    <span />
                  </span>
                </span>
              ) : (
                'Lưu hạn mức'
              )}
            </button>
          </section>


          {/* Dong bo Cookie AstraFlow (Admin) */}
          {user.role === 'admin' && (
            <section>
              <div className="mb-3 flex items-center justify-between">
                <h2 className="flex items-center gap-2 font-display text-base font-bold text-foreground">
                  <Globe size={17} className="text-primary" />
                  Đồng bộ Cookies AstraFlow
                </h2>
                <span className="font-mono text-[11px] text-muted-foreground">passport.scloudsg.com</span>
              </div>
              <p className="text-xs leading-relaxed text-muted-foreground">
                Bấm để mở trình duyệt đăng nhập tài khoản tại{' '}
                <code className="font-mono text-primary">https://passport.scloudsg.com/</code>. Hệ thống sẽ tự động
                bắt và làm mới toàn bộ cookies vào tệp hệ thống.
              </p>

              {astraMsg && (
                <div
                  className={`mt-3 rounded-lg p-3 text-xs ${
                    astraMsg.type === 'success'
                      ? 'border border-emerald/30 bg-emerald/10 text-emerald'
                      : 'border border-rose-500/30 bg-rose-500/10 text-rose-300'
                  }`}
                >
                  {astraMsg.text}
                </div>
              )}

              <button
                type="button"
                disabled={astraLoading}
                onClick={async () => {
                  setAstraLoading(true)
                  setAstraMsg(null)
                  try {
                    const res = await fetch('/api/admin/astraflow/sync-browser', { method: 'POST' })
                    const data = await res.json()
                    if (data.success) {
                      setAstraMsg({
                        type: 'success',
                        text: data.message || 'Đã mở cửa sổ đăng nhập Chrome tại https://passport.scloudsg.com/.',
                      })
                    } else {
                      setAstraMsg({
                        type: 'error',
                        text: data.error || 'Lỗi khi kích hoạt cửa sổ đăng nhập.',
                      })
                    }
                  } catch (e: any) {
                    setAstraMsg({ type: 'error', text: e.message || 'Lỗi kết nối máy chủ.' })
                  } finally {
                    setAstraLoading(false)
                  }
                }}
                className="glow-button mt-4 flex w-full items-center justify-center gap-2 rounded-md bg-primary py-3 text-sm font-bold text-primary-foreground transition-all hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
              >
                {astraLoading ? (
                  <span className="flex items-center gap-1.5">
                    <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-black border-t-transparent" />
                    Đang kích hoạt...
                  </span>
                ) : (
                  <>
                    <ExternalLink size={14} />
                    <span>Đăng nhập AstraFlow</span>
                  </>
                )}
              </button>
            </section>
          )}
        </div>
      )}

      {/* Tab: history */}
      {activeTab === 'history' && (
        <div className="space-y-6">
          {/* Lich su nap so du */}
          <section>
            <div className="mb-4 flex items-center justify-between">
              <h2 className="flex items-center gap-2 font-display text-base font-bold text-foreground">
                <Receipt size={17} className="text-primary" />
                Lịch sử nạp số dư
              </h2>
              {usage?.stats && (
                <span className="text-[11px] text-muted-foreground">
                  Tổng nạp:{' '}
                  <span className="font-bold text-emerald">{formatVnd(usage.stats.totalDeposited || 0)}</span>
                  {' · '}
                  {usage.stats.depositCount} lần
                </span>
              )}
            </div>

            {usage && usage.history.length > 0 ? (
              <div className="overflow-hidden rounded-xl border border-border/70">
                {/* Header bang */}
                <div className="hidden grid-cols-[1.6fr_1fr_1.1fr_0.9fr] gap-2 border-b border-border/70 bg-secondary/40 px-4 py-2.5 text-[11px] font-semibold text-muted-foreground md:grid">
                  <span>Gói nạp</span>
                  <span className="text-right">Số tiền</span>
                  <span>Mã hóa đơn / Đơn</span>
                  <span className="text-right">Trạng thái</span>
                </div>
                <div className="max-h-[420px] divide-y divide-border/60 overflow-y-auto">
                  {usage.history.map((h) => (
                    <div
                      key={h.id}
                      className="grid grid-cols-1 gap-2 px-4 py-3 transition-colors hover:bg-secondary/20 md:grid-cols-[1.6fr_1fr_1.1fr_0.9fr] md:items-center"
                    >
                      <div className="min-w-0">
                        <div className="truncate text-xs font-bold text-foreground">{h.planName}</div>
                        <div className="text-[10px] text-muted-foreground">
                          {new Date(h.date).toLocaleString('vi-VN')}
                        </div>
                      </div>
                      <div className="text-left md:text-right">
                        <div className="font-display text-sm font-bold text-emerald">+{formatVnd(h.subtotal || 0)}</div>
                        <div className="text-[10px] text-muted-foreground">
                          TT: {formatVnd(h.totalAmount || 0)} (VAT {formatVnd(h.vatAmount || 0)})
                        </div>
                      </div>
                      <div className="min-w-0 font-mono text-[10px] text-muted-foreground">
                        <div className="truncate text-primary">{h.invoiceNumber}</div>
                        <div className="truncate">{h.orderCode}</div>
                      </div>
                      <div className="md:text-right">
                        <span
                          className={`inline-block rounded px-2 py-0.5 text-[10px] font-semibold ${
                            h.status === 'paid'
                              ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                              : 'border border-amber-500/30 bg-amber-500/10 text-amber-400'
                          }`}
                        >
                          {h.status === 'paid' ? 'Đã thanh toán' : h.status}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Chưa có lịch sử nạp số dư nào.</p>
            )}
          </section>
        </div>
      )}

      {/* Tab: security */}
      {activeTab === 'security' && (
        <div className="space-y-6">
          {/* Doi mat khau */}
          <section className="max-w-sm mx-auto">
            <h2 className="mb-4 flex items-center gap-2 font-display text-base font-bold text-foreground">
              <Lock size={17} className="text-primary" />
              {user.authProvider === 'google' || user.googleId ? 'Hướng dẫn đăng nhập' : 'Thay đổi mật khẩu'}
            </h2>

            {passwordMsg && (
              <div
                className={`mb-4 rounded-xl p-3 text-xs font-medium ${
                  passwordMsg.type === 'success'
                    ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                    : 'border border-rose-500/30 bg-rose-500/10 text-rose-400'
                }`}
              >
                {passwordMsg.text}
              </div>
            )}

            <form onSubmit={handleChangePassword} className="max-w-sm space-y-4">
              {user.authProvider === 'google' || user.googleId ? (
                <div className="rounded-xl border border-primary/20 bg-primary/5 p-2.5 text-xs text-muted-foreground">
                  Tài khoản được liên kết với Google. Bạn có thể thiết lập mật khẩu tại đây để đăng nhập trực tiếp bằng email và mật khẩu khi cần.
                </div>
              ) : (
                <div>
                  <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
                    Mật khẩu hiện tại
                  </label>
                  <div className="relative">
                    <Lock size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                    <input
                      type="password"
                      required
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      placeholder="••••••••"
                      className="w-full rounded-md border border-border bg-secondary/40 py-2 pl-10 pr-3 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                    />
                  </div>
                </div>
              )}

              <div>
                <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
                  Mật khẩu mới (tối thiểu 6 ký tự)
                </label>
                <div className="relative">
                  <Lock size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="password"
                    required
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-md border border-border bg-secondary/40 py-2 pl-10 pr-3 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
                  Xác nhận mật khẩu mới
                </label>
                <div className="relative">
                  <Lock size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="password"
                    required
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-md border border-border bg-secondary/40 py-2 pl-10 pr-3 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={passwordLoading}
                className="glow-button w-full rounded-md py-3 text-sm font-bold bg-primary text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
              >
                {passwordLoading ? (
                  <span className="flex items-center justify-center gap-2">
                    <span className="spinner-modern" />
                    <span>Đang cập nhật</span>
                    <span className="loading-dots-wave">
                      <span />
                      <span />
                      <span />
                    </span>
                  </span>
                ) : user.authProvider === 'google' || user.googleId ? (
                  'Thiết lập mật khẩu'
                ) : (
                  'Lưu mật khẩu mới'
                )}
              </button>
            </form>
          </section>

        </div>
      )}

      {/* Dang xuat - cuoi trang */}
      <div className="mt-10 flex flex-col items-center gap-3 border-t border-border pt-8 pb-4">
        <button
          type="button"
          onClick={handleLogout}
          className="flex items-center gap-2 rounded-lg border border-border/80 bg-secondary/30 px-5 py-2.5 text-sm font-semibold text-muted-foreground hover:border-rose-500/40 hover:bg-rose-500/10 hover:text-rose-400 transition-all cursor-pointer"
        >
          <LogOut size={16} />
          <span>Đăng xuất tài khoản</span>
        </button>
        <p className="text-xs text-muted-foreground">Mì Tôm AI — Số dư và dữ liệu của bạn được bảo toàn sau khi đăng xuất.</p>
      </div>
    </div>
  )
}
