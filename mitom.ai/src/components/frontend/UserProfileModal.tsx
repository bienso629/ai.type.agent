'use client'

import React, { useState } from 'react'
import { useAuth } from '@/context/AuthContext'
import { User, LogOut, Key, Wallet, Shield, Check, Copy, ExternalLink, RefreshCw } from 'lucide-react'

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
  const [copiedKey, setCopiedKey] = useState(false)
  const [refreshing, setRefreshing] = useState(false)

  if (!isOpen || !user) return null

  const handleCopyKey = () => {
    if (user.apiKey) {
      navigator.clipboard.writeText(user.apiKey)
      setCopiedKey(true)
      setTimeout(() => setCopiedKey(false), 2000)
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
            onClick={onClose}
            className="rounded-lg p-1.5 text-muted-foreground hover:bg-secondary hover:text-foreground"
          >
            ✕
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

          {/* API Key Box */}
          <div className="rounded-xl border border-border bg-secondary/40 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="flex items-center gap-1.5 text-xs font-semibold text-foreground">
                <Key size={14} className="text-primary" />
                API Key cá nhân
              </span>
              <button
                onClick={handleCopyKey}
                className="flex items-center gap-1 text-[11px] font-medium text-primary hover:underline"
              >
                {copiedKey ? (
                  <>
                    <Check size={12} /> Đã sao chép
                  </>
                ) : (
                  <>
                    <Copy size={12} /> Sao chép
                  </>
                )}
              </button>
            </div>
            <div className="font-mono text-xs text-muted-foreground break-all bg-background/80 p-2.5 rounded-lg border border-border">
              {user.apiKey || 'Chưa khởi tạo API Key'}
            </div>
            <p className="text-[11px] text-muted-foreground mt-2">
              Sử dụng API Key này làm Bearer Token cho Base URL:{' '}
              <code className="text-primary font-mono">https://api-us-ca.umodelverse.ai/v1</code>
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border bg-secondary/20 px-6 py-4">
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
          <button
            onClick={onClose}
            className="rounded-md bg-secondary px-5 py-2 text-xs font-semibold text-foreground hover:bg-secondary/80 transition-colors"
          >
            Đóng
          </button>
        </div>
      </div>
    </div>
  )
}
