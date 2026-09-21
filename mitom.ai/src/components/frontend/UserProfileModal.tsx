'use client'

import React, { useState, useEffect } from 'react'
import { useAuth } from '@/context/AuthContext'
import { User, LogOut, Wallet, Shield, ExternalLink, RefreshCw, X, Lock, ChevronDown, ChevronUp, Globe, Gauge, Calendar } from 'lucide-react'


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

export function UserProfileModal({
  isOpen,
  onClose,
  onLogout,
}: {
  isOpen: boolean
  onClose: () => void
  onLogout?: () => void
}) {
  const { user, logout, refreshUser } = useAuth()
  const [refreshing, setRefreshing] = useState(false)

  // State AstraFlow Cookies
  const [astraLoading, setAstraLoading] = useState(false)
  const [astraMsg, setAstraMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // State đổi mật khẩu
  const [showChangePassword, setShowChangePassword] = useState(false)
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordMsg, setPasswordMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // State hạn mức chi tiêu API
  const [limits, setLimits] = useState<{ balance: number; dailyLimit: number; monthlyLimit: number } | null>(null)
  const [limitsLoading, setLimitsLoading] = useState(false)
  const [limitsSaving, setLimitsSaving] = useState(false)
  const [dailyInput, setDailyInput] = useState('')
  const [monthlyInput, setMonthlyInput] = useState('')
  const [limitsMsg, setLimitsMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // Tải hạn mức + số dư mỗi khi mở modal
  useEffect(() => {
    if (!isOpen) return
    let cancelled = false
    const load = async () => {
      setLimitsLoading(true)
      setLimitsMsg(null)
      try {
        const res = await fetch('/api/account/limits', { cache: 'no-store' })
        const data = await res.json()
        if (!cancelled && res.ok && data.success) {
          setLimits({ balance: data.balance, dailyLimit: data.dailyLimit, monthlyLimit: data.monthlyLimit })
          setDailyInput(String(data.dailyLimit ?? 0))
          setMonthlyInput(String(data.monthlyLimit ?? 0))
        }
      } catch {
        // bo qua loi mang tam thoi
      } finally {
        if (!cancelled) setLimitsLoading(false)
      }
    }
    load()
    return () => {
      cancelled = true
    }
  }, [isOpen])

  // ===== Muc tieu thu API AstraFlow + Lich su nap so du =====
  const [usage, setUsage] = useState<UsageData | null>(null)
  const [usageLoading, setUsageLoading] = useState(false)
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

  useEffect(() => {
    if (!isOpen) return
    loadUsage()
  }, [isOpen])

  const handleCustomDateChange = (newDate: string) => {
    setSelectedCustomDate(newDate)
    if (newDate) {
      loadUsage(newDate)
    } else {
      loadUsage()
    }
  }

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
        handleReloadUsage()
      } else {
        setLimitsMsg({ type: 'error', text: data.error || 'Lưu hạn mức thất bại.' })
      }
    } catch (e: any) {
      setLimitsMsg({ type: 'error', text: e.message || 'Lỗi kết nối máy chủ.' })
    } finally {
      setLimitsSaving(false)
    }
  }



  if (!isOpen || !user) return null

  const handleReloadUsage = async () => {
    setUsageLoading(true)
    try {
      const res = await fetch('/api/user/usage', { cache: 'no-store' })
      const data = await res.json()
      if (res.ok && data.success) {
        setUsage({ astraflow: data.astraflow, history: data.history || [], stats: data.stats })
      }
    } catch {
      // bo qua loi mang tam thoi
    } finally {
      setUsageLoading(false)
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
        setTimeout(() => {
          setShowChangePassword(false)
          setPasswordMsg(null)
        }, 1500)
      }
    } catch (err: any) {
      setPasswordMsg({ type: 'error', text: err.message || 'Lỗi mạng khi đổi mật khẩu.' })
    } finally {
      setPasswordLoading(false)
    }
  }

  const handleRefresh = async () => {
    setRefreshing(true)
    await refreshUser()
    setRefreshing(false)
  }

  const formatVnd = (n: number) => (Number(n) || 0).toLocaleString('vi-VN', { maximumFractionDigits: 2 }) + 'đ'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md animate-in fade-in duration-200">
      <div
        className="relative w-full max-w-lg overflow-hidden rounded-lg border border-border bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/20 text-primary font-bold text-base overflow-hidden border border-primary/30">
              {user.avatar ? (
                <img src={user.avatar} alt={user.name || user.email} className="h-full w-full object-cover" />
              ) : (
                (user.name || user.email).charAt(0).toUpperCase()
              )}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-display text-base font-bold text-foreground">
                  {user.name || 'Người dùng Mì Tôm AI'}
                </h3>
                {user.role === 'admin' && (
                  <span className="rounded bg-amber-500/15 border border-amber-500/30 px-2 py-0.5 font-mono text-[10px] font-bold text-amber-400">
                    ADMIN
                  </span>
                )}
              </div>
              <p className="text-xs text-muted-foreground">{user.email}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground cursor-pointer shrink-0"
            aria-label="Đóng"
          >
            <X size={18} />
          </button>
        </div>

        {/* Body */}
        <div className="p-6 space-y-5">
          {/* Badge phương thức và số dư */}
          {/* Badge phương thức, mã khách hàng và số dư */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-lg border border-border bg-secondary/30 p-3.5">
              <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1">
                <Shield size={14} className="text-primary" />
                <span>Mã khách hàng</span>
              </div>
              <div className="text-sm font-bold text-primary font-mono select-all">
                {user.customerCode || '---'}
              </div>
            </div>

            <div className="rounded-lg border border-border bg-secondary/30 p-3.5">
              <div className="flex items-center justify-between text-xs text-muted-foreground mb-1">
                <span className="flex items-center gap-2">
                  <Wallet size={14} className="text-emerald" />
                  Số dư API
                </span>
                <button
                  onClick={handleRefresh}
                  disabled={refreshing}
                  className="hover:text-primary transition-colors"
                  title="Làm mới số dư"
                >
                  <RefreshCw size={12} className={refreshing ? 'animate-spin' : ''} />
                </button>
              </div>
              <div className="text-base font-extrabold text-emerald font-display">
                {formatVnd(user.balance || 0)}
              </div>
            </div>
          </div>

          {/* Hạn mức chi tiêu API (tự điều chỉnh) */}
          <div className="rounded-lg border border-border bg-secondary/40 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-foreground">
                <Gauge size={14} className="text-primary" />
                Hạn mức chi tiêu API
              </div>
              <span className="text-[11px] text-muted-foreground font-mono">
                Số dư: {formatVnd(limits?.balance ?? user.balance ?? 0)}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                  Hạn mức ngày (VNĐ)
                </label>
                <input
                  type="number"
                  min={0}
                  max={limits?.balance ?? user.balance ?? 0}
                  value={dailyInput}
                  onChange={(e) => setDailyInput(e.target.value)}
                  placeholder="0 = theo số dư"
                  className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                  Hạn mức tháng (VNĐ)
                </label>
                <input
                  type="number"
                  min={0}
                  max={limits?.balance ?? user.balance ?? 0}
                  value={monthlyInput}
                  onChange={(e) => setMonthlyInput(e.target.value)}
                  placeholder="0 = theo số dư"
                  className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Nhập 0 để dùng toàn bộ số dư. Hạn mức ngày và tháng không được vượt quá số dư tài khoản hiện có.
            </p>
            {limitsMsg && (
              <div
                className={`rounded-lg p-3 text-xs font-medium ${
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
              className="glow-button w-full rounded-md py-3 text-sm font-bold bg-primary text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50 cursor-pointer mt-2"
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
          </div>

          {/* Muc tieu thu API AstraFlow */}
          <div className="rounded-lg border border-border bg-secondary/40 p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-foreground">
                <Gauge size={14} className="text-primary" />
                Mức tiêu thụ API
              </div>
              <div className="flex items-center gap-2">
                <div className="flex items-center gap-1 rounded border border-border/80 bg-background/80 px-2 py-0.5">
                  <input
                    type="date"
                    title="Chọn ngày để xem tiêu thụ"
                    value={selectedCustomDate}
                    onChange={(e) => handleCustomDateChange(e.target.value)}
                    className="bg-transparent text-[11px] font-mono text-foreground focus:outline-none cursor-pointer"
                  />
                  {selectedCustomDate && (
                    <button
                      type="button"
                      onClick={() => handleCustomDateChange('')}
                      className="text-muted-foreground hover:text-foreground text-[10px] ml-0.5"
                      title="Xóa chọn ngày"
                    >
                      ✕
                    </button>
                  )}
                </div>
              </div>
            </div>

            {usage?.astraflow?.connected ? (
              <div className="space-y-2.5">
                <div className="grid grid-cols-2 gap-2">
                  <div className="rounded-md border border-border bg-background/60 p-2.5">
                    <div className="text-[10px] text-muted-foreground mb-0.5">
                      {selectedCustomDate ? `Tiêu thụ ngày ${selectedCustomDate}` : 'Tiêu thụ hôm nay'}
                    </div>
                    <div className="text-sm font-bold text-foreground font-display">
                      {customDateLoading ? (
                        <div className="flex items-center gap-1.5 py-0.5">
                          <span className="spinner-modern-primary" style={{ width: '0.85rem', height: '0.85rem', borderWidth: '1.5px' }} />
                          <span className="loading-shimmer-bar" style={{ width: '4.5rem', height: '1rem' }} />
                        </div>
                      ) : (
                        formatVnd(selectedCustomDate ? (usage.astraflow.selectedDateUsedVnd || 0) : (usage.astraflow.dailyUsedVnd || 0))
                      )}
                    </div>
                    <div className="text-[10px] text-muted-foreground mt-0.5">
                      Hạn mức: {formatVnd(usage.astraflow.dailyLimitVnd || 0)}
                    </div>
                  </div>
                  <div className="rounded-md border border-border bg-background/60 p-2.5">
                    <div className="text-[10px] text-muted-foreground mb-0.5">Tiêu thụ tháng này</div>
                    <div className="text-sm font-bold text-foreground font-display">
                      {formatVnd(usage.astraflow.monthlyUsedVnd || 0)}
                    </div>
                    <div className="text-[10px] text-muted-foreground mt-0.5">
                      Hạn mức: {formatVnd(usage.astraflow.monthlyLimitVnd || 0)}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Chưa phát hiện API Key hoạt động.</p>
            )}
          </div>

          {/* Lich su nap so du */}
          <div className="rounded-lg border border-border bg-secondary/40 p-4 space-y-3">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-foreground">
              <Wallet size={14} className="text-primary" />
              Lịch sử nạp số dư
              {usage?.stats && (
                <span className="ml-auto text-[10px] font-normal text-muted-foreground">
                  Tổng nạp: <span className="font-bold text-emerald">{formatVnd(usage.stats.totalDeposited || 0)}</span>
                  {' · '}
                  {usage.stats.depositCount} lần
                </span>
              )}
            </div>

            {usage && usage.history.length > 0 ? (
              <div className="max-h-52 space-y-2 overflow-y-auto pr-1">
                {usage.history.map((h) => (
                  <div
                    key={h.id}
                    className="flex items-center justify-between gap-2 rounded-md border border-border bg-background/60 p-2.5"
                  >
                    <div className="min-w-0">
                      <div className="text-xs font-bold text-foreground truncate">{h.planName}</div>
                      <div className="text-[10px] text-muted-foreground font-mono truncate">
                        {h.invoiceNumber} · {h.orderCode}
                      </div>
                      <div className="text-[10px] text-muted-foreground">
                        {new Date(h.date).toLocaleString('vi-VN')}
                      </div>
                    </div>
                    <div className="text-right shrink-0">
                      <div className="text-sm font-bold text-emerald font-display">+{formatVnd(h.subtotal || 0)}</div>
                      <div className="text-[10px] text-muted-foreground">
                        TT: {formatVnd(h.totalAmount || 0)} (gồm VAT {formatVnd(h.vatAmount || 0)})
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Chưa có lịch sử nạp số dư nào.</p>
            )}
          </div>

          {/* Khu vực Đăng nhập & Đồng bộ Cookie AstraFlow (Chỉ dành cho Admin) */}
          {user.role === 'admin' && (
            <div className="rounded-lg border border-border bg-secondary/40 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-semibold text-foreground">
                <Globe size={15} className="text-primary" />
                <span>Đồng bộ Cookies AstraFlow</span>
              </div>
              <span className="text-[11px] text-muted-foreground font-mono">passport.scloudsg.com</span>
            </div>
            <p className="text-xs text-muted-foreground leading-relaxed">
              Bấm để mở trình duyệt đăng nhập tài khoản tại <code className="text-primary font-mono">https://passport.scloudsg.com/</code>. Hệ thống sẽ tự động bắt và làm mới toàn bộ cookies vào tệp hệ thống.
            </p>

            {astraMsg && (
              <div
                className={`rounded-lg p-3 text-xs ${
                  astraMsg.type === 'success'
                    ? 'border border-emerald/30 bg-emerald/10 text-emerald'
                    : 'border border-rose-500/30 bg-rose-500/10 text-rose-300'
                }`}
              >
                {astraMsg.text}
              </div>
            )}

            <div className="flex flex-wrap items-center gap-2 pt-1">
              <button
                type="button"
                disabled={astraLoading}
                onClick={async () => {
                  setAstraLoading(true)
                  setAstraMsg(null)
                  try {
                    const res = await fetch('/api/astraflow', {
                      method: 'POST',
                      headers: { 'Content-Type': 'application/json' },
                      body: JSON.stringify({ mode: 'window' }),
                    })
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
                className="glow-button flex w-full items-center justify-center gap-2 rounded-md bg-primary py-3 text-sm font-bold text-primary-foreground transition-all hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
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
            </div>
          </div>
          )}

          {/* Khu vực Đổi mật khẩu */}
          <div className="rounded-lg border border-border bg-secondary/30 overflow-hidden">
            <button
              type="button"
              onClick={() => {
                setShowChangePassword(!showChangePassword)
                setPasswordMsg(null)
              }}
              className="w-full flex items-center justify-between p-4 text-left text-sm font-semibold text-foreground hover:bg-secondary/50 transition-colors cursor-pointer"
            >
              <span className="flex items-center gap-2">
                <Lock size={16} className="text-primary" />
                {user.authProvider === 'google' || user.googleId ? 'Hướng dẫn đăng nhập' : 'Thay đổi mật khẩu'}
              </span>
              {showChangePassword ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
            </button>

            {showChangePassword && (
              <form onSubmit={handleChangePassword} className="p-4 pt-2 border-t border-border/50 space-y-4">
                {passwordMsg && (
                  <div
                    className={`rounded-lg p-3 text-xs font-medium ${
                      passwordMsg.type === 'success'
                        ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                        : 'border border-rose-500/30 bg-rose-500/10 text-rose-400'
                    }`}
                  >
                    {passwordMsg.text}
                  </div>
                )}

                {user.authProvider === 'google' || user.googleId ? (
                  <div className="rounded-md border border-primary/20 bg-primary/5 p-2.5 text-xs text-muted-foreground">
                    Tài khoản được liên kết với Google. Bạn có thể thiết lập mật khẩu tại đây để đăng nhập trực tiếp bằng email và mật khẩu khi cần.
                  </div>
                ) : (
                  <div>
                    <label className="block text-xs font-medium text-muted-foreground mb-1.5">
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
                        className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                      />
                    </div>
                  </div>
                )}

                <div>
                  <label className="block text-xs font-medium text-muted-foreground mb-1.5">
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
                      className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-medium text-muted-foreground mb-1.5">
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
                      className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={passwordLoading}
                  className="glow-button w-full rounded-md py-3 text-sm font-bold bg-primary text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50 cursor-pointer mt-2"
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
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-start border-t border-border bg-secondary/20 px-6 py-4">
          <button
            onClick={async () => {
              onClose()
              await logout()
              if (onLogout) {
                onLogout()
              } else {
                window.location.href = '/'
              }
            }}
            className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground hover:text-rose-400 hover:underline transition-colors cursor-pointer"
          >
            <LogOut size={14} />
            Đăng xuất
          </button>
        </div>
      </div>
    </div>
  )
}
