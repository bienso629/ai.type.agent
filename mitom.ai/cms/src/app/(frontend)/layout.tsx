import type { Metadata } from 'next'
import React from 'react'
import './globals.css'

export const metadata: Metadata = {
  title: 'Mì Tôm AI | Mua nhanh công cụ AI giá rẻ - Powered by Payload CMS',
  description: 'Nền tảng mua chung và kích hoạt ChatGPT Plus, Claude Pro, Midjourney, Cursor, API Token giá rẻ tại Việt Nam.',
}

export default function FrontendLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="vi">
      <body className="min-h-screen bg-background text-foreground antialiased selection:bg-primary/20">
        {children}
      </body>
    </html>
  )
}
