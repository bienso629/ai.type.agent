'use client'

import React, { useState } from 'react'
import Image from 'next/image'
import { useAuth } from '@/context/AuthContext'
import { X, Lock, Mail, AlertCircle, CheckCircle2, KeyRound, ArrowLeft } from 'lucide-react'

export function LoginModal({
  isOpen: propIsOpen,
  onClose: propOnClose,
}: {
  isOpen?: boolean
  onClose?: () => void
} = {}) {
  const {
    isLoginModalOpen: contextIsOpen,
    closeLoginModal: contextCloseModal,
    loginWithLocal,
    loginWithGoogle,
  } = useAuth()

  const isModalOpen = propIsOpen !== undefined ? propIsOpen : contextIsOpen
  const handleClose = propOnClose || contextCloseModal

  // Mode: 'login' | 'forgot' | 'reset'
  const [mode, setMode] = useState<'login' | 'forgot' | 'reset'>('login')

  // Form state cho đăng nhập hệ thống
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [otp, setOtp] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmNewPassword, setConfirmNewPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  if (!isModalOpen) return null

  const handleSuccess = (userName?: string) => {
    setSuccessMessage(`Đăng nhập thành công! Chào mừng ${userName || 'bạn'} quay trở lại.`)
    setErrorMessage(null)
    setTimeout(() => {
      handleClose()
      setSuccessMessage(null)
      setEmail('')
      setPassword('')
      setMode('login')
    }, 1200)
  }

  const handleSystemSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrorMessage(null)
    setSuccessMessage(null)

    if (!email.trim() || !password) {
      setErrorMessage('Vui lòng nhập đầy đủ Email và Mật khẩu.')
      return
    }

    setLoading(true)
    try {
      const res = await loginWithLocal(email.trim(), password)
      if (!res.success) {
        setErrorMessage(res.message || 'Email hoặc mật khẩu không chính xác.')
      } else {
        handleSuccess(email.trim().split('@')[0])
      }
    } finally {
      setLoading(false)
    }
  }

  // Xử lý gửi OTP Quên mật khẩu
  const handleForgotSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrorMessage(null)
    setSuccessMessage(null)

    if (!email.trim()) {
      setErrorMessage('Vui lòng nhập địa chỉ email của bạn.')
      return
    }

    setLoading(true)
    try {
      const res = await fetch('/api/auth/forgot-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim() }),
      })
      const data = await res.json()

      if (!res.ok || !data.success) {
        setErrorMessage(data.message || 'Có lỗi xảy ra khi gửi yêu cầu.')
      } else {
        setSuccessMessage(data.message)
        // Chuyển sang bước nhập OTP và mật khẩu mới
        setTimeout(() => {
          setMode('reset')
          setSuccessMessage(null)
        }, 1200)
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Lỗi mạng khi gửi yêu cầu.')
    } finally {
      setLoading(false)
    }
  }

  // Xử lý đặt lại mật khẩu với OTP
  const handleResetSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrorMessage(null)
    setSuccessMessage(null)

    if (!otp.trim() || !newPassword) {
      setErrorMessage('Vui lòng nhập đầy đủ mã OTP và mật khẩu mới.')
      return
    }

    if (newPassword.length < 6) {
      setErrorMessage('Mật khẩu mới phải có tối thiểu 6 ký tự.')
      return
    }

    if (newPassword !== confirmNewPassword) {
      setErrorMessage('Mật khẩu xác nhận không khớp.')
      return
    }

    setLoading(true)
    try {
      const res = await fetch('/api/auth/reset-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email.trim(),
          otp: otp.trim(),
          newPassword,
        }),
      })
      const data = await res.json()

      if (!res.ok || !data.success) {
        setErrorMessage(data.message || 'Đặt lại mật khẩu thất bại.')
      } else {
        setSuccessMessage('Đặt lại mật khẩu thành công! Hãy đăng nhập ngay.')
        setPassword(newPassword)
        setOtp('')
        setNewPassword('')
        setConfirmNewPassword('')
        setTimeout(() => {
          setMode('login')
          setSuccessMessage(null)
        }, 1500)
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Lỗi mạng khi đặt lại mật khẩu.')
    } finally {
      setLoading(false)
    }
  }

  const handleGoogleOAuthPopup = () => {
    setErrorMessage(null)
    setSuccessMessage(null)
    const clientId = '377304131013-199fj4fujd3ku2niuek64cripmms8bqb.apps.googleusercontent.com'
    const redirectUri = window.location.origin
    const scope = 'openid email profile'
    const oauthUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=token&scope=${encodeURIComponent(scope)}&prompt=select_account`

    const width = 500
    const height = 600
    const left = window.screenX + (window.outerWidth - width) / 2
    const top = window.screenY + (window.outerHeight - height) / 2

    const popup = window.open(
      oauthUrl,
      'GoogleLoginPopup',
      `width=${width},height=${height},left=${left},top=${top},status=no,toolbar=no,menubar=no`
    )

    if (!popup) {
      setErrorMessage('Trình duyệt đã chặn cửa sổ Popup. Vui lòng mở quyền popup cho trang này.')
      return
    }

    const timer = setInterval(async () => {
      try {
        if (!popup || popup.closed) {
          clearInterval(timer)
          return
        }

        const url = popup.location.href
        if (url.includes('access_token=')) {
          clearInterval(timer)
          const params = new URLSearchParams(popup.location.hash.substring(1))
          const accessToken = params.get('access_token')
          popup.close()

          if (accessToken) {
            setLoading(true)
            try {
              const res = await loginWithGoogle(undefined, accessToken)
              if (!res.success) {
                setErrorMessage(res.message || 'Đăng nhập Google thất bại.')
              } else {
                handleSuccess('bạn')
              }
            } finally {
              setLoading(false)
            }
          }
        }
      } catch (e) {
        // Bỏ qua lỗi cross-origin khi popup chưa redirect về cùng domain
      }
    }, 500)
  }

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/75 p-4 backdrop-blur-md animate-in fade-in duration-200"
      onClick={handleClose}
    >
      <div
        className="relative w-full max-w-md overflow-hidden rounded-2xl border border-border bg-card shadow-2xl transition-all"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Modal */}
        <div className="flex items-center justify-between border-b border-border bg-secondary/30 px-6 py-4">
          <div className="flex items-center gap-3">
            {mode !== 'login' ? (
              <button
                type="button"
                onClick={() => {
                  setMode('login')
                  setErrorMessage(null)
                  setSuccessMessage(null)
                }}
                className="flex h-9 w-9 items-center justify-center rounded-lg bg-secondary hover:bg-secondary/80 text-foreground transition-colors cursor-pointer"
                title="Quay lại đăng nhập"
              >
                <ArrowLeft size={18} />
              </button>
            ) : (
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10">
                <Image src="/logo.png" alt="Logo" width={24} height={24} className="object-contain" />
              </div>
            )}
            <div>
              <h3 className="font-display text-base font-bold text-foreground">
                {mode === 'login' && 'Đăng nhập Mì Tôm AI'}
                {mode === 'forgot' && 'Quên mật khẩu'}
                {mode === 'reset' && 'Đặt lại mật khẩu mới'}
              </h3>
              <p className="text-[11px] text-muted-foreground">
                {mode === 'login' && 'Nhập tài khoản hệ thống hoặc chọn liên kết Google bên dưới'}
                {mode === 'forgot' && 'Nhập email để nhận mã OTP khôi phục mật khẩu'}
                {mode === 'reset' && 'Nhập mã OTP vừa nhận từ email và mật khẩu mới'}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground cursor-pointer shrink-0"
            aria-label="Đóng"
          >
            <X size={18} />
          </button>
        </div>

        {/* Nội dung Modal Form */}
        <div className="p-6">
          {errorMessage && (
            <div className="mb-4 flex items-start gap-2.5 rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-300">
              <AlertCircle size={16} className="shrink-0 text-rose-400 mt-0.5" />
              <span>{errorMessage}</span>
            </div>
          )}

          {successMessage && (
            <div className="mb-4 flex items-start gap-2.5 rounded-md border border-emerald-500/40 bg-emerald-500/15 p-3 text-xs text-emerald-500 font-medium">
              <CheckCircle2 size={16} className="shrink-0 text-emerald-500 mt-0.5" />
              <span>{successMessage}</span>
            </div>
          )}

          {/* Giao diện Đăng nhập */}
          {mode === 'login' && (
            <>
              <form onSubmit={handleSystemSubmit} className="space-y-4">
                <div>
                  <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                    Email tài khoản
                  </label>
                  <div className="relative">
                    <Mail size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                    <input
                      type="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="name@example.com"
                      className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                    />
                  </div>
                </div>

                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="text-xs font-medium text-muted-foreground">
                      Mật khẩu
                    </label>
                    <button
                      type="button"
                      onClick={() => {
                        setMode('forgot')
                        setErrorMessage(null)
                        setSuccessMessage(null)
                      }}
                      className="text-[11px] font-medium text-primary hover:underline cursor-pointer"
                    >
                      Quên mật khẩu?
                    </button>
                  </div>
                  <div className="relative">
                    <Lock size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                    <input
                      type="password"
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      placeholder="••••••••"
                      className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={loading || Boolean(successMessage)}
                  className="glow-button flex w-full items-center justify-center gap-2 rounded-md py-3 text-sm font-bold transition-all disabled:opacity-50 cursor-pointer"
                >
                  {loading ? (
                    <span className="flex items-center gap-2">
                      <span className="h-4 w-4 animate-spin rounded-full border-2 border-black border-t-transparent" />
                      Đang xác thực...
                    </span>
                  ) : successMessage ? (
                    'Thành công!'
                  ) : (
                    'Đăng nhập'
                  )}
                </button>
              </form>

              <div className="relative my-5">
                <div className="absolute inset-0 flex items-center">
                  <span className="w-full border-t border-border" />
                </div>
                <div className="relative flex justify-center text-[10px] uppercase">
                  <span className="bg-card px-2 text-muted-foreground">hoặc đăng nhập bằng</span>
                </div>
              </div>

              <button
                type="button"
                onClick={handleGoogleOAuthPopup}
                className="group flex w-full items-center justify-center gap-2.5 rounded-md border border-border bg-secondary/40 py-2.5 px-4 text-xs font-semibold text-foreground transition-all hover:bg-secondary hover:border-primary/50 cursor-pointer"
              >
                <svg width="18" height="18" viewBox="0 0 24 24" className="shrink-0">
                  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" />
                  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" />
                </svg>
                <span>Đăng nhập với Google</span>
              </button>
            </>
          )}

          {/* Giao diện Yêu cầu gửi OTP Quên mật khẩu */}
          {mode === 'forgot' && (
            <form onSubmit={handleForgotSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                  Email đã đăng ký tài khoản
                </label>
                <div className="relative">
                  <Mail size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="name@example.com"
                    className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="glow-button flex w-full items-center justify-center gap-2 rounded-md py-3 text-sm font-bold transition-all disabled:opacity-50 cursor-pointer"
              >
                {loading ? 'Đang gửi yêu cầu...' : 'Gửi mã xác nhận OTP'}
              </button>

              <div className="text-center pt-2">
                <button
                  type="button"
                  onClick={() => {
                    setMode('login')
                    setErrorMessage(null)
                    setSuccessMessage(null)
                  }}
                  className="text-xs font-medium text-muted-foreground hover:text-foreground transition-colors cursor-pointer"
                >
                  Quay lại đăng nhập
                </button>
              </div>
            </form>
          )}

          {/* Giao diện Đặt lại mật khẩu với OTP */}
          {mode === 'reset' && (
            <form onSubmit={handleResetSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                  Mã OTP (gồm 6 chữ số gửi qua email)
                </label>
                <div className="relative">
                  <KeyRound size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="text"
                    required
                    value={otp}
                    onChange={(e) => setOtp(e.target.value)}
                    placeholder="123456"
                    className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground font-mono tracking-wider placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

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
                    value={confirmNewPassword}
                    onChange={(e) => setConfirmNewPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="glow-button flex w-full items-center justify-center gap-2 rounded-md py-3 text-sm font-bold transition-all disabled:opacity-50 cursor-pointer"
              >
                {loading ? 'Đang đặt lại mật khẩu...' : 'Xác nhận đặt lại mật khẩu'}
              </button>

              <div className="text-center pt-2">
                <button
                  type="button"
                  onClick={() => {
                    setMode('forgot')
                    setErrorMessage(null)
                    setSuccessMessage(null)
                  }}
                  className="text-xs font-medium text-primary hover:underline cursor-pointer"
                >
                  Gửi lại mã OTP
                </button>
              </div>
            </form>
          )}
        </div>

        <div className="border-t border-border bg-secondary/20 px-6 py-3 text-center text-[11px] text-muted-foreground">
          Bằng việc đăng nhập, bạn đồng ý với Điều khoản và Chính sách của Mì Tôm AI.
        </div>
      </div>
    </div>
  )
}
