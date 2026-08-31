'use client'

import React, { useState, useEffect } from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { Zap, ShieldCheck, Search, Menu, X, ExternalLink, Activity } from 'lucide-react'

interface NavbarProps {
  adminRoute?: string
  onOpenLookup?: () => void
}

export const Navbar: React.FC<NavbarProps> = ({ adminRoute = '/admin', onOpenLookup }) => {
  const [scrolled, setScrolled] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20)
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  return (
    <header className={`navbar-header ${scrolled ? 'navbar-scrolled' : ''}`}>
      <div className="container navbar-container">
        {/* Brand Logo */}
        <Link href="/" className="brand-logo">
          <div className="logo-wrapper">
            <Image
              src="/logo.png"
              alt="Mì Tôm AI Logo"
              width={42}
              height={42}
              className="brand-img"
              priority
            />
          </div>
          <div className="brand-text">
            <span className="brand-title">
              MÌ TÔM <span className="brand-highlight">AI</span>
            </span>
            <span className="brand-subtitle">Thẻ cào & Dịch vụ AI 24/7</span>
          </div>
        </Link>

        {/* Live status badge */}
        <div className="status-badge-wrapper desktop-only">
          <span className="status-indicator">
            <span className="status-ping"></span>
            <span className="status-dot"></span>
          </span>
          <span className="status-text">Hệ thống kích hoạt tự động 24/7</span>
        </div>

        {/* Navigation Links */}
        <nav className="desktop-nav">
          <a href="#menh-gia" className="nav-link">
            Bảng Mệnh Giá
          </a>
          <a href="#huong-dan" className="nav-link">
            Hướng Dẫn
          </a>
          <a href="#cam-ket" className="nav-link">
            Ưu Điểm
          </a>
          <button
            type="button"
            onClick={() => {
              const lookupSection = document.getElementById('tra-cuu')
              if (lookupSection) {
                lookupSection.scrollIntoView({ behavior: 'smooth' })
              } else if (onOpenLookup) {
                onOpenLookup()
              }
            }}
            className="nav-link btn-link"
          >
            <Search size={15} />
            <span>Tra cứu đơn</span>
          </button>
        </nav>

        {/* Mobile menu toggle */}
        <button
          className="mobile-toggle"
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          aria-label="Toggle Navigation"
        >
          {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>

      {/* Mobile Drawer */}
      {mobileMenuOpen && (
        <div className="mobile-menu">
          <a
            href="#menh-gia"
            className="mobile-link"
            onClick={() => setMobileMenuOpen(false)}
          >
            Bảng Mệnh Giá
          </a>
          <a
            href="#huong-dan"
            className="mobile-link"
            onClick={() => setMobileMenuOpen(false)}
          >
            Hướng Dẫn Nạp Thẻ
          </a>
          <a
            href="#cam-ket"
            className="mobile-link"
            onClick={() => setMobileMenuOpen(false)}
          >
            Cam Kết Dịch Vụ
          </a>
          <a
            href="#tra-cuu"
            className="mobile-link"
            onClick={() => {
              setMobileMenuOpen(false)
              const el = document.getElementById('tra-cuu')
              if (el) el.scrollIntoView({ behavior: 'smooth' })
            }}
          >
            Tra Cứu Đơn Hàng
          </a>
        </div>
      )}
    </header>
  )
}
