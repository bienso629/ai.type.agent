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
        <p className="mt-3 text-xs leading-relaxed text-muted-foreground line-clamp-3">
          {model.description}
        </p>
      </div>

      {/* Footer Actions */}
      <div className="mt-5 pt-3 border-t border-border">
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
