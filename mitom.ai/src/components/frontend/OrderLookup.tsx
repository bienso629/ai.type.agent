'use client'

import React, { useState } from 'react'
import { Search, RefreshCw, AlertCircle, CheckCircle, Clock, AlertTriangle, Key, ExternalLink } from 'lucide-react'

interface OrderLookupProps {
  initialCode?: string
}

export const OrderLookup: React.FC<OrderLookupProps> = ({ initialCode = '' }) => {
  const [query, setQuery] = useState(initialCode)
  const [loading, setLoading] = useState(false)
  const [results, setResults] = useState<any[] | null>(null)
  const [errorMessage, setErrorMessage] = useState('')
  const [searched, setSearched] = useState(false)

  const handleSearch = async (e?: React.FormEvent) => {
    if (e) e.preventDefault()
    if (!query.trim()) {
      setErrorMessage('Vui lòng nhập Mã đơn hàng hoặc Email để tra cứu.')
      return
    }

    setLoading(true)
    setErrorMessage('')
    setSearched(true)

    try {
      const res = await fetch(`/api/orders/lookup?q=${encodeURIComponent(query.trim())}`)
      const data = await res.json()

      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Có lỗi xảy ra khi tra cứu đơn hàng.')
      }

      setResults(data.orders || [])
    } catch (err: any) {
      setErrorMessage(err.message || 'Lỗi kết nối khi tra cứu.')
      setResults([])
    } finally {
      setLoading(false)
    }
  }

  const formatPrice = (amount: number) => {
    return new Intl.NumberFormat('vi-VN').format(amount) + 'đ'
  }

  const formatDate = (isoString: string) => {
    try {
      const d = new Date(isoString)
      return d.toLocaleString('vi-VN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    } catch {
      return isoString
    }
  }

  const renderPaymentBadge = (status: string) => {
    switch (status) {
      case 'paid':
        return (
          <span className="status-pill status-pill-success">
            <CheckCircle size={13} />
            Đã thanh toán
          </span>
        )
      case 'failed':
      case 'refunded':
        return (
          <span className="status-pill status-pill-danger">
            <AlertTriangle size={13} />
            {status === 'refunded' ? 'Đã hoàn tiền' : 'Hủy / Thất bại'}
          </span>
        )
      default:
        return (
          <span className="status-pill status-pill-warning">
            <Clock size={13} />
            Chờ thanh toán
          </span>
        )
    }
  }

  const renderFulfillmentBadge = (status: string) => {
    switch (status) {
      case 'fulfilled':
        return (
          <span className="status-pill status-pill-success">
            <CheckCircle size={13} />
            Đã kích hoạt / Bàn giao
          </span>
        )
      case 'processing':
        return (
          <span className="status-pill status-pill-info">
            <RefreshCw size={13} className="spin-icon" />
            Đang xử lý
          </span>
        )
      default:
        return (
          <span className="status-pill status-pill-neutral">
            <Clock size={13} />
            Chờ cấp mã
          </span>
        )
    }
  }

  return (
    <section id="tra-cuu" className="lookup-section">
      <div className="container lookup-container">
        <div className="section-header-center">
          <span className="section-sub-badge">Công Cụ Trực Tuyến</span>
          <h2 className="section-title">Tra Cứu Trạng Thái Đơn Hàng</h2>
          <p className="section-description">
            Nhập mã đơn hàng (ví dụ: <code className="inline-code">MT-1234ABC</code>) hoặc địa chỉ Email của bạn để kiểm tra trạng thái thanh toán và thông tin bàn giao mã thẻ.
          </p>
        </div>

        {/* Search Input Box */}
        <form onSubmit={handleSearch} className="lookup-form">
          <div className="lookup-input-wrapper">
            <Search size={20} className="lookup-search-icon" />
            <input
              type="text"
              placeholder="Nhập Mã đơn hàng (MT-XXXXXX) hoặc Email..."
              className="lookup-input"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <button type="submit" className="btn-lookup-submit" disabled={loading}>
            {loading ? (
              <>
                <RefreshCw size={16} className="spin-icon" />
                <span>Đang tìm...</span>
              </>
            ) : (
              <>
                <Search size={16} />
                <span>Tra cứu ngay</span>
              </>
            )}
          </button>
        </form>

        {errorMessage && (
          <div className="alert-error mt-4">
            <AlertCircle size={16} />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Results Container */}
        {searched && !loading && (
          <div className="lookup-results-wrap">
            {results && results.length > 0 ? (
              <div className="lookup-results-list">
                {results.map((ord) => (
                  <div key={ord.id} className="lookup-order-card">
                    <div className="order-card-header">
                      <div>
                        <span className="order-label">Mã đơn hàng:</span>
                        <strong className="order-code-text">{ord.orderCode}</strong>
                      </div>
                      <div className="order-badges">
                        {renderPaymentBadge(ord.paymentStatus)}
                        {renderFulfillmentBadge(ord.fulfillmentStatus)}
                      </div>
                    </div>

                    <div className="order-card-details">
                      <div className="detail-item">
                        <span className="label">Sản phẩm / Mệnh giá:</span>
                        <span className="value">{ord.productName} ({ord.planName})</span>
                      </div>
                      <div className="detail-item">
                        <span className="label">Tổng tiền:</span>
                        <span className="value price-value">{formatPrice(ord.totalAmount)}</span>
                      </div>
                      <div className="detail-item">
                        <span className="label">Thời gian tạo:</span>
                        <span className="value">{formatDate(ord.createdAt)}</span>
                      </div>
                    </div>

                    {/* Delivery Credentials if fulfilled */}
                    {ord.deliveryInfo ? (
                      <div className="delivery-info-box">
                        <div className="delivery-info-header">
                          <Key size={16} className="text-success" />
                          <strong>Thông tin bàn giao mã thẻ / Kích hoạt:</strong>
                        </div>
                        <pre className="delivery-info-content">{ord.deliveryInfo}</pre>
                      </div>
                    ) : ord.paymentStatus === 'paid' ? (
                      <div className="delivery-pending-box">
                        <Clock size={16} />
                        <span>Hệ thống đang tiến hành cấp mã thẻ tự động cho bạn trong ít phút.</span>
                      </div>
                    ) : (
                      <div className="delivery-unpaid-box">
                        <AlertCircle size={16} />
                        <span>Đơn hàng đang chờ thanh toán. Vui lòng chuyển khoản đúng số tiền và nội dung để hệ thống tự động kích hoạt.</span>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <div className="lookup-empty-state">
                <AlertCircle size={32} className="empty-icon" />
                <h4>Không tìm thấy đơn hàng</h4>
                <p>Không có dữ liệu đơn hàng nào khớp với từ khóa "{query}". Vui lòng kiểm tra lại mã đơn hoặc email.</p>
              </div>
            )}
          </div>
        )}
      </div>
    </section>
  )
}
