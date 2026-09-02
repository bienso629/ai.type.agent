'use client'

import React, { useState } from 'react'
import Image from 'next/image'
import { useAuth } from '@/context/AuthContext'
import { X, Lock, Mail, AlertCircle, Cloud, CheckCircle2 } from 'lucide-react'

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
    loginWithTadu,
    loginWithGoogle,
  } = useAuth()

  const isModalOpen = propIsOpen !== undefined ? propIsOpen : contextIsOpen
  const handleClose = propOnClose || contextCloseModal

  // Form state cho đăng nhập hệ thống
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  // State phụ cho modal đăng nhập Tadu Cloud
  const [isTaduMode, setIsTaduMode] = useState(false)

  if (!isModalOpen) return null

  const handleSuccess = (userName?: string) => {
    setSuccessMessage(`Đăng nhập thành công! Chào mừng ${userName || 'bạn'} quay trở lại.`)
    setErrorMessage(null)
    setTimeout(() => {
      handleClose()
      setSuccessMessage(null)
      setEmail('')
      setPassword('')
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
      if (isTaduMode) {
        const res = await loginWithTadu(email.trim(), password)
        if (!res.success) {
          setErrorMessage(res.message || 'Đăng nhập Tadu Cloud thất bại.')
        } else {
          handleSuccess(email.trim().split('@')[0])
        }
      } else {
        const res = await loginWithLocal(email.trim(), password)
        if (!res.success) {
          setErrorMessage(res.message || 'Email hoặc mật khẩu không chính xác.')
        } else {
          handleSuccess(email.trim().split('@')[0])
        }
      }
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
      setErrorMessage('Trình duyệt đã chặn popup Google. Vui lòng cho phép popup để đăng nhập.')
      return
    }

    const timer = setInterval(async () => {
      try {
        if (!popup || popup.closed) {
          clearInterval(timer)
          return
        }

        const href = popup.location.href
        if (href.includes('access_token=')) {
          clearInterval(timer)
          const params = new URLSearchParams(popup.location.hash.substring(1))
          const accessToken = params.get('access_token')
          popup.close()

          if (accessToken) {
            const res = await loginWithGoogle(undefined, accessToken)
            if (!res.success) {
              setErrorMessage(res.message || 'Đăng nhập Google thất bại.')
            } else {
              handleSuccess('tài khoản Google')
            }
          }
        }
      } catch (e) {
        // Bỏ qua Cross-Origin khi popup đang ở Google
      }
    }, 500)
  }

  return (
    <div
      style={{ display: 'flex' }}
      className="fixed inset-0 z-[9999] items-center justify-center bg-black/80 p-4 backdrop-blur-md"
      onClick={handleClose}
    >
      <div
        className="relative w-full max-w-md overflow-hidden rounded-xl border border-border bg-card shadow-2xl transition-all"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Modal */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="relative h-8 w-8 flex items-center justify-center">
              <Image src="/logo.png" alt="Logo" width={32} height={32} className="h-full w-full object-contain" />
            </div>
            <div>
              <h3 className="font-display text-base font-bold text-foreground">
                {isTaduMode ? 'Đăng nhập Tadu Cloud' : 'Đăng nhập Mì Tôm AI'}
              </h3>
              <p className="text-[11px] text-muted-foreground">
                {isTaduMode ? 'Sử dụng tài khoản Cloud Server Tadu' : 'Nhập tài khoản hệ thống hoặc chọn liên kết bên dưới'}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-md p-1.5 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground cursor-pointer"
            aria-label="Đóng"
          >
            <X size={18} />
          </button>
        </div>

        {/* Nội dung Modal Form */}
        <div className="p-6">
          {/* Thông báo lỗi */}
          {errorMessage && (
            <div className="mb-4 flex items-start gap-2.5 rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-300">
              <AlertCircle size={16} className="shrink-0 text-rose-400 mt-0.5" />
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Thông báo thành công */}
          {successMessage && (
            <div className="mb-4 flex items-start gap-2.5 rounded-md border border-emerald/40 bg-emerald/15 p-3 text-xs text-emerald font-medium">
              <CheckCircle2 size={16} className="shrink-0 text-emerald mt-0.5" />
              <span>{successMessage}</span>
            </div>
          )}

          {/* Form đăng nhập chính */}
          <form onSubmit={handleSystemSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                {isTaduMode ? 'Email tài khoản Tadu Cloud' : 'Email tài khoản'}
              </label>
              <div className="relative">
                <Mail size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder={isTaduMode ? 'account@tadu.vn' : 'name@example.com'}
                  className="w-full rounded-md border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                Mật khẩu
              </label>
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
              className="glow-button flex w-full items-center justify-center gap-2 rounded-md bg-primary py-3 text-sm font-bold text-primary-foreground transition-all hover:scale-[1.02] disabled:opacity-50 cursor-pointer"
            >
              {loading ? (
                <span className="flex items-center gap-2">
                  <span className="h-4 w-4 animate-spin rounded-full border-2 border-primary-foreground border-t-transparent" />
                  Đang xác thực...
                </span>
              ) : successMessage ? (
                'Thành công!'
              ) : (
                isTaduMode ? 'Đăng nhập với Tadu Cloud' : 'Đăng nhập hệ thống'
              )}
            </button>
          </form>

          {/* Dải phân cách */}
          <div className="relative my-5">
            <div className="absolute inset-0 flex items-center">
              <span className="w-full border-t border-border" />
            </div>
            <div className="relative flex justify-center text-[10px] uppercase">
              <span className="bg-card px-2 text-muted-foreground">hoặc đăng nhập bằng</span>
            </div>
          </div>

          {/* Các lựa chọn đăng nhập khác: Google, Tadu Cloud */}
          <div className="grid grid-cols-2 gap-3">
            {/* Google */}
            <button
              type="button"
              onClick={handleGoogleOAuthPopup}
              className="group flex items-center justify-center gap-2 rounded-md border border-border bg-secondary/40 py-2.5 px-4 text-xs font-semibold text-foreground transition-all hover:bg-secondary hover:border-primary/50 cursor-pointer"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" className="shrink-0">
                <path
                  fill="#4285F4"
                  d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                />
                <path
                  fill="#34A853"
                  d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                />
                <path
                  fill="#FBBC05"
                  d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"
                />
                <path
                  fill="#EA4335"
                  d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"
                />
              </svg>
              <span>Google</span>
            </button>

            {/* Tadu Cloud */}
            <button
              type="button"
              onClick={() => {
                setIsTaduMode(!isTaduMode)
                setErrorMessage(null)
                setSuccessMessage(null)
              }}
              className={`group flex items-center justify-center gap-2 rounded-md border py-2.5 px-4 text-xs font-semibold transition-all cursor-pointer ${
                isTaduMode
                  ? 'border-primary bg-primary/10 text-primary shadow-sm'
                  : 'border-border bg-secondary/40 text-foreground hover:bg-secondary hover:border-primary/50'
              }`}
            >
              <Cloud size={18} className={`shrink-0 ${isTaduMode ? 'text-primary' : 'text-sky-400'}`} />
              <span>Tadu Cloud</span>
            </button>
          </div>
        </div>

        {/* Footer Modal */}
        <div className="border-t border-border bg-secondary/20 px-6 py-3 text-center text-[11px] text-muted-foreground">
          Bằng việc đăng nhập, bạn đồng ý với Điều khoản và Chính sách của Mì Tôm AI.
        </div>
      </div>
    </div>
  )
}
