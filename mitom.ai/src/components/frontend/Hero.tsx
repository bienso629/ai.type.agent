'use client'

import React from 'react'
import { Sparkles, ShieldCheck, Zap, ArrowRight, CheckCircle2, TrendingUp, Cpu } from 'lucide-react'

export const Hero: React.FC = () => {
  return (
    <section className="hero-section">
      <div className="hero-background-glow"></div>
      <div className="hero-grid-pattern"></div>

      <div className="container hero-container">
        {/* Top Tag */}
        <div className="hero-badge">
          <Sparkles size={16} className="hero-badge-icon" />
          <span>Hệ Thống Nạp Thẻ Cào & Tài Khoản AI Tự Động 2.0</span>
          <span className="badge-promo">+5% Khuyến Mãi</span>
        </div>

        {/* Main Headline */}
        <h1 className="hero-title">
          Giải Pháp Nạp Thẻ & Dịch Vụ{' '}
          <span className="gradient-text">Mì Tôm AI</span> Siêu Tốc
        </h1>

        {/* Subtitle */}
        <p className="hero-subtitle">
          Kích hoạt ngay trong 5 phút. Hỗ trợ đầy đủ mệnh giá từ 20.000đ đến 1.000.000đ, 
          tự động cộng thêm +5% giá trị vào tài khoản. An toàn, bảo mật và lưu trữ số dư vĩnh viễn.
        </p>

        {/* CTA Actions */}
        <div className="hero-actions">
          <a href="#menh-gia" className="btn-primary-hero">
            <Zap size={18} />
            <span>Xem Các Mệnh Giá</span>
            <ArrowRight size={18} />
          </a>
          <a href="#tra-cuu" className="btn-secondary-hero">
            <ShieldCheck size={18} />
            <span>Tra Cứu Trạng Thái Đơn</span>
          </a>
        </div>

        {/* Trust Badges */}
        <div className="hero-trust-list">
          <div className="trust-item">
            <CheckCircle2 size={18} className="trust-icon" />
            <span>Tự động hóa 24/7</span>
          </div>
          <div className="trust-item">
            <CheckCircle2 size={18} className="trust-icon" />
            <span>Bảo lưu số dư vĩnh viễn</span>
          </div>
          <div className="trust-item">
            <CheckCircle2 size={18} className="trust-icon" />
            <span>Hỗ trợ ChatGPT, Claude, Midjourney</span>
          </div>
        </div>

        {/* Stats Grid */}
        <div className="hero-stats-grid">
          <div className="stat-card">
            <div className="stat-value">+5%</div>
            <div className="stat-label">Thưởng nạp mọi mệnh giá</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">~5 Phút</div>
            <div className="stat-label">Thời gian kích hoạt tự động</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">100%</div>
            <div className="stat-label">Bảo mật & Uy tín tuyệt đối</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">24/7</div>
            <div className="stat-label">Hỗ trợ kỹ thuật liên tục</div>
          </div>
        </div>
      </div>
    </section>
  )
}
