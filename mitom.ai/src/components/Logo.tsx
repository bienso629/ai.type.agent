import React from 'react'

export const Logo: React.FC = () => {
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <img
        src="/logo.png"
        alt="Logo"
        style={{
          maxHeight: '40px',
          width: 'auto',
          objectFit: 'contain',
          display: 'block',
        }}
      />
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
