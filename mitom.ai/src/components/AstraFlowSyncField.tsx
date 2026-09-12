'use client'

import React, { useState } from 'react'

export const AstraFlowSyncField: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [msg, setMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  const handleOpenLogin = async () => {
    setLoading(true)
    setMsg(null)
    try {
      const res = await fetch('/api/astraflow', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'window' }),
      })
      const data = await res.json()
      if (data.success) {
        setMsg({
          type: 'success',
          text: data.message || 'Đã mở cửa sổ Chrome tại passport.scloudsg.com.',
        })
      } else {
        setMsg({
          type: 'error',
          text: data.error || 'Lỗi khi kích hoạt cửa sổ đăng nhập.',
        })
      }
    } catch (e: any) {
      setMsg({ type: 'error', text: e.message || 'Lỗi kết nối máy chủ.' })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div
      style={{
        padding: '16px',
        background: 'var(--theme-elevation-50, #14161f)',
        border: '1px solid var(--theme-elevation-150, #2a2e3d)',
        borderRadius: '4px',
        marginTop: '16px',
        marginBottom: '24px',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
        <h4 style={{ margin: 0, fontSize: '14px', fontWeight: 'bold', color: '#f5c451' }}>
          Đồng bộ Cookies AstraFlow
        </h4>
        <span style={{ fontSize: '12px', opacity: 0.7, fontFamily: 'monospace' }}>
          passport.scloudsg.com
        </span>
      </div>

      <p style={{ fontSize: '13px', margin: '0 0 14px 0', opacity: 0.8, lineHeight: 1.5 }}>
        Bấm nút bên dưới để mở cửa sổ trình duyệt Chrome tại <code>https://passport.scloudsg.com/</code>.
        Sau khi bạn đăng nhập hoàn tất, toàn bộ cookies sẽ tự động được lưu vào tệp <code>astraflow_cookies.json</code> trên máy chủ.
      </p>

      {msg && (
        <div
          style={{
            padding: '10px 14px',
            borderRadius: '4px',
            fontSize: '12px',
            marginBottom: '14px',
            background: msg.type === 'success' ? 'rgba(52, 211, 153, 0.15)' : 'rgba(239, 68, 68, 0.15)',
            color: msg.type === 'success' ? '#34d399' : '#f87171',
            border: `1px solid ${msg.type === 'success' ? '#34d39940' : '#f8717140'}`,
          }}
        >
          {msg.text}
        </div>
      )}

      <div>
        <button
          type="button"
          disabled={loading}
          onClick={handleOpenLogin}
          style={{
            background: '#f5c451',
            color: '#000',
            fontWeight: 'bold',
            fontSize: '13px',
            padding: '8px 16px',
            borderRadius: '4px',
            border: 'none',
            cursor: loading ? 'not-allowed' : 'pointer',
            opacity: loading ? 0.6 : 1,
            display: 'inline-flex',
            alignItems: 'center',
            gap: '8px',
          }}
        >
          {loading ? 'Đang kích hoạt...' : 'Đăng nhập AstraFlow để lấy Cookie'}
        </button>
      </div>
    </div>
  )
}
export default AstraFlowSyncField
