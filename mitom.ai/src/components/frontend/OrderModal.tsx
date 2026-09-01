'use client'

import React, { useState, useEffect } from 'react'
import { X, Check, Copy, AlertCircle, ArrowRight, ShieldCheck, QrCode, RefreshCw } from 'lucide-react'
import { ProductItem, PlanItem } from './ProductCard'
import { useAuth } from '@/context/AuthContext'

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
  const { user } = useAuth()
  const [customerEmail, setCustomerEmail] = useState(user?.email || '')
  const [customerPhone, setCustomerPhone] = useState('')
  const [note, setNote] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [errorMsg, setErrorMsg] = useState('')
  const [orderResult, setOrderResult] = useState<any>(null)
  const [copiedField, setCopiedField] = useState<string | null>(null)

  useEffect(() => {
    if (isOpen && user?.email && !customerEmail) {
      setCustomerEmail(user.email)
    }
  }, [isOpen, user])

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
    setCustomerEmail(user?.email || '')
    setCustomerPhone('')
    setNote('')
    onClose()
  }

  // VietQR config cho thanh toán tự động
  const bankId = 'MBBank'
  const accountNo = '0938414436'
  const accountName = 'NGUYEN NGOC THANH VY'
  const memoContent = orderResult ? orderResult.orderCode : 'MITOM'
  const qrUrl = orderResult
    ? `https://vietqr.app/img?bank=${bankId}&acc=${accountNo}&template=&showinfo=true&holder=${encodeURIComponent(accountName)}&amount=${orderResult.totalAmount}&memo=${encodeURIComponent(memoContent)}`
    : ''

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-md animate-in fade-in duration-200 overflow-y-auto" onClick={resetAndClose}>
      <div 
        className={`relative w-full overflow-hidden rounded-2xl border border-border bg-card shadow-2xl transition-all my-8 ${
          !orderResult ? 'max-w-lg' : 'max-w-2xl'
        }`} 
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <div className="flex flex-col gap-0.5">
            <h3 className="font-display text-lg font-bold text-foreground">
              {!orderResult ? 'Xác Nhận Đơn Hàng' : 'Thanh Toán Đơn Hàng Tự Động'}
            </h3>
            <span className="text-xs text-muted-foreground">
              {!orderResult
                ? 'Điền thông tin nhận mã thẻ và hướng dẫn kích hoạt'
                : 'Quét mã VietQR để hệ thống tự động kích hoạt ngay lập tức'}
            </span>
          </div>
          <button 
            type="button" 
            className="rounded-lg p-1.5 text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors" 
            onClick={resetAndClose}
          >
            <X size={20} />
          </button>
        </div>

        {!orderResult ? (
          /* Step 1: Order Form */
          <form onSubmit={handleSubmitOrder} className="p-6 space-y-4">
            {/* Selected Product Summary */}
            <div className="rounded-xl border border-border bg-secondary/40 p-4 space-y-2.5">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Mệnh giá nạp:</span>
                <span className="font-semibold text-foreground">{product.name}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Gói lựa chọn:</span>
                <span className="font-semibold text-foreground">{plan.name}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Khuyến mãi nhận được:</span>
                <span className="font-semibold text-emerald">+5% (+{formatPrice(bonusAmount - plan.price)})</span>
              </div>
              <div className="border-t border-border pt-2.5 flex items-baseline justify-between">
                <span className="text-sm font-bold text-foreground">Tổng thanh toán:</span>
                <span className="font-display text-xl font-black text-primary">{formatPrice(plan.price)}</span>
              </div>
            </div>

            {errorMsg && (
              <div className="flex items-center gap-2 rounded-xl border border-rose-500/40 bg-rose-500/10 p-3 text-xs text-rose-400">
                <AlertCircle size={16} className="shrink-0" />
                <span>{errorMsg}</span>
              </div>
            )}

            {/* Input Fields */}
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-foreground block" htmlFor="custEmail">
                Email nhận mã thẻ <span className="text-rose-400">*</span>
              </label>
              <input
                id="custEmail"
                type="email"
                required
                placeholder="vidu@gmail.com"
                className="w-full rounded-xl border border-border bg-secondary/30 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 focus:border-primary focus:outline-none"
                value={customerEmail}
                onChange={(e) => setCustomerEmail(e.target.value)}
              />
              <span className="text-[11px] text-muted-foreground block">Mã thẻ và biên lai thanh toán sẽ được gửi tới email này.</span>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-foreground block" htmlFor="custPhone">
                Số điện thoại Zalo (tùy chọn)
              </label>
              <input
                id="custPhone"
                type="tel"
                placeholder="0987654321"
                className="w-full rounded-xl border border-border bg-secondary/30 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 focus:border-primary focus:outline-none"
                value={customerPhone}
                onChange={(e) => setCustomerPhone(e.target.value)}
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-foreground block" htmlFor="custNote">
                Ghi chú thêm (nếu có)
              </label>
              <textarea
                id="custNote"
                rows={2}
                placeholder="Ghi chú thêm cho đơn hàng của bạn..."
                className="w-full rounded-xl border border-border bg-secondary/30 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 focus:border-primary focus:outline-none resize-none"
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                className="rounded-xl border border-border px-4 py-2.5 text-sm font-semibold text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors"
                onClick={resetAndClose}
                disabled={isLoading}
              >
                Hủy bỏ
              </button>
              <button
                type="submit"
                className="glow-button inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <RefreshCw size={16} className="animate-spin" />
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
          <div className="p-6 space-y-6">
            <div className="flex items-center gap-3 rounded-xl border border-emerald/30 bg-emerald/10 p-4">
              <ShieldCheck size={28} className="text-emerald shrink-0" />
              <div>
                <h4 className="text-sm font-bold text-foreground">Đơn hàng đã được tạo thành công!</h4>
                <p className="text-xs text-muted-foreground">Mã đơn hàng: <strong className="text-primary font-mono font-bold">{orderResult.orderCode}</strong></p>
              </div>
            </div>

            {/* VietQR Fullwidth Hero Box */}
            <div className="w-full text-center flex flex-col items-center justify-center">
              <div className="w-full max-w-sm aspect-square relative flex items-center justify-center">
                <img
                  src={qrUrl}
                  alt="Mã VietQR Chuyển Khoản"
                  className="w-full h-full object-contain rounded-xl"
                />
              </div>
              <div className="mt-4 flex items-center justify-center gap-2 font-medium text-sm text-muted-foreground px-4 py-2">
                <QrCode size={16} className="text-primary" />
                <span>Mở ứng dụng ngân hàng bất kỳ để quét mã VietQR tự động</span>
              </div>
            </div>

            {/* Bank Details */}
            <div className="rounded-xl border border-border bg-secondary/30 p-4 space-y-3">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-sm border-b border-border/50 pb-2.5">
                <span className="text-muted-foreground text-xs">Ngân hàng:</span>
                <strong className="text-foreground font-semibold">MB Bank (Ngân hàng Quân Đội)</strong>
              </div>

              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-sm border-b border-border/50 pb-2.5">
                <span className="text-muted-foreground text-xs">Số tài khoản:</span>
                <div className="flex items-center gap-2">
                  <strong className="font-mono text-base font-bold text-foreground">{accountNo}</strong>
                  <button
                    type="button"
                    className="inline-flex items-center gap-1 rounded border border-border bg-secondary px-2 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
                    onClick={() => handleCopy(accountNo, 'stk')}
                  >
                    {copiedField === 'stk' ? <Check size={13} className="text-emerald" /> : <Copy size={13} />}
                    <span>{copiedField === 'stk' ? 'Đã chép' : 'Chép'}</span>
                  </button>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-sm border-b border-border/50 pb-2.5">
                <span className="text-muted-foreground text-xs">Chủ tài khoản:</span>
                <strong className="text-foreground font-semibold">{accountName}</strong>
              </div>

              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-sm border-b border-border/50 pb-2.5">
                <span className="text-muted-foreground text-xs">Số tiền thanh toán:</span>
                <div className="flex items-center gap-2">
                  <strong className="font-display text-lg font-black text-primary">{formatPrice(orderResult.totalAmount)}</strong>
                  <button
                    type="button"
                    className="inline-flex items-center gap-1 rounded border border-border bg-secondary px-2 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
                    onClick={() => handleCopy(String(orderResult.totalAmount), 'amount')}
                  >
                    {copiedField === 'amount' ? <Check size={13} className="text-emerald" /> : <Copy size={13} />}
                    <span>{copiedField === 'amount' ? 'Đã chép' : 'Chép'}</span>
                  </button>
                </div>
              </div>

              <div className="rounded-xl border border-primary/40 bg-primary/10 p-3.5 space-y-2">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <span className="text-xs font-bold text-foreground">Nội dung chuyển khoản (BẮT BUỘC):</span>
                  <div className="flex items-center gap-2">
                    <strong className="font-mono text-base font-black text-primary">{orderResult.orderCode}</strong>
                    <button
                      type="button"
                      className="inline-flex items-center gap-1 rounded bg-primary px-2.5 py-1 text-xs font-bold text-primary-foreground hover:brightness-110 transition-all"
                      onClick={() => handleCopy(orderResult.orderCode, 'memo')}
                    >
                      {copiedField === 'memo' ? <Check size={13} /> : <Copy size={13} />}
                      <span>{copiedField === 'memo' ? 'Đã chép mã' : 'Sao chép mã'}</span>
                    </button>
                  </div>
                </div>
                <p className="text-[11px] text-muted-foreground leading-relaxed">
                  * Vui lòng giữ nguyên nội dung chuyển khoản để hệ thống tự động nhận diện và kích hoạt đơn hàng trong vài giây.
                </p>
              </div>
            </div>

            <div className="pt-2">
              <button
                type="button"
                className="glow-button w-full inline-flex items-center justify-center gap-2 rounded-xl bg-primary py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.01]"
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
