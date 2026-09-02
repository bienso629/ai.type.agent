'use client'

import React, { useState, useMemo, useRef } from 'react'
import { ApiModel, MODEL_CATEGORIES, ModelCategory } from '@/data/models-parser'
import { ModelCard } from './ModelCard'

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

  const handleCopied = (id: string) => {
    setCopiedId(id)
    setTimeout(() => setCopiedId(null), 2500)
  }

  return (
    <section id="models" className="w-full">
      {/* Search input & Provider dropdown */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4 pb-6 border-b border-border">
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center gap-1 rounded bg-emerald/15 px-2.5 py-1 font-mono text-xs font-bold text-emerald">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> {models.length} Models Sẵn sàng
          </span>
          <span className="font-mono text-xs text-muted-foreground">
            Chuẩn OpenAI API
          </span>
        </div>

        <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
          <div className="relative min-w-[260px]">
            <input
              type="text"
              placeholder="Tìm kiếm model, hãng..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-md border border-border bg-card px-3.5 py-2 pl-9 text-sm text-foreground placeholder:text-muted-foreground transition-colors focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
            <svg
              className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground"
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
          </div>

          <select
            value={selectedProvider}
            onChange={(e) => setSelectedProvider(e.target.value)}
            className="rounded-md border border-border bg-card px-3 py-2 text-xs font-mono text-foreground transition-colors focus:border-primary focus:outline-none"
          >
            {providers.map((p) => (
              <option key={p} value={p}>
                {p === 'all' ? 'Tất cả các hãng' : p}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Category Tabs */}
      <div className="mt-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-border pb-4">
        <div className="flex flex-wrap gap-2">
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

        {/* Total models count */}
        {filteredModels.length > 0 && (
          <div className="flex items-center gap-2 self-end sm:self-auto shrink-0 font-mono text-xs text-muted-foreground">
            Hiển thị: <strong className="text-primary font-bold">{filteredModels.length}</strong> / {models.length} model
          </div>
        )}
      </div>

      {/* Quick notice bar for copied ID */}
      {copiedId && (
        <div className="mt-4 rounded-md border border-emerald/40 bg-emerald/10 px-4 py-2 text-xs text-emerald font-mono flex items-center justify-between">
          <span>Đã sao chép Model ID: <strong>{copiedId}</strong></span>
          <span>Dùng trực tiếp trong payload API hoặc cấu hình Cline / Cursor</span>
        </div>
      )}

      {/* Full Models Grid - Xổ hết danh sách */}
      {filteredModels.length > 0 ? (
        <div className="mt-8 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filteredModels.map((m) => (
            <ModelCard key={m.id} model={m} onCopy={handleCopied} />
          ))}
        </div>
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
