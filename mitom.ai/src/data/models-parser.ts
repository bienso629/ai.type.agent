import rawModelsData from './models.json'

export type ModelCategory = 'all' | 'chat' | 'code' | 'image' | 'video' | 'audio' | 'embedding' | 'doc'

export interface ModelPricingRate {
  item: string
  price: number
  currency: string
  unit: string
}

export interface ModelPricingCondition {
  condition: string
  rates: ModelPricingRate[]
}

export interface ApiModel {
  id: string
  name: string
  provider: string
  category: Exclude<ModelCategory, 'all'>
  badge?: string
  description: string
  accent: string
  initials: string
  context?: string
  pricing: ModelPricingCondition[]
  highlightPrice?: string
}

export const MODEL_CATEGORIES: { id: ModelCategory; label: string; count?: number }[] = [
  { id: 'all', label: 'Tất cả model' },
  { id: 'chat', label: 'LLM Chat & Trí tuệ' },
  { id: 'code', label: 'Lập trình (Code)' },
  { id: 'image', label: 'Tạo & Chỉnh sửa ảnh' },
  { id: 'video', label: 'Tạo Video & Lip-sync' },
  { id: 'audio', label: 'Giọng nói & TTS' },
  { id: 'embedding', label: 'Embedding & Rerank' },
  { id: 'doc', label: 'Tài liệu & OCR' },
]

function getCategory(id: string): Exclude<ModelCategory, 'all'> {
  const lower = id.toLowerCase()
  if (
    lower.includes('video') ||
    lower.includes('i2v') ||
    lower.includes('t2v') ||
    lower.includes('r2v') ||
    lower.includes('kling') ||
    lower.includes('vidu') ||
    lower.includes('wan') ||
    lower.includes('hailuo') ||
    lower.includes('lip-sync')
  ) {
    return 'video'
  }
  if (lower.includes('code') || lower.includes('coder')) {
    return 'code'
  }
  if (lower.includes('image') || lower.includes('seedream')) {
    return 'image'
  }
  if (lower.includes('audio') || lower.includes('speech') || lower.includes('tts') || lower.includes('cicada')) {
    return 'audio'
  }
  if (lower.includes('embed') || lower.includes('rerank') || lower.includes('bge')) {
    return 'embedding'
  }
  if (lower.includes('doc') || lower.includes('extract') || lower.includes('parse') || lower.includes('mask')) {
    return 'doc'
  }
  return 'chat'
}

function getProvider(id: string): { provider: string; accent: string; initials: string } {
  const lower = id.toLowerCase()
  if (lower.includes('deepseek')) {
    return { provider: 'DeepSeek', accent: '#0066ff', initials: 'DS' }
  }
  if (lower.includes('glm') || lower.includes('zai-org')) {
    return { provider: 'Zhipu AI (GLM)', accent: '#3b82f6', initials: 'GL' }
  }
  if (lower.includes('qwen')) {
    return { provider: 'Alibaba (Qwen)', accent: '#ff6a00', initials: 'QW' }
  }
  if (lower.includes('doubao') || lower.includes('bytedance')) {
    return { provider: 'ByteDance (Doubao)', accent: '#3b82f6', initials: 'DB' }
  }
  if (lower.includes('kimi') || lower.includes('moonshot')) {
    return { provider: 'Moonshot AI (Kimi)', accent: '#10b981', initials: 'KM' }
  }
  if (lower.includes('minimax') || lower.includes('hailuo') || lower.includes('speech-')) {
    return { provider: 'MiniMax', accent: '#ef4444', initials: 'MM' }
  }
  if (lower.includes('kling')) {
    return { provider: 'Kuaishou (Kling)', accent: '#f59e0b', initials: 'KL' }
  }
  if (lower.includes('vidu')) {
    return { provider: 'ShengShu (Vidu)', accent: '#8b5cf6', initials: 'VD' }
  }
  if (lower.includes('wan')) {
    return { provider: 'Wan-AI (Alibaba)', accent: '#06b6d4', initials: 'WN' }
  }
  if (lower.includes('ernie') || lower.includes('baidu')) {
    return { provider: 'Baidu (ERNIE)', accent: '#2563eb', initials: 'EN' }
  }
  if (lower.includes('bge') || lower.includes('baai')) {
    return { provider: 'BAAI', accent: '#64748b', initials: 'BG' }
  }
  if (lower.includes('cicada')) {
    return { provider: 'Cicada AI', accent: '#ec4899', initials: 'CC' }
  }
  if (lower.includes('easydoc')) {
    return { provider: 'EasyDoc AI', accent: '#14b8a6', initials: 'ED' }
  }
  if (lower.includes('happyhorse')) {
    return { provider: 'HappyHorse', accent: '#f97316', initials: 'HH' }
  }
  if (lower.includes('mimo')) {
    return { provider: 'Mimo AI', accent: '#a855f7', initials: 'MI' }
  }
  if (lower.includes('indextts') || lower.includes('indexteam')) {
    return { provider: 'IndexTeam', accent: '#6366f1', initials: 'IX' }
  }
  return { provider: 'UModelverse', accent: '#34d399', initials: 'AI' }
}

