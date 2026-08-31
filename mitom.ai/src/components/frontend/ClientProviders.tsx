'use client'

import React from 'react'
import { AuthProvider } from '@/context/AuthContext'
import { LoginModal } from '@/components/frontend/LoginModal'

export function ClientProviders({ children }: { children: React.ReactNode }) {
  return (
    <AuthProvider>
      {children}
      <LoginModal />
    </AuthProvider>
  )
}
