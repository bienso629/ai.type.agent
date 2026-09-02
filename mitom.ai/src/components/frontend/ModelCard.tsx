'use client'

import React, { useState } from 'react'
import { ApiModel } from '@/data/models-parser'

export function ModelCard({
  model,
  onCopy,
}: {
  model: ApiModel
  onCopy: (id: string) => void
}) {
  const [showPricingDetails, setShowPricingDetails] = useState(false)
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(model.id)
    setCopied(true)
    onCopy(model.id)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <article className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border bg-card p-5 transition-all duration-300 hover:border-primary/50 hover:-translate-y-1">
      <div
        className="pointer-events-none absolute -right-16 -top-16 h-40 w-40 rounded-xl opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-20"
        style={{ background: model.accent }}
      />

      <div>
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="overflow-hidden">
            <div className="flex items-center gap-2">
              <h3
                className="truncate font-mono text-sm font-bold text-foreground"
                title={model.id}
              >
                {model.id}
              </h3>
            </div>
            <span className="text-xs text-muted-foreground">{model.provider}</span>
          </div>
          {model.badge && (
            <span className="inline-flex h-5 shrink-0 items-center rounded-sm bg-primary/15 px-2 font-mono text-[10px] font-semibold text-primary leading-none">
              {model.badge}
            </span>
          )}
        </div>

        {/* Description */}
        <p className="mt-3 text-xs leading-relaxed text-muted-foreground">
          {model.description}
        </p>

        {/* Pricing snippet */}
        {model.pricing.length > 0 && (
          <div className="mt-4 rounded-lg border border-border/80 bg-secondary/30 p-3">
            <div className="flex items-center justify-between gap-2 text-xs">
              <span className="shrink-0 font-mono text-[11px] font-medium text-muted-foreground whitespace-nowrap">Bảng giá API:</span>
              <button
                type="button"
                onClick={() => setShowPricingDetails(!showPricingDetails)}
                className="shrink-0 font-mono text-[11px] font-semibold text-primary hover:underline whitespace-nowrap"
              >
                {showPricingDetails ? 'Thu gọn ▲' : 'Xem chi tiết ▼'}
              </button>
            </div>

            {/* Concise preview */}
            {!showPricingDetails && model.highlightPrice && (
              <div className="mt-2 flex items-center justify-between rounded border border-border/40 bg-background/50 font-mono text-xs">
                <span className="text-muted-foreground">Giá cơ bản:</span>
                <span className="font-bold text-emerald">{model.highlightPrice}</span>
              </div>
            )}

            {/* Expanded Pricing Table */}
            {showPricingDetails && (
              <div className="mt-2.5 space-y-3 border-t border-border/50 pt-2.5 text-[11px]">
                {model.pricing.map((p, idx) => (
                  <div key={idx} className="space-y-1.5">
                    {model.pricing.length > 1 && (
                      <div className="px-1 py-0.5 font-mono text-[10px] font-bold text-primary">
                        {p.condition}
                      </div>
                    )}
                    <div className="overflow-hidden rounded border border-border/50 bg-background/40">
                      <table className="w-full text-left font-mono">
                        <thead>
                          <tr className="border-b border-border/50 bg-secondary/50 text-[10px] uppercase text-muted-foreground">
                            <th className="font-semibold">Mục tính phí</th>
                            <th className="text-right font-semibold">Đơn giá</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-border/30 text-muted-foreground">
                          {p.rates.map((r, rIdx) => (
                            <tr key={rIdx} className="hover:bg-secondary/30 transition-colors">
                              <td className="text-foreground/80 font-medium">{r.item}</td>
                              <td className="text-right font-bold text-foreground whitespace-nowrap">
                                {r.price} {r.currency}/{r.unit}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Footer Actions */}
      <div className="mt-4 pt-3 border-t border-border">
        <div className="flex items-center justify-between gap-2">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium text-emerald">
            <span
              className="h-1.5 w-1.5 rounded-full bg-emerald"
              style={{ animation: 'tokenpulse 2s ease-in-out infinite' }}
            />{' '}
            Sẵn sàng
          </span>

          <button
            type="button"
            onClick={handleCopy}
            className="flex items-center gap-1.5 rounded border border-border bg-secondary/80 px-2.5 py-1 font-mono text-xs font-medium text-secondary-foreground transition-colors hover:border-primary/50 hover:bg-secondary"
          >
            {copied ? (
              <span className="text-emerald font-semibold">Đã chép ID</span>
            ) : (
              <span>Sao chép ID</span>
            )}
          </button>
        </div>
      </div>
    </article>
  )
}
