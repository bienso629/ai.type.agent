'use client'

import React, { useState, useEffect, useCallback } from 'react'
import { useAuth } from '@/context/AuthContext'
import {
  User,
  LogOut,
  Wallet,
  Shield,
  ExternalLink,
  RefreshCw,
  X,
  Lock,
  ChevronDown,
  ChevronUp,
  Globe,
  Activity,
  History,
  TrendingDown,
  CheckCircle2,
  Clock,
  FileText
} from 'lucide-react'

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

  // State Dữ liệu Tiêu thụ & Lịch sử nạp
  const [usageStats, setUsageStats] = useState<{
    dailyUsedVnd: number
    monthlyUsedVnd: number
    dailyUsedUsd: string
    monthlyUsedUsd: string
    keyStatus: string
    lastUpdated: string | null
  } | null>(null)
  const [topupHistory, setTopupHistory] = useState<any[]>([])
  const [loadingUsage, setLoadingUsage] = useState(false)

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

  const fetchUsageData = useCallback(async () => {
    if (!isOpen) return
    setLoadingUsage(true)
    try {
      const res = await fetch('/api/user/usage')
      if (res.ok) {
        const data = await res.json()
        if (data.success) {
          setUsageStats(data.usageStats)
          setTopupHistory(data.topupHistory || [])
        }
      }
    } catch {
      // Ignored
    } finally {
      setLoadingUsage(false)
    }
  }, [isOpen])

  useEffect(() => {
    if (isOpen) {
      fetchUsageData()
    }
  }, [isOpen, fetchUsageData])



  if (!isOpen || !user) return null

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
    await Promise.all([refreshUser(), fetchUsageData()])
    setRefreshing(false)
  }

  const formatVnd = (n: number) => n.toLocaleString('vi-VN') + 'đ'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md animate-in fade-in duration-200">
      <div
        className="relative w-full max-w-lg max-h-[90vh] flex flex-col overflow-hidden rounded-lg border border-border bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4 shrink-0">
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

        {/* Body (Scrollable) */}
        <div className="p-6 space-y-5 overflow-y-auto max-h-[calc(90vh-140px)]">
          {/* Badge phương thức, mã khách hàng và số dư */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-lg border border-border bg-secondary/30 p-3.5">
              <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1">
                <Shield size={14} className="text-primary" />
                <span>Mã khách hàng</span>
              </div>
              <div className="text-sm font-bold text-primary font-mono select-all">
                {user.customerCode || 'MITO'}
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
                  title="Làm mới số dư & dữ liệu sử dụng"
                >
                  <RefreshCw size={12} className={refreshing ? 'animate-spin' : ''} />
                </button>
              </div>
              <div className="text-base font-extrabold text-emerald font-display">
                {formatVnd(user.balance || 0)}
              </div>
            </div>
          </div>

          {/* Block Mức tiêu thụ API AstraFlow */}
          <div className="rounded-lg border border-border bg-secondary/30 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold text-foreground">
                <Activity size={14} className="text-primary" />
                <span>Mức tiêu thụ API Key (AstraFlow)</span>
              </div>
              {usageStats?.keyStatus && (
                <span className="inline-flex items-center gap-1 font-mono text-[10px] font-bold text-emerald">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald animate-pulse" />
                  {usageStats.keyStatus}
                </span>
              )}
            </div>

            <div className="grid grid-cols-2 gap-2.5 pt-1">
              <div className="rounded-md border border-border/80 bg-background/60 p-2.5">
                <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
                  <Clock size={12} />
                  <span>Tiêu thụ hôm nay</span>
                </div>
                <div className="mt-1 font-mono font-bold text-sm text-foreground">
                  {formatVnd(usageStats?.dailyUsedVnd || 0)}
                </div>
              </div>

              <div className="rounded-md border border-border/80 bg-background/60 p-2.5">
                <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
                  <TrendingDown size={12} className="text-amber-400" />
                  <span>Tiêu thụ tháng này</span>
                </div>
                <div className="mt-1 font-mono font-bold text-sm text-foreground">
                  {formatVnd(usageStats?.monthlyUsedVnd || 0)}
                </div>
              </div>
            </div>
          </div>

          {/* Block Danh sách chi tiết các lần nạp tiền */}
          <div className="rounded-lg border border-border bg-secondary/30 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold text-foreground">
                <History size={14} className="text-primary" />
                <span>Lịch sử nạp số dư</span>
              </div>
              <span className="font-mono text-[11px] text-muted-foreground">
                {topupHistory.length} giao dịch
              </span>
            </div>

            {loadingUsage ? (
              <div className="py-6 text-center text-xs text-muted-foreground">
                Đang tải dữ liệu lịch sử...
              </div>
            ) : topupHistory.length === 0 ? (
              <div className="rounded-md border border-dashed border-border py-5 text-center text-xs text-muted-foreground">
                Chưa có giao dịch nạp tiền nào được ghi nhận.
              </div>
            ) : (
              <div className="space-y-2 max-h-48 overflow-y-auto pr-1">
                {topupHistory.map((item) => (
                  <div
                    key={item.id}
                    className="flex items-center justify-between rounded-md border border-border/70 bg-background/60 p-2.5 text-xs transition-colors hover:border-border"
                  >
                    <div className="space-y-0.5">
                      <div className="flex items-center gap-1.5">
                        <CheckCircle2 size={13} className="text-emerald shrink-0" />
                        <span className="font-semibold text-foreground">
                          {item.planName || 'Nạp số dư'}
                        </span>
                        {item.invoiceCode && (
                          <span className="rounded bg-primary/10 border border-primary/20 px-1.5 py-0.2 font-mono text-[9px] font-semibold text-primary">
                            {item.invoiceCode}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 text-[11px] text-muted-foreground font-mono">
                        <span>{item.code}</span>
                        <span>•</span>
                        <span>{new Date(item.createdAt).toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="font-mono font-bold text-emerald">
                        +{formatVnd(item.amount)}
                      </div>
                      <span className="text-[10px] text-muted-foreground">
                        {item.status}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
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
                className="glow-button flex items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2 text-xs font-bold text-primary-foreground transition-all hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
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
                Thay đổi mật khẩu
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

                {user.authProvider === 'local' && (
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
                  className="glow-button flex w-full items-center justify-center gap-2 rounded-md py-3 text-sm font-bold transition-all disabled:opacity-50 cursor-pointer mt-2"
                >
                  {passwordLoading ? (
                    <span className="flex items-center gap-2">
                      <span className="h-4 w-4 animate-spin rounded-full border-2 border-black border-t-transparent" />
                      Đang cập nhật...
                    </span>
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
            className="flex items-center gap-2 rounded-md border border-rose-500/30 bg-rose-500/10 px-4 py-2 text-xs font-semibold text-rose-300 hover:bg-rose-500/20 transition-colors"
          >
            <LogOut size={14} />
            Đăng xuất
          </button>
        </div>
      </div>
    </div>
  )
}
