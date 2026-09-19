'use client'

import React from 'react'
import { Zap, ShieldCheck, CreditCard, Sparkles, CheckCircle2, Lock, Cpu, Headphones } from 'lucide-react'

export const FeaturesGuide: React.FC = () => {
  return (
    <>
      {/* 3 Step Guide */}
      <section id="huong-dan" className="guide-section">
        <div className="container">
          <div className="section-header-center">
            <span className="section-sub-badge">Quy Trình Tự Động</span>
            <h2 className="section-title">3 Bước Nạp Thẻ & Kích Hoạt Siêu Tốc</h2>
            <p className="section-description">
              Hệ thống xử lý thanh toán và kích hoạt hoàn toàn tự động 24/7, không cần chờ duyệt thủ công.
            </p>
          </div>

          <div className="steps-grid">
            <div className="step-card">
              <div className="step-number">01</div>
              <div className="step-icon-wrap">
                <CreditCard size={28} />
              </div>
              <h3 className="step-title">Chọn Mệnh Giá Thẻ</h3>
              <p className="step-desc">
                Lựa chọn mệnh giá phù hợp với nhu cầu từ 20.000đ đến 1.000.000đ.
              </p>
            </div>

            <div className="step-card">
              <div className="step-number">02</div>
              <div className="step-icon-wrap">
                <Zap size={28} />
              </div>
              <h3 className="step-title">Thanh Toán Quét VietQR</h3>
              <p className="step-desc">
                Mở ứng dụng ngân hàng hoặc ví điện tử bất kỳ quét mã QR tự động. Số tiền và mã đơn hàng được điền sẵn chuẩn xác.
              </p>
            </div>

            <div className="step-card">
              <div className="step-number">03</div>
              <div className="step-icon-wrap">
                <Sparkles size={28} />
              </div>
              <h3 className="step-title">Nhận Mã & Kích Hoạt</h3>
              <p className="step-desc">
                Ngay sau khi thanh toán thành công, hệ thống tự động gửi mã thẻ qua email và hiển thị trực tiếp trên trang tra cứu.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Why Choose Us */}
      <section id="cam-ket" className="benefits-section">
        <div className="container">
          <div className="section-header-center">
            <span className="section-sub-badge">Ưu Điểm Vượt Trội</span>
            <h2 className="section-title">Tại Sao Nên Chọn Mì Tôm AI?</h2>
            <p className="section-description">
              Giải pháp tối ưu chi phí và nâng cao hiệu suất làm việc với trí tuệ nhân tạo.
            </p>
          </div>

          <div className="benefits-grid">
            <div className="benefit-card">
              <div className="benefit-icon">
                <Zap size={24} />
              </div>
              <h4>Kích Hoạt Tức Thì</h4>
              <p>Hệ thống kết nối API ngân hàng tự động cập nhật số dư chỉ sau vài giây giao dịch.</p>
            </div>

            <div className="benefit-card">
              <div className="benefit-icon">
                <Lock size={24} />
              </div>
              <h4>Bảo Lưu Số Dư Vĩnh Viễn</h4>
              <p>Mã thẻ và số dư tài khoản của bạn không bị giới hạn thời gian hết hạn, sử dụng bất cứ khi nào.</p>
            </div>

            <div className="benefit-card">
              <div className="benefit-icon">
                <Cpu size={24} />
              </div>
              <h4>Đa Nền Tảng AI</h4>
              <p>Tương thích và hỗ trợ nạp dịch vụ cho OpenAI, Claude, Midjourney, v.v.</p>
            </div>

            <div className="benefit-card">
              <div className="benefit-icon">
                <Headphones size={24} />
              </div>
              <h4>Hỗ Trợ Kỹ Thuật 24/7</h4>
              <p>Đội ngũ trực ban sẵn sàng giải đáp thắc mắc và hỗ trợ xử lý đơn hàng mọi lúc.</p>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
