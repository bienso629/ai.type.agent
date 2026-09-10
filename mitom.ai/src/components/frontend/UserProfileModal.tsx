'use client'

import React, { useState } from 'react'
import { useAuth } from '@/context/AuthContext'
import { User, LogOut, Key, Wallet, Shield, Check, Copy, ExternalLink, RefreshCw, X, Lock, ChevronDown, ChevronUp } from 'lucide-react'

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

  // State đổi mật khẩu
  const [showChangePassword, setShowChangePassword] = useState(false)
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordMsg, setPasswordMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

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
    await refreshUser()
    setRefreshing(false)
  }

  const formatVnd = (n: number) => n.toLocaleString('vi-VN') + 'đ'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md animate-in fade-in duration-200">
      <div
        className="relative w-full max-w-lg overflow-hidden rounded-2xl border border-border bg-card shadow-2xl"
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
              <h3 className="font-display text-base font-bold text-foreground">
                {user.name || 'Người dùng Mì Tôm AI'}
              </h3>
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
            <div className="rounded-xl border border-border bg-secondary/30 p-3.5">
              <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1">
                <Shield size={14} className="text-primary" />
                <span>Mã khách hàng</span>
              </div>
              <div className="text-sm font-bold text-primary font-mono select-all">
                {user.customerCode || `MITO${String(user.id).padStart(6, '0')}`}
              </div>
            </div>

            <div className="rounded-xl border border-border bg-secondary/30 p-3.5">
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

          {/* Thong tin API Key gui qua email */}
          <div className="rounded-xl border border-border bg-secondary/40 p-4">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-foreground mb-1.5">
              <Key size={14} className="text-primary" />
              API Key sử dụng AI
            </div>
            <p className="text-xs text-muted-foreground leading-relaxed">
              API Key được gửi bảo mật trực tiếp vào email đăng ký của bạn (<span className="text-foreground font-medium">{user.email}</span>). Vui lòng kiểm tra hòm thư (bao gồm cả thư mục Spam/Quảng cáo).
            </p>
            <p className="text-[11px] text-muted-foreground mt-2">
              Base URL tích hợp hệ thống: <code className="text-primary font-mono font-bold">https://api-vn-sg.mitom.ai/v1</code>
            </p>
          </div>

          {/* Khu vực Đổi mật khẩu */}
          <div className="rounded-xl border border-border bg-secondary/30 overflow-hidden">
            <button
              type="button"
              onClick={() => {
                setShowChangePassword(!showChangePassword)
                setPasswordMsg(null)
              }}
              className="w-full flex items-center justify-between p-4 text-left text-xs font-semibold text-foreground hover:bg-secondary/50 transition-colors"
            >
              <span className="flex items-center gap-2">
                <Lock size={14} className="text-primary" />
                Thay đổi mật khẩu
              </span>
              {showChangePassword ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </button>

            {showChangePassword && (
              <form onSubmit={handleChangePassword} className="p-4 pt-0 border-t border-border/50 space-y-3 mt-3">
                {passwordMsg && (
                  <div
                    className={`rounded-lg p-2.5 text-xs font-medium ${
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
                    <label className="block text-[11px] font-medium text-muted-foreground mb-1">
                      Mật khẩu hiện tại
                    </label>
                    <input
                      type="password"
                      required
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      placeholder="••••••••"
                      className="w-full rounded-md border border-border bg-background/80 py-2 px-3 text-xs text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                    />
                  </div>
                )}

                <div>
                  <label className="block text-[11px] font-medium text-muted-foreground mb-1">
                    Mật khẩu mới (tối thiểu 6 ký tự)
                  </label>
                  <input
                    type="password"
                    required
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-md border border-border bg-background/80 py-2 px-3 text-xs text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-muted-foreground mb-1">
                    Xác nhận mật khẩu mới
                  </label>
                  <input
                    type="password"
                    required
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-md border border-border bg-background/80 py-2 px-3 text-xs text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                </div>

                <button
                  type="submit"
                  disabled={passwordLoading}
                  className="glow-button w-full py-2 rounded-md text-xs font-bold transition-all disabled:opacity-50 cursor-pointer"
                >
                  {passwordLoading ? 'Đang cập nhật...' : 'Lưu mật khẩu mới'}
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
