'use client'

import React, { useState } from 'react'
import { Check, Zap, Sparkles, Clock, ArrowRight, ShieldCheck } from 'lucide-react'

export interface PlanItem {
  id?: string
  name: string
  price: number
  originalPrice?: number | null
  discount?: string | null
  isPopular?: boolean | null
}

export interface FeatureItem {
  id?: string
  item: string
}

export interface ProductItem {
  id: string | number
  name: string
  slug: string
  provider: string
  badge?: string | null
  desc: string
  plans?: PlanItem[] | null
  features?: FeatureItem[] | null
  accentColor?: string | null
  eta?: string | null
  status?: string | null
}

interface ProductCardProps {
  product: ProductItem
  onSelectPlan: (product: ProductItem, plan: PlanItem) => void
}

export const ProductCard: React.FC<ProductCardProps> = ({ product, onSelectPlan }) => {
  const plans = product.plans && product.plans.length > 0 ? product.plans : [
    {
      name: product.name,
      price: 50000,
      originalPrice: 50000,
      isPopular: false,
    }
  ]

  const [selectedPlanIndex, setSelectedPlanIndex] = useState(0)
  const currentPlan = plans[selectedPlanIndex] || plans[0]

  const formatPrice = (amount: number) => {
    return new Intl.NumberFormat('vi-VN').format(amount) + 'đ'
  }


  const isPopular = currentPlan.isPopular || product.badge === 'Bán chạy' || product.badge === 'VIP'

  return (
    <div
      className={`product-card ${isPopular ? 'product-card-popular' : ''}`}
      style={{ '--card-accent': product.accentColor || '#10b981' } as React.CSSProperties}
    >
      {/* Top badges */}
      <div className="card-top-bar">
        {product.badge && (
          <span className="card-badge">
            <Sparkles size={13} />
            {product.badge}
          </span>
        )}
        {isPopular && <span className="card-badge-popular">HOT NHẤT</span>}
        <span className="card-provider">{product.provider || 'Mì Tôm AI'}</span>
      </div>

      {/* Title & Desc */}
      <div className="card-header">
        <h3 className="card-title">{product.name}</h3>
        <p className="card-desc">{product.desc}</p>
      </div>

      {/* Plan selection if multiple */}
      {plans.length > 1 && (
        <div className="card-plans-tabs">
          {plans.map((p, idx) => (
            <button
              key={idx}
              type="button"
              className={`plan-tab-btn ${selectedPlanIndex === idx ? 'active' : ''}`}
              onClick={() => setSelectedPlanIndex(idx)}
            >
              {p.name}
            </button>
          ))}
        </div>
      )}

      {/* Pricing block */}
      <div className="card-pricing-block">
        <div className="card-price-row">
          <span className="card-price-main">{formatPrice(currentPlan.price)}</span>
          {currentPlan.discount && (
            <span className="card-discount-tag">{currentPlan.discount}</span>
          )}
        </div>
      </div>

      {/* ETA & Status */}
      <div className="card-eta-row">
        <div className="eta-item">
          <Clock size={14} />
          <span>{product.eta || 'Kích hoạt ngay'}</span>
        </div>
        <div className="status-item">
          <ShieldCheck size={14} />
          <span>Tự động 24/7</span>
        </div>
      </div>

      {/* Feature list */}
      {product.features && product.features.length > 0 && (
        <ul className="card-features-list">
          {product.features.map((feat, idx) => (
            <li key={idx} className="feature-item">
              <span className="feature-check-icon">
                <Check size={14} />
              </span>
              <span className="feature-text">{feat.item}</span>
            </li>
          ))}
        </ul>
      )}

      {/* Order CTA */}
      <div className="card-footer">
        <button
          type="button"
          className="btn-order-now"
          onClick={() => onSelectPlan(product, currentPlan)}
        >
          <Zap size={16} />
          <span>Nạp Mệnh Giá Này</span>
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  )
}
