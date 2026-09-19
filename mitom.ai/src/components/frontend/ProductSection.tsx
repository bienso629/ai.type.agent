'use client'

import React, { useState, useMemo } from 'react'
import { Search, Filter, Sparkles, Layers, SlidersHorizontal } from 'lucide-react'
import { ProductCard, ProductItem, PlanItem } from './ProductCard'
import { OrderModal } from './OrderModal'

interface CategoryItem {
  id: string | number
  name: string
  slug: string
  description?: string | null
}

interface ProductSectionProps {
  initialProducts: ProductItem[]
  categories: CategoryItem[]
  onOpenLookup?: (code?: string) => void
}

export const ProductSection: React.FC<ProductSectionProps> = ({
  initialProducts,
  categories,
  onOpenLookup,
}) => {
  const [selectedCategory, setSelectedCategory] = useState<string>('all')
  const [searchQuery, setSearchQuery] = useState<string>('')
  const [sortBy, setSortBy] = useState<'default' | 'price-asc' | 'price-desc'>('default')

  // Order modal states
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedProduct, setSelectedProduct] = useState<ProductItem | null>(null)
  const [selectedPlan, setSelectedPlan] = useState<PlanItem | null>(null)

  const handleSelectPlan = (product: ProductItem, plan: PlanItem) => {
    setSelectedProduct(product)
    setSelectedPlan(plan)
    setIsModalOpen(true)
  }

  const filteredProducts = useMemo(() => {
    let list = [...initialProducts]

    // Search filter
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim()
      list = list.filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.desc.toLowerCase().includes(q) ||
          (p.badge && p.badge.toLowerCase().includes(q))
      )
    }

    // Sort
    if (sortBy === 'price-asc') {
      list.sort((a, b) => {
        const priceA = a.plans && a.plans[0] ? a.plans[0].price : 0
        const priceB = b.plans && b.plans[0] ? b.plans[0].price : 0
        return priceA - priceB
      })
    } else if (sortBy === 'price-desc') {
      list.sort((a, b) => {
        const priceA = a.plans && a.plans[0] ? a.plans[0].price : 0
        const priceB = b.plans && b.plans[0] ? b.plans[0].price : 0
        return priceB - priceA
      })
    }

    return list
  }, [initialProducts, searchQuery, sortBy])

  return (
    <section id="menh-gia" className="products-section">
      <div className="container">
        {/* Section Header */}
        <div className="section-header-center">
          <span className="section-sub-badge">
            <Sparkles size={14} />
            Mệnh Giá Thẻ Cào & Gói Dịch Vụ
          </span>
          <h2 className="section-title">Danh Sách Mệnh Giá Nạp Mì Tôm AI</h2>
          <p className="section-description">
            Tất cả các mệnh giá đều được cộng trực tiếp vào ví tài khoản ngay sau khi nạp.
          </p>
        </div>

        {/* Filters and Controls */}
        <div className="products-controls-bar">
          {/* Category Tabs */}
          <div className="category-tabs-wrap">
            <button
              type="button"
              className={`cat-tab-btn ${selectedCategory === 'all' ? 'active' : ''}`}
              onClick={() => setSelectedCategory('all')}
            >
              <Layers size={15} />
              <span>Tất Cả Mệnh Giá</span>
            </button>
            {categories.map((cat) => (
              <button
                key={cat.id}
                type="button"
                className={`cat-tab-btn ${selectedCategory === cat.slug ? 'active' : ''}`}
                onClick={() => setSelectedCategory(cat.slug)}
              >
                <span>{cat.name}</span>
              </button>
            ))}
          </div>

          {/* Search & Sort */}
          <div className="search-sort-group">
            <div className="search-box-wrap">
              <Search size={16} className="search-icon-input" />
              <input
                type="text"
                placeholder="Tìm mệnh giá (20k, 50k, 100k...)"
                className="search-input-field"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>

            <div className="sort-select-wrap">
              <SlidersHorizontal size={15} className="sort-icon-input" />
              <select
                className="sort-select"
                value={sortBy}
                onChange={(e: any) => setSortBy(e.target.value)}
              >
                <option value="default">Sắp xếp: Mặc định</option>
                <option value="price-asc">Giá: Thấp đến Cao</option>
                <option value="price-desc">Giá: Cao đến Thấp</option>
              </select>
            </div>
          </div>
        </div>

        {/* Product Cards Grid */}
        {filteredProducts.length > 0 ? (
          <div className="products-grid">
            {filteredProducts.map((product) => (
              <ProductCard
                key={product.id}
                product={product}
                onSelectPlan={handleSelectPlan}
              />
            ))}
          </div>
        ) : (
          <div className="no-products-found">
            <h4>Không tìm thấy mệnh giá phù hợp</h4>
            <p>Vui lòng thử tìm kiếm với từ khóa khác.</p>
          </div>
        )}
      </div>

      {/* Checkout Order Modal */}
      <OrderModal
        isOpen={isModalOpen}
        product={selectedProduct}
        plan={selectedPlan}
        onClose={() => setIsModalOpen(false)}
        onSuccessCheckOrder={(code) => {
          if (onOpenLookup) {
            onOpenLookup(code)
          } else {
            const el = document.getElementById('tra-cuu')
            if (el) el.scrollIntoView({ behavior: 'smooth' })
          }
        }}
      />
    </section>
  )
}
