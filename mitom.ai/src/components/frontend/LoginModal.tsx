'use client'

import React, { useState } from 'react'
import Image from 'next/image'
import { GoogleLogin } from '@react-oauth/google'
import { useAuth } from '@/context/AuthContext'
import { X, Lock, Mail, AlertCircle, Cloud, CheckCircle2, Copy } from 'lucide-react'

export function LoginModal() {
  const { isLoginModalOpen, closeLoginModal, loginWithTadu, loginWithGoogle } = useAuth()
  const [activeTab, setActiveTab] = useState<'google' | 'tadu'>('google')

  // Form state cho Tadu Cloud
  const [taduEmail, setTaduEmail] = useState('')
  const [taduPassword, setTaduPassword] = useState('')
  const [taduLoading, setTaduLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)


  if (!isLoginModalOpen) return null

  const handleTaduSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrorMessage(null)

    if (!taduEmail.trim() || !taduPassword) {
      setErrorMessage('Vui lòng nhập đầy đủ Email và Mật khẩu Tadu Cloud.')
      return
    }

    if (taduPassword.length < 6) {
      setErrorMessage('Mật khẩu Tadu Cloud phải có ít nhất 6 ký tự.')
      return
    }

    setTaduLoading(true)
    try {
      const res = await loginWithTadu(taduEmail.trim(), taduPassword)
      if (!res.success) {
        setErrorMessage(res.message || 'Đăng nhập Tadu Cloud thất bại.')
      }
    } finally {
      setTaduLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md animate-in fade-in duration-200">
      <div
        className="relative w-full max-w-md overflow-hidden rounded-2xl border border-border bg-card shadow-2xl transition-all"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Modal */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 p-1 text-primary">
              <Image src="/logo.png" alt="Logo" width={24} height={24} className="object-contain" />
            </div>
            <div>
              <h3 className="font-display text-base font-bold text-foreground">Đăng nhập tài khoản</h3>
              <p className="text-[11px] text-muted-foreground">Mì Tôm AI & Cổng kết nối dịch vụ</p>
            </div>
          </div>
          <button
            onClick={closeLoginModal}
            className="rounded-lg p-1.5 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            aria-label="Đóng"
          >
            <X size={18} />
          </button>
        </div>

        {/* Tab Selection */}
        <div className="grid grid-cols-2 border-b border-border bg-secondary/30 p-1 text-xs font-semibold">
          <button
            type="button"
            onClick={() => {
              setActiveTab('google')
              setErrorMessage(null)
            }}
            className={`flex items-center justify-center gap-2 rounded-lg py-2.5 transition-all ${
              activeTab === 'google'
                ? 'bg-card text-primary shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <svg width="16" height="16" viewBox="0 0 24 24">
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
            Tài khoản Google
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab('tadu')
              setErrorMessage(null)
            }}
            className={`flex items-center justify-center gap-2 rounded-lg py-2.5 transition-all ${
              activeTab === 'tadu'
                ? 'bg-card text-primary shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <Cloud size={16} className={activeTab === 'tadu' ? 'text-primary' : ''} />
            Tadu Cloud
          </button>
        </div>

        {/* Nội dung Modal */}
        <div className="p-6">
          {errorMessage && (
            <div className="mb-4 flex items-start gap-2.5 rounded-lg border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-300">
              <AlertCircle size={16} className="shrink-0 text-rose-400 mt-0.5" />
              <span>{errorMessage}</span>
            </div>
          )}

          {activeTab === 'google' && (
            <div className="space-y-4 text-center">
              <p className="text-xs text-muted-foreground leading-relaxed">
                Đăng nhập nhanh chóng và an toàn bằng tài khoản Google của bạn để quản lý số dư và truy cập API.
              </p>

              <div className="pt-2 flex flex-col items-center justify-center gap-3">
                <div className="w-full flex justify-center">
                  <GoogleLogin
                    onSuccess={async (credentialResponse) => {
                      setErrorMessage(null)
                      if (credentialResponse.credential) {
                        const res = await loginWithGoogle(credentialResponse.credential)
                        if (!res.success) {
                          setErrorMessage(res.message || 'Đăng nhập Google không thành công.')
                        }
                      }
                    }}
                    onError={() => {
                      setErrorMessage('Đăng nhập Google thất bại.')
                    }}
                    useOneTap
                    theme="filled_black"
                    shape="pill"
                    size="large"
                    text="signin_with"
                    width="320"
                  />
                </div>
              </div>
            </div>
          )}

          {activeTab === 'tadu' && (
            <form onSubmit={handleTaduSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-muted-foreground mb-1.5">
                  Email tài khoản Tadu Cloud
                </label>
                <div className="relative">
                  <Mail size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="email"
                    required
                    value={taduEmail}
                    onChange={(e) => setTaduEmail(e.target.value)}
                    placeholder="tai-khoan@tadu.vn"
                    className="w-full rounded-xl border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
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
                    value={taduPassword}
                    onChange={(e) => setTaduPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full rounded-xl border border-border bg-secondary/40 py-2.5 pl-10 pr-3.5 text-sm text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                </div>
              </div>

              <div className="flex items-center justify-between text-[11px] text-muted-foreground">
                <span>Xác thực qua API Tadu Cloud</span>
                <a
                  href="https://tadu.vn"
                  target="_blank"
                  rel="noreferrer"
                  className="text-primary hover:underline"
                >
                  Quên mật khẩu?
                </a>
              </div>

              <button
                type="submit"
                disabled={taduLoading}
                className="glow-button mt-2 flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3 text-sm font-bold text-primary-foreground transition-all hover:scale-[1.02] disabled:opacity-50"
              >
                {taduLoading ? (
                  <span className="flex items-center gap-2">
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-primary-foreground border-t-transparent" />
                    Đang xác thực Tadu...
                  </span>
                ) : (
                  'Đăng nhập Tadu Cloud'
                )}
              </button>
            </form>
          )}
        </div>

        {/* Footer Modal */}
        <div className="border-t border-border bg-secondary/20 px-6 py-3 text-center text-[11px] text-muted-foreground">
          Bằng việc đăng nhập, bạn đồng ý với Điều khoản và Chính sách bảo mật của Mì Tôm AI.
        </div>
      </div>
    </div>
  )
}
