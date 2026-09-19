'use client'

import React from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { ShieldCheck, Mail, Phone, MessageSquare, ExternalLink, Heart } from 'lucide-react'

interface FooterProps {
  adminRoute?: string
}

export const Footer: React.FC<FooterProps> = ({ adminRoute = '/admin' }) => {
  return (
    <footer className="site-footer">
      <div className="container footer-container">
        <div className="footer-top-grid">
          {/* Col 1: Brand Info */}
          <div className="footer-col footer-col-brand">
            <div className="footer-brand-header">
              <Image
                src="/logo.png"
                alt="Mì Tôm AI Logo"
                width={36}
                height={36}
                className="footer-logo-img"
              />
              <span className="footer-brand-name">
                MÌ TÔM <span className="text-highlight">AI</span>
              </span>
            </div>
            <p className="footer-brand-desc">
              Cổng dịch vụ thẻ cào nạp tài khoản và giải pháp AI tự động hóa thế hệ mới. Nhanh chóng, tiện lợi, minh bạch và an toàn 100%.
            </p>
            <div className="footer-badge-secure">
              <ShieldCheck size={16} className="text-success" />
              <span>Hệ thống bảo mật SSL 256-bit</span>
            </div>
          </div>

          {/* Col 2: Quick Links */}
          <div className="footer-col">
            <h4 className="footer-heading">Liên Kết Nhanh</h4>
            <ul className="footer-links-list">
              <li>
                <a href="#menh-gia">Bảng Mệnh Giá Thẻ</a>
              </li>
              <li>
                <a href="#huong-dan">Hướng Dẫn Nạp Thẻ</a>
              </li>
              <li>
                <a href="#tra-cuu">Tra Cứu Đơn Hàng</a>
              </li>
              <li>
                <a href="#cam-ket">Chính Sách & Cam Kết</a>
              </li>
            </ul>
          </div>

          {/* Col 3: Dịch vụ & Hỗ trợ */}
          <div className="footer-col">
            <h4 className="footer-heading">Hỗ Trợ Khách Hàng</h4>
            <ul className="footer-links-list">
              <li>
                <a href="#tra-cuu">Kiểm tra trạng thái nạp</a>
              </li>
              <li>
                <a href="#huong-dan">Hướng dẫn & Giải đáp</a>
              </li>
              <li>
                <span className="text-muted">Thời gian phục vụ: 24/7/365</span>
              </li>
            </ul>
          </div>

          {/* Col 4: Liên hệ */}
          <div className="footer-col">
            <h4 className="footer-heading">Kênh Liên Hệ</h4>
            <div className="footer-contact-items">
              <div className="contact-item">
                <Mail size={16} />
                <span>support@mitom.ai</span>
              </div>
              <div className="contact-item">
                <MessageSquare size={16} />
                <span>Telegram / Zalo Kỹ Thuật</span>
              </div>
              <div className="contact-item">
                <ShieldCheck size={16} />
                <span>Kích hoạt tự động qua VietQR</span>
              </div>
            </div>
          </div>
        </div>

        {/* Footer Bottom */}
        <div className="footer-bottom-bar">
          <div className="copyright-text">
            © {new Date().getFullYear()} Mì Tôm AI (mitom.ai). Tất cả các quyền được bảo lưu.
          </div>
          <div className="footer-sub-links">
            <a href="#tra-cuu">Tra cứu đơn</a>
          </div>
        </div>
      </div>
    </footer>
  )
}