function getBadge(id: string): string | undefined {
  const lower = id.toLowerCase()
  if (lower.includes('glm-5.3') || lower.includes('wan3.0') || lower.includes('deepseek-v4') || lower.includes('qwen3.8') || lower.includes('kimi-k3')) {
    return 'Mới nhất'
  }
  if (lower.includes('flash') || lower.includes('turbo') || lower.includes('lightning') || lower.includes('fast')) {
    return 'Tốc độ cao'
  }
  if (lower.includes('pro') || lower.includes('max') || lower.includes('prime')) {
    return 'Hiệu năng cao'
  }
  if (lower.includes('coder') || lower.includes('code')) {
    return 'Chuyên Code'
  }
  if (lower.includes('vision') || lower.includes('vl')) {
    return 'Đa phương thức'
  }
  return undefined
}

function parsePricing(rawPricing: any[]): { conditions: ModelPricingCondition[]; highlight?: string } {
  if (!rawPricing || !Array.isArray(rawPricing) || rawPricing.length === 0) {
    return { conditions: [] }
  }

  const conditions: ModelPricingCondition[] = rawPricing.map((cond) => {
    const conditionTitle = cond.DescriptionEn || cond.Description || cond.Condition || 'Mặc định'
    const rates: ModelPricingRate[] = (cond.Rates || []).map((r: any) => {
      const itemDesc = r.ChargeItemDescriptionEn || r.ChargeItemDescription || r.ChargeItem || 'Giá'
      const unit = r.UnitEn || r.Unit || 'lượt'
      return {
        item: itemDesc,
        price: r.Price,
        currency: r.Currency || 'CNY',
        unit: unit,
      }
    })
    return {
      condition: conditionTitle,
      rates,
    }
  })

  let highlight: string | undefined
  const firstRate = conditions[0]?.rates?.[0]
  if (firstRate) {
    highlight = `${firstRate.price} ${firstRate.currency}/${firstRate.unit}`
  }

  return { conditions, highlight }
}

export function parseRawModels(rawList: any[]): ApiModel[] {
  return rawList.map((item) => {
    const id = item.id
    const category = getCategory(id)
    const { provider, accent, initials } = getProvider(id)
    const badge = getBadge(id)
    const { conditions, highlight } = parsePricing(item.pricing)

    let description = `Mô hình AI ${provider} được tối ưu hóa cho tác vụ ${category}. Sẵn sàng kết nối qua OpenAI-compatible API.`
    if (category === 'video') {
      description = `Mô hình sinh và xử lý video độ phân giải cao từ văn bản / hình ảnh của ${provider}.`
    } else if (category === 'code') {
      description = `Mô hình chuyên dụng cho lập trình, debug và sinh mã nguồn chất lượng cao của ${provider}.`
    } else if (category === 'image') {
      description = `Mô hình sinh ảnh và chỉnh sửa hình ảnh chi tiết của ${provider}.`
    } else if (category === 'audio') {
      description = `Mô hình chuyển đổi văn bản thành giọng nói (TTS) và xử lý âm thanh tự nhiên.`
    } else if (category === 'embedding') {
      description = `Mô hình vector embedding và xếp hạng lại (reranking) phục vụ tìm kiếm ngữ nghĩa, RAG.`
    } else if (category === 'doc') {
      description = `Mô hình phân tích, trích xuất cấu trúc văn bản và xử lý tài liệu thông minh.`
    }

    return {
      id,
      name: id,
      provider,
      category,
      badge,
      description,
      accent,
      initials,
      pricing: conditions,
      highlightPrice: highlight,
    }
  })
}

export const ALL_MODELS: ApiModel[] = parseRawModels(rawModelsData)
