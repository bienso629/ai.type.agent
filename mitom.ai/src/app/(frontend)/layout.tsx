import React from 'react'
import type { Metadata } from 'next'
import './styles.css'
import { ClientProviders } from '@/components/frontend/ClientProviders'

export const metadata: Metadata = {
  title: 'Mì Tôm AI - Cổng API & Danh Mục 130+ Mô Hình AI Sẵn Sàng 24/7',
  description: 'Một số dư, gọi mọi model AI: DeepSeek, GLM-5.3, Qwen, Doubao, Kling Video, Vidu, Wan-AI. Chuẩn định dạng OpenAI API qua endpoint tốc độ cao.',
  icons: {
    icon: '/logo.png',
  },
  other: {
    'cf-rocket-loader': 'off',
  },
}

export default async function RootLayout(props: { children: React.ReactNode }) {
  const { children } = props

  return (
    <html lang="vi" data-cfasync="false">
      <head>
        <meta data-cfasync="false" />
      </head>
      <body data-cfasync="false" className="min-h-screen w-full bg-background text-foreground font-sans antialiased">
        <ClientProviders>{children}</ClientProviders>
      </body>
    </html>
  )
}
