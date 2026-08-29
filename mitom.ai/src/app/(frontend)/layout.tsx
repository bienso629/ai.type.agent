import React from 'react'
import './styles.css'

export const metadata = {
  description: 'Mì Tôm AI - Nền tảng tài khoản và gói token AI chính hãng',
  title: 'Mì Tôm AI - Nạp Token & Tài Khoản AI',
}

export default async function RootLayout(props: { children: React.ReactNode }) {
  const { children } = props

  return (
    <html lang="vi">
      <body>
        <main>{children}</main>
      </body>
    </html>
  )
}
