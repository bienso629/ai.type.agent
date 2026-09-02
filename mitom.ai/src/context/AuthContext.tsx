'use client'

import React, { createContext, useContext, useState, useEffect, useCallback } from 'react'

export interface AuthUser {
  id: string | number
  email: string
  name?: string
  avatar?: string
  authProvider: 'local' | 'google' | 'tadu'
  balance: number
  customerCode?: string
  apiKey?: string
  role?: string
}

interface AuthContextType {
  user: AuthUser | null
  loading: boolean
  isLoginModalOpen: boolean
  openLoginModal: () => void
  closeLoginModal: () => void
  loginWithLocal: (email: string, password: string) => Promise<{ success: boolean; message?: string }>
  loginWithTadu: (email: string, password: string) => Promise<{ success: boolean; message?: string }>
  loginWithGoogle: (credential?: string, accessToken?: string) => Promise<{ success: boolean; message?: string }>
  logout: () => Promise<void>
  refreshUser: () => Promise<void>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [isLoginModalOpen, setIsLoginModalOpen] = useState(false)

  const refreshUser = useCallback(async () => {
    try {
      const res = await fetch('/api/auth/me')
      if (res.ok) {
        const data = await res.json()
        if (data.authenticated && data.user) {
          setUser(data.user)
          return
        }
      }
      setUser(null)
    } catch {
      setUser(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    refreshUser()
  }, [refreshUser])

  const openLoginModal = () => setIsLoginModalOpen(true)
  const closeLoginModal = () => setIsLoginModalOpen(false)

  const loginWithLocal = async (email: string, password: string) => {
    try {
      const res = await fetch('/api/auth/local', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      })
      const data = await res.json()

      if (!res.ok || !data.success) {
        return { success: false, message: data.message || 'Đăng nhập thất bại.' }
      }

      setUser(data.user)
      setIsLoginModalOpen(false)
      return { success: true }
    } catch (err: any) {
      return { success: false, message: err.message || 'Lỗi mạng khi kết nối đăng nhập.' }
    }
  }

  const loginWithTadu = async (email: string, password: string) => {
    try {
      const res = await fetch('/api/auth/tadu', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      })
      const data = await res.json()

      if (!res.ok || !data.success) {
        return { success: false, message: data.message || 'Đăng nhập Tadu thất bại.' }
      }

      setUser(data.user)
      setIsLoginModalOpen(false)
      return { success: true }
    } catch (err: any) {
      return { success: false, message: err.message || 'Lỗi mạng khi kết nối đăng nhập.' }
    }
  }

  const loginWithGoogle = async (credential?: string, accessToken?: string) => {
    try {
      const res = await fetch('/api/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ credential, accessToken }),
      })
      const data = await res.json()

      if (!res.ok || !data.success) {
        return { success: false, message: data.message || 'Đăng nhập Google thất bại.' }
      }

      setUser(data.user)
      setIsLoginModalOpen(false)
      return { success: true }
    } catch (err: any) {
      return { success: false, message: err.message || 'Lỗi mạng khi đăng nhập Google.' }
    }
  }

  const logout = async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' })
    } finally {
      setUser(null)
    }
  }

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        isLoginModalOpen,
        openLoginModal,
        closeLoginModal,
        loginWithLocal,
        loginWithTadu,
        loginWithGoogle,
        logout,
        refreshUser,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
