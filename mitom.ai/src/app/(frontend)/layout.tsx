import React from 'react'
import type { Metadata } from 'next'
import './styles.css'

export const metadata: Metadata = {
  title: 'Mì Tôm AI - Nạp Token & Kích Hoạt Công Cụ AI Tự Động 24/7',
  description: 'Một số dư, dùng mọi công cụ AI: ChatGPT Plus, Claude Pro, Midjourney, Cursor, Token API. Nạp một lần, dùng dần, không hết hạn.',
  icons: {
    icon: '/logo.png',
  },
}

export default async function RootLayout(props: { children: React.ReactNode }) {
  const { children } = props

  return (
    <html lang="vi">
      <body className="min-h-screen w-full bg-background text-foreground font-sans antialiased">
        {children}
      </body>
    </html>
  )
}
