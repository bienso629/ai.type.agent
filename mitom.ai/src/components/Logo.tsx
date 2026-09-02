import React from 'react'

export const Logo: React.FC = () => {
  const usdRate = process.env.NEXT_PUBLIC_USD_RATE || process.env.USD_RATE || '26.000'
  const formattedRate = Number(String(usdRate).replace(/\D/g, '') || 26000).toLocaleString('vi-VN')

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
      <img
        src="/logo.png"
        alt="Logo"
        style={{
          maxHeight: '38px',
          width: 'auto',
          objectFit: 'contain',
          display: 'block',
        }}
      />
      <div
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '6px',
          padding: '3px 8px',
          borderRadius: '6px',
          background: 'rgba(245, 196, 81, 0.12)',
          border: '1px solid rgba(245, 196, 81, 0.3)',
          fontFamily: 'monospace',
          fontSize: '11px',
          color: '#f5c451',
          fontWeight: '600',
          letterSpacing: '0.2px',
        }}
        title="Tỷ giá USD áp dụng quy đổi số dư (.env)"
      >
        <span>USD Rate:</span>
        <span style={{ color: '#fff', fontWeight: 'bold' }}>{formattedRate}đ</span>
      </div>
    </div>
  )
}

export const Icon: React.FC = () => {
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <img
        src="/logo.png"
        alt="Icon"
        style={{
          maxHeight: '24px',
          width: 'auto',
          objectFit: 'contain',
          display: 'block',
        }}
      />
    </div>
  )
}
