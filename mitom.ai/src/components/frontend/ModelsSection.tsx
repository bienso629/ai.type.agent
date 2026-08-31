'use client'

import React, { useState, useMemo, useEffect } from 'react'
import { ApiModel, MODEL_CATEGORIES, ModelCategory } from '@/data/models-parser'
import { ModelCard } from './ModelCard'

const ITEMS_PER_PAGE = 12

export function ModelsSection({
  models,
  onSelectModel,
}: {
  models: ApiModel[]
  onSelectModel?: (m: ApiModel) => void
}) {
  const [activeCategory, setActiveCategory] = useState<ModelCategory>('all')
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedProvider, setSelectedProvider] = useState<string>('all')
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const [currentPage, setCurrentPage] = useState<number>(1)

  // Extract list of unique providers
  const providers = useMemo(() => {
    const set = new Set<string>()
    models.forEach((m) => set.add(m.provider))
    return ['all', ...Array.from(set).sort()]
  }, [models])

  // Filter models
  const filteredModels = useMemo(() => {
    return models.filter((m) => {
      // Category filter
      if (activeCategory !== 'all' && m.category !== activeCategory) {
        return false
      }
      // Provider filter
      if (selectedProvider !== 'all' && m.provider !== selectedProvider) {
        return false
      }
      // Search query
      if (searchQuery.trim() !== '') {
        const q = searchQuery.toLowerCase().trim()
        const matchId = m.id.toLowerCase().includes(q)
        const matchProvider = m.provider.toLowerCase().includes(q)
        const matchDesc = m.description.toLowerCase().includes(q)
        if (!matchId && !matchProvider && !matchDesc) {
          return false
        }
      }
      return true
    })
  }, [models, activeCategory, selectedProvider, searchQuery])

  // Reset về trang 1 khi lọc thay đổi
  useEffect(() => {
    setCurrentPage(1)
  }, [activeCategory, selectedProvider, searchQuery])

  // Phân trang
  const totalPages = Math.ceil(filteredModels.length / ITEMS_PER_PAGE) || 1
  const paginatedModels = useMemo(() => {
    const start = (currentPage - 1) * ITEMS_PER_PAGE
    return filteredModels.slice(start, start + ITEMS_PER_PAGE)
  }, [filteredModels, currentPage])

  const handleCopied = (id: string) => {
    setCopiedId(id)
    setTimeout(() => setCopiedId(null), 2500)
  }

  const handlePageChange = (page: number) => {
    if (page < 1 || page > totalPages) return
    setCurrentPage(page)
    const el = document.getElementById('models')
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' })
    }
  }

  // Tạo danh sách các số trang hiển thị
  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) {
        pages.push(i)
      }
    } else {
      pages.push(1)
      if (currentPage > 3) {
        pages.push('...')
      }
      const start = Math.max(2, currentPage - 1)
      const end = Math.min(totalPages - 1, currentPage + 1)
      for (let i = start; i <= end; i++) {
        pages.push(i)
      }
      if (currentPage < totalPages - 2) {
        pages.push('...')
      }
      pages.push(totalPages)
    }
    return pages
  }

  return (
    <section id="models" className="mx-auto max-w-7xl px-5 py-20 md:px-8">
      {/* Section Header */}
      <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span className="font-mono text-xs uppercase tracking-widest text-primary">
              // Danh mục Model API có sẵn
            </span>
            <span className="inline-flex items-center gap-1 rounded bg-emerald/15 px-2 py-0.5 font-mono text-[11px] font-bold text-emerald">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> {models.length} Models Online
            </span>
          </div>
          <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
            Các mô hình AI sẵn sàng kết nối
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted-foreground">
            Hệ thống hỗ trợ đầy đủ các model DeepSeek, GLM-5, Qwen, Doubao, Kling, Wan, Vidu và MiniMax. Chuẩn định dạng OpenAI API qua endpoint{' '}
            <code className="rounded bg-secondary/80 px-1.5 py-0.5 font-mono text-xs text-primary">
              https://api-us-ca.umodelverse.ai/v1
            </code>
            .
          </p>
        </div>

        {/* Search input & Provider dropdown */}
        <div className="flex flex-col sm:flex-row gap-3 w-full lg:w-auto">
          <div className="relative min-w-[240px]">
            <input
              type="text"
              placeholder="Tìm kiếm model, hãng..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-md border border-border bg-card px-3.5 py-2.5 pl-9 text-sm text-foreground placeholder:text-muted-foreground transition-colors focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
            <svg
              className="absolute left-3 top-3 h-4 w-4 text-muted-foreground"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
              />
            </svg>
            {searchQuery && (
              <button
                type="button"
                onClick={() => setSearchQuery('')}
                className="absolute right-3 top-2.5 text-xs text-muted-foreground hover:text-foreground"
              >
                Xóa
              </button>
            )}
          </div>

          <select
            value={selectedProvider}
            onChange={(e) => setSelectedProvider(e.target.value)}
            className="rounded-md border border-border bg-card px-3 py-2 text-sm text-foreground transition-colors focus:border-primary focus:outline-none"
          >
            <option value="all">Tất cả nhà cung cấp ({providers.length - 1})</option>
            {providers.filter((p) => p !== 'all').map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Category Tabs */}
      <div className="mt-8 flex flex-wrap gap-2 border-b border-border pb-4">
        {MODEL_CATEGORIES.map((c) => {
          const count =
            c.id === 'all'
              ? models.length
              : models.filter((m) => m.category === c.id).length

          return (
            <button
              key={c.id}
              onClick={() => setActiveCategory(c.id)}
              className={`glow-button-secondary inline-flex h-8 items-center gap-2 rounded-md border px-3.5 text-xs font-medium transition-all ${
                activeCategory === c.id
                  ? 'border-primary bg-primary text-primary-foreground shadow-sm'
                  : 'border-border bg-card text-secondary-foreground hover:border-primary/50'
              }`}
            >
              <span className="leading-none">{c.label}</span>
              <span
                className={`inline-flex h-4 min-w-4 items-center justify-center rounded-full px-1.5 font-mono text-[10px] leading-none ${
                  activeCategory === c.id
                    ? 'bg-primary-foreground/20 text-primary-foreground'
                    : 'bg-secondary text-muted-foreground'
                }`}
              >
                {count}
              </span>
            </button>
          )
        })}
      </div>

      {/* Quick notice bar for copied ID */}
      {copiedId && (
        <div className="mt-4 rounded-md border border-emerald/40 bg-emerald/10 px-4 py-2 text-xs text-emerald font-mono flex items-center justify-between">
          <span>Đã sao chép Model ID: <strong>{copiedId}</strong></span>
          <span>Dùng trực tiếp trong payload API hoặc cấu hình Cline / Cursor</span>
        </div>
      )}

      {/* Models Grid */}
      {filteredModels.length > 0 ? (
        <>
          <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {paginatedModels.map((m) => (
              <ModelCard key={m.id} model={m} onCopy={handleCopied} />
            ))}
          </div>

          {/* Pagination Controls */}
          {totalPages > 1 && (
            <div className="mt-10 flex flex-col sm:flex-row items-center justify-between gap-4 border-t border-border pt-6">
              <div className="text-xs text-muted-foreground font-mono">
                Hiển thị <span className="font-semibold text-foreground">{(currentPage - 1) * ITEMS_PER_PAGE + 1}</span> - <span className="font-semibold text-foreground">{Math.min(currentPage * ITEMS_PER_PAGE, filteredModels.length)}</span> trên <span className="font-semibold text-foreground">{filteredModels.length}</span> mô hình
              </div>

              <div className="flex items-center gap-1.5">
                <button
                  type="button"
                  onClick={() => handlePageChange(currentPage - 1)}
                  disabled={currentPage === 1}
                  className="rounded-md border border-border bg-card px-3 py-1.5 text-xs font-medium text-secondary-foreground transition-colors hover:border-primary/50 disabled:opacity-40 disabled:hover:border-border"
                >
                  Trước
                </button>

                <div className="flex items-center gap-1">
                  {getPageNumbers().map((p, idx) => {
                    if (p === '...') {
                      return (
                        <span key={`ellipsis-${idx}`} className="px-2 py-1 text-xs text-muted-foreground font-mono">
                          ...
                        </span>
                      )
                    }

                    const pageNum = Number(p)
                    const isActive = pageNum === currentPage

                    return (
                      <button
                        key={pageNum}
                        type="button"
                        onClick={() => handlePageChange(pageNum)}
                        className={`min-w-[32px] rounded-md border px-2.5 py-1.5 font-mono text-xs font-semibold transition-all ${
                          isActive
                            ? 'border-primary bg-primary text-primary-foreground shadow-sm'
                            : 'border-border bg-card text-secondary-foreground hover:border-primary/50'
                        }`}
                      >
                        {pageNum}
                      </button>
                    )
                  })}
                </div>

                <button
                  type="button"
                  onClick={() => handlePageChange(currentPage + 1)}
                  disabled={currentPage === totalPages}
                  className="rounded-md border border-border bg-card px-3 py-1.5 text-xs font-medium text-secondary-foreground transition-colors hover:border-primary/50 disabled:opacity-40 disabled:hover:border-border"
                >
                  Sau
                </button>
              </div>
            </div>
          )}
        </>
      ) : (
        <div className="mt-12 rounded-xl border border-dashed border-border p-12 text-center">
          <div className="font-mono text-sm text-muted-foreground">
            Không tìm thấy model phù hợp với từ khóa &ldquo;{searchQuery}&rdquo;.
          </div>
          <button
            type="button"
            onClick={() => {
              setSearchQuery('')
              setActiveCategory('all')
              setSelectedProvider('all')
            }}
            className="mt-4 text-xs text-primary underline"
          >
            Đặt lại bộ lọc tìm kiếm
          </button>
        </div>
      )}
    </section>
  )
}
