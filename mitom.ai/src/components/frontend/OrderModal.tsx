'use client'

import React, { useState } from 'react'
import { X, Check, Copy, AlertCircle, ArrowRight, ShieldCheck, QrCode, RefreshCw } from 'lucide-react'
import { ProductItem, PlanItem } from './ProductCard'

interface OrderModalProps {
  isOpen: boolean
  product: ProductItem | null
  plan: PlanItem | null
  onClose: () => void
  onSuccessCheckOrder?: (orderCode: string) => void
}

export const OrderModal: React.FC<OrderModalProps> = ({
  isOpen,
  product,
  plan,
  onClose,
  onSuccessCheckOrder,
}) => {
  const [customerEmail, setCustomerEmail] = useState('')
  const [customerPhone, setCustomerPhone] = useState('')
  const [note, setNote] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [errorMsg, setErrorMsg] = useState('')
  const [orderResult, setOrderResult] = useState<any>(null)
  const [copiedField, setCopiedField] = useState<string | null>(null)

  if (!isOpen || !product || !plan) return null

  const formatPrice = (amount: number) => {
    return new Intl.NumberFormat('vi-VN').format(amount) + 'đ'
  }

  const bonusAmount = Math.round(plan.price * 1.05)

  const handleCopy = (text: string, fieldName: string) => {
    navigator.clipboard.writeText(text)
    setCopiedField(fieldName)
    setTimeout(() => setCopiedField(null), 2500)
  }

  const handleSubmitOrder = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!customerEmail.trim()) {
      setErrorMsg('Vui lòng nhập địa chỉ email nhận thông tin nạp thẻ.')
      return
    }

    setIsLoading(true)
    setErrorMsg('')

    try {
      const res = await fetch('/api/orders/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          productId: product.id,
          planName: plan.name,
          totalAmount: plan.price,
          customerEmail: customerEmail.trim(),
          customerPhone: customerPhone.trim(),
          note: note.trim(),
        }),
      })

      const data = await res.json()

      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Không thể khởi tạo đơn hàng. Vui lòng thử lại.')
      }

      setOrderResult(data.order)
    } catch (err: any) {
      setErrorMsg(err.message || 'Có lỗi kết nối xảy ra. Vui lòng thử lại.')
    } finally {
      setIsLoading(false)
    }
  }

  const resetAndClose = () => {
    setOrderResult(null)
    setErrorMsg('')
    setCustomerEmail('')
    setCustomerPhone('')
    setNote('')
    onClose()
  }

  // VietQR config mẫu thông dụng cho thanh toán tự động
  const bankId = 'MB'
  const accountNo = '0348731111'
  const accountName = 'CONG TY DICH VU AI'
  const memoContent = orderResult ? orderResult.orderCode : 'MITOM'
  const qrUrl = orderResult
    ? `https://img.vietqr.io/image/${bankId}-${accountNo}-compact2.png?amount=${orderResult.totalAmount}&addInfo=${encodeURIComponent(memoContent)}&accountName=${encodeURIComponent(accountName)}`
    : ''

  return (
    <div className="modal-backdrop" onClick={resetAndClose}>
      <div className="modal-container" onClick={(e) => e.stopPropagation()}>
        {/* Modal Header */}
        <div className="modal-header">
          <div className="modal-title-wrap">
            <h3 className="modal-title">
              {!orderResult ? 'Xác Nhận Đơn Hàng' : 'Thanh Toán Đơn Hàng Tự Động'}
            </h3>
            <span className="modal-subtitle">
              {!orderResult
                ? 'Điền thông tin nhận mã thẻ và hướng dẫn kích hoạt'
                : 'Quét mã VietQR để hệ thống tự động kích hoạt ngay lập tức'}
            </span>
          </div>
          <button type="button" className="btn-close-modal" onClick={resetAndClose}>
            <X size={20} />
          </button>
        </div>

        {!orderResult ? (
          /* Step 1: Order Form */
          <form onSubmit={handleSubmitOrder} className="modal-body">
            {/* Selected Product Summary */}
            <div className="order-summary-box">
              <div className="summary-row">
                <span className="summary-label">Mệnh giá nạp:</span>
                <span className="summary-value">{product.name}</span>
              </div>
              <div className="summary-row">
                <span className="summary-label">Gói lựa chọn:</span>
                <span className="summary-value">{plan.name}</span>
              </div>
              <div className="summary-row">
                <span className="summary-label">Khuyến mãi nhận được:</span>
                <span className="summary-value text-bonus">+5% (+{formatPrice(bonusAmount - plan.price)})</span>
              </div>
              <div className="summary-divider"></div>
              <div className="summary-row total-row">
                <span className="summary-label">Tổng thanh toán:</span>
                <span className="summary-price">{formatPrice(plan.price)}</span>
              </div>
            </div>

            {errorMsg && (
              <div className="alert-error">
                <AlertCircle size={16} />
                <span>{errorMsg}</span>
              </div>
            )}

            {/* Input Fields */}
            <div className="form-group">
              <label className="form-label" htmlFor="custEmail">
                Email nhận mã thẻ <span className="required-star">*</span>
              </label>
              <input
                id="custEmail"
                type="email"
                required
                placeholder="vidu@gmail.com"
                className="form-input"
                value={customerEmail}
                onChange={(e) => setCustomerEmail(e.target.value)}
              />
              <span className="form-hint">Mã thẻ và biên lai thanh toán sẽ được gửi tới email này.</span>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="custPhone">
                Số điện thoại Zalo (tùy chọn)
              </label>
              <input
                id="custPhone"
                type="tel"
                placeholder="0987654321"
                className="form-input"
                value={customerPhone}
                onChange={(e) => setCustomerPhone(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="custNote">
                Ghi chú thêm (nếu có)
              </label>
              <textarea
                id="custNote"
                rows={2}
                placeholder="Ghi chú thêm cho đơn hàng của bạn..."
                className="form-textarea"
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>

            <div className="modal-actions">
              <button
                type="button"
                className="btn-cancel"
                onClick={resetAndClose}
                disabled={isLoading}
              >
                Hủy bỏ
              </button>
              <button
                type="submit"
                className="btn-submit-order"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <RefreshCw size={16} className="spin-icon" />
                    <span>Đang khởi tạo đơn...</span>
                  </>
                ) : (
                  <>
                    <span>Tiếp tục thanh toán</span>
                    <ArrowRight size={16} />
                  </>
                )}
              </button>
            </div>
          </form>
        ) : (
          /* Step 2: Payment QR & Instructions */
          <div className="modal-body payment-step">
            <div className="order-created-success">
              <ShieldCheck size={28} className="text-success" />
              <div>
                <h4>Đơn hàng đã được tạo thành công!</h4>
                <p>Mã đơn hàng: <strong className="order-code-highlight">{orderResult.orderCode}</strong></p>
              </div>
            </div>

            <div className="payment-grid">
              {/* QR Code */}
              <div className="qr-container">
                <img
                  src={qrUrl}
                  alt="Mã VietQR Chuyển Khoản"
                  className="vietqr-image"
                />
                <div className="qr-guide-text">
                  <span>Mở app ngân hàng bất kỳ để quét mã</span>
                </div>
              </div>

              {/* Bank Details */}
              <div className="bank-details-box">
                <div className="bank-detail-item">
                  <span className="detail-label">Ngân hàng:</span>
                  <div className="detail-val-row">
                    <strong>MB Bank (Ngân hàng Quân Đội)</strong>
                  </div>
                </div>

                <div className="bank-detail-item">
                  <span className="detail-label">Số tài khoản:</span>
                  <div className="detail-val-row">
                    <strong className="code-text">{accountNo}</strong>
                    <button
                      type="button"
                      className="btn-copy-mini"
                      onClick={() => handleCopy(accountNo, 'stk')}
                    >
                      {copiedField === 'stk' ? <Check size={14} /> : <Copy size={14} />}
                      <span>{copiedField === 'stk' ? 'Đã chép' : 'Chép'}</span>
                    </button>
                  </div>
                </div>

                <div className="bank-detail-item">
                  <span className="detail-label">Chủ tài khoản:</span>
                  <div className="detail-val-row">
                    <strong>{accountName}</strong>
                  </div>
                </div>

                <div className="bank-detail-item">
                  <span className="detail-label">Số tiền:</span>
                  <div className="detail-val-row">
                    <strong className="price-text">{formatPrice(orderResult.totalAmount)}</strong>
                    <button
                      type="button"
                      className="btn-copy-mini"
                      onClick={() => handleCopy(String(orderResult.totalAmount), 'amount')}
                    >
                      {copiedField === 'amount' ? <Check size={14} /> : <Copy size={14} />}
                      <span>{copiedField === 'amount' ? 'Đã chép' : 'Chép'}</span>
                    </button>
                  </div>
                </div>

                <div className="bank-detail-item highlight-memo">
                  <span className="detail-label">Nội dung chuyển khoản (BẮT BUỘC):</span>
                  <div className="detail-val-row">
                    <strong className="memo-code">{orderResult.orderCode}</strong>
                    <button
                      type="button"
                      className="btn-copy-mini btn-copy-highlight"
                      onClick={() => handleCopy(orderResult.orderCode, 'memo')}
                    >
                      {copiedField === 'memo' ? <Check size={14} /> : <Copy size={14} />}
                      <span>{copiedField === 'memo' ? 'Đã chép mã' : 'Sao chép mã'}</span>
                    </button>
                  </div>
                  <span className="memo-warning">
                    * Vui lòng giữ nguyên nội dung chuyển khoản để hệ thống tự động nhận diện và kích hoạt.
                  </span>
                </div>
              </div>
            </div>

            <div className="modal-actions-payment">
              <button
                type="button"
                className="btn-check-order"
                onClick={() => {
                  const code = orderResult.orderCode
                  resetAndClose()
                  if (onSuccessCheckOrder) {
                    onSuccessCheckOrder(code)
                  } else {
                    const el = document.getElementById('tra-cuu')
                    if (el) el.scrollIntoView({ behavior: 'smooth' })
                  }
                }}
              >
                <span>Tra cứu trạng thái đơn hàng</span>
                <ArrowRight size={16} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
