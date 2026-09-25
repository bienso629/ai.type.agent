import rawModelsData from './models.json'
import squareModelsData from './square-models.json'
export { rawModelsData, squareModelsData }

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
  contextLength?: number
  created?: number
  pricing: ModelPricingCondition[]
  highlightPrice?: string
}

export const MODEL_CATEGORIES: { id: ModelCategory; label: string; count?: number }[] = [
  { id: 'all', label: 'Tất cả' },
  { id: 'code', label: 'Lập trình' },
  { id: 'image', label: 'Tạo & Chỉnh sửa ảnh' },
  { id: 'video', label: 'Tạo Video & Lip-sync' },
  { id: 'audio', label: 'Giọng nói & TTS' },
  { id: 'doc', label: 'Tài liệu & OCR' },
]

function getCategory(id: string, modelCategory?: string): Exclude<ModelCategory, 'all'> {
  const cat = String(modelCategory || '').toLowerCase()
  if (cat === 'video') return 'video'
  if (cat === 'image') return 'image'
  if (cat === 'audio') return 'audio'
  if (cat === 'code') return 'code'
  if (cat === 'doc') return 'doc'

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
    lower.includes('pixverse') ||
    lower.includes('seedance') ||
    lower.includes('lip-sync')
  ) {
    return 'video'
  }
  if (lower.includes('code') || lower.includes('coder') || lower.includes('codex')) {
    return 'code'
  }
  if (
    lower.includes('image') ||
    lower.includes('seedream') ||
    lower.includes('flux') ||
    lower.includes('midjourney')
  ) {
    return 'image'
  }
  if (
    lower.includes('audio') ||
    lower.includes('speech') ||
    lower.includes('tts') ||
    lower.includes('suno') ||
    lower.includes('cicada') ||
    lower.includes('elevenlabs') ||
    lower.includes('transcribe') ||
    lower.includes('whisper')
  ) {
    return 'audio'
  }
  if (lower.includes('embed') || lower.includes('rerank') || lower.includes('bge')) {
    return 'embedding'
  }
  if (lower.includes('doc') || lower.includes('extract') || lower.includes('parse') || lower.includes('mask') || lower.includes('easydoc')) {
    return 'doc'
  }
  return 'chat'
}

function getProvider(id: string, manufacturer?: string): { provider: string; accent: string; initials: string } {
  const lower = id.toLowerCase()
  const rawMfg = String(manufacturer || '').trim()

  if (lower.includes('deepseek') || rawMfg.toLowerCase() === 'deepseek') {
    return { provider: 'DeepSeek', accent: '#0066ff', initials: 'DS' }
  }
  if (lower.includes('glm') || lower.includes('zai-org') || rawMfg.toLowerCase().includes('zhipu')) {
    return { provider: 'Zhipu AI (GLM)', accent: '#3b82f6', initials: 'GL' }
  }
  if (lower.includes('qwen') || rawMfg.toLowerCase() === 'qwen' || rawMfg.toLowerCase().includes('alibaba')) {
    return { provider: 'Alibaba (Qwen)', accent: '#ff6a00', initials: 'QW' }
  }
  if (lower.includes('doubao') || lower.includes('bytedance') || rawMfg.toLowerCase().includes('bytedance')) {
    return { provider: 'ByteDance (Doubao)', accent: '#3b82f6', initials: 'DB' }
  }
  if (lower.includes('kimi') || lower.includes('moonshot') || rawMfg.toLowerCase().includes('moonshot')) {
    return { provider: 'Moonshot AI (Kimi)', accent: '#10b981', initials: 'KM' }
  }
  if (lower.includes('minimax') || lower.includes('hailuo') || rawMfg.toLowerCase().includes('minimax')) {
    return { provider: 'MiniMax', accent: '#ef4444', initials: 'MM' }
  }
  if (lower.includes('kling') || rawMfg.toLowerCase().includes('kuaishou')) {
    return { provider: 'Kuaishou (Kling)', accent: '#f59e0b', initials: 'KL' }
  }
  if (lower.includes('vidu') || rawMfg.toLowerCase().includes('shengshu') || rawMfg.toLowerCase() === 'vidu') {
    return { provider: 'ShengShu (Vidu)', accent: '#8b5cf6', initials: 'VD' }
  }
  if (lower.includes('wan')) {
    return { provider: 'Wan-AI (Alibaba)', accent: '#06b6d4', initials: 'WN' }
  }
  if (lower.includes('ernie') || lower.includes('baidu') || rawMfg.toLowerCase().includes('baidu')) {
    return { provider: 'Baidu (ERNIE)', accent: '#2563eb', initials: 'EN' }
  }
  if (lower.includes('bge') || lower.includes('baai') || rawMfg.toLowerCase().includes('baai')) {
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
  if (lower.includes('mimo') || rawMfg.toLowerCase().includes('xiaomi')) {
    return { provider: 'Xiaomi (Mimo)', accent: '#ff6900', initials: 'XM' }
  }
  if (lower.includes('suno') || rawMfg.toLowerCase().includes('suno')) {
    return { provider: 'Suno AI', accent: '#f43f5e', initials: 'SU' }
  }
  if (lower.includes('indextts') || lower.includes('indexteam')) {
    return { provider: 'IndexTeam', accent: '#6366f1', initials: 'IX' }
  }
  if (lower.includes('gpt') || lower.includes('openai') || rawMfg.toLowerCase() === 'openai') {
    return { provider: 'OpenAI', accent: '#10a37f', initials: 'OA' }
  }
  if (lower.includes('claude') || lower.includes('anthropic') || rawMfg.toLowerCase().includes('anthropic')) {
    return { provider: 'Anthropic (Claude)', accent: '#d97706', initials: 'CL' }
  }
  if (lower.includes('gemini') || lower.includes('google') || rawMfg.toLowerCase().includes('google')) {
    return { provider: 'Google (Gemini)', accent: '#4285f4', initials: 'GM' }
  }
  if (lower.includes('grok') || lower.includes('x.ai') || rawMfg.toLowerCase().includes('x.ai')) {
    return { provider: 'xAI (Grok)', accent: '#ffffff', initials: 'GK' }
  }
  if (rawMfg && !hasChinese(rawMfg)) {
    return { provider: rawMfg, accent: '#3b82f6', initials: rawMfg.slice(0, 2).toUpperCase() }
  }
  return { provider: 'UModelverse', accent: '#34d399', initials: 'AI' }
}

function getBadge(id: string): string | undefined {
  const lower = id.toLowerCase()
  if (lower.includes('glm-5.3') || lower.includes('wan3.0') || lower.includes('deepseek-v4') || lower.includes('qwen3.8') || lower.includes('kimi-k3') || lower.includes('gpt-6') || lower.includes('opus-5-5')) {
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

function parsePricing(rawPricing: any[], multiplier: number = 1): { conditions: ModelPricingCondition[]; highlight?: string } {
  if (!rawPricing || !Array.isArray(rawPricing) || rawPricing.length === 0) {
    return { conditions: [] }
  }

  const conditions: ModelPricingCondition[] = rawPricing.map((cond) => {
    const conditionTitle = cond.DescriptionEn || cond.Description || cond.Condition || 'Mặc định'
    const rates: ModelPricingRate[] = (cond.Rates || []).map((r: any) => {
      const itemDesc = r.ChargeItemDescriptionEn || r.ChargeItemDescription || r.ChargeItem || 'Giá'
      const unit = r.UnitEn || r.Unit || 'lượt'
      const rawPrice = Number(r.Price) || 0
      const listPrice = Math.round(rawPrice * multiplier * 10000) / 10000
      return {
        item: itemDesc,
        price: listPrice,
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

function extractContextLength(id: string, rawPricing: any[]): { lengthK: number; label: string } {
  const lower = id.toLowerCase()

  // 1. Quét chi tiết từ các mức giá pricing
  if (Array.isArray(rawPricing)) {
    for (const p of rawPricing) {
      const desc = String(p.DescriptionEn || p.Description || p.Condition || '')
      // Check 1M, 2M, 20M
      const mMatches = desc.match(/(\d+(?:\.\d+)?)\s*([mM])/i)
      if (mMatches) {
        const val = parseFloat(mMatches[1])
        if (val >= 1) {
          return { lengthK: Math.round(val * 1000), label: `${val >= 1 && val % 1 === 0 ? val : val}M tokens` }
        }
      }
      const kMatches = desc.match(/(\d+(?:\.\d+)?)\s*([kK])/i)
      if (kMatches) {
        const val = parseFloat(kMatches[1])
        if (val >= 999) {
          return { lengthK: Math.round(val), label: `${Math.round(val)}K tokens` }
        }
      }
    }
  }

  // 2. Nhận diện các dòng mô hình AI có context window chuẩn từ 1M đến 2M tokens
  if (lower.includes('kimi')) {
    return { lengthK: 2000, label: '2M tokens' }
  }
  if (lower.includes('glm-5')) {
    return { lengthK: 1000, label: '1M tokens' }
  }
  if (lower.includes('deepseek-v4')) {
    return { lengthK: 1000, label: '1M tokens' }
  }
  if (lower.includes('minimax-h3') || lower.includes('minimax-m3')) {
    return { lengthK: 1000, label: '1M tokens' }
  }
  if (
    lower.includes('qwen3.8') ||
    lower.includes('qwen3.7') ||
    lower.includes('qwen3.6') ||
    lower.includes('qwen3.5')
  ) {
    return { lengthK: 1000, label: '1M tokens' }
  }
  if (lower.includes('doubao-seed-evolving') || lower.includes('doubao-seed-2-1') || lower.includes('doubao-seed-1-6')) {
    return { lengthK: 2000, label: '2M tokens' }
  }
  if (lower.includes('mimo-v2')) {
    return { lengthK: 1000, label: '1M tokens' }
  }

  return { lengthK: 128, label: '128K tokens' }
}

export function parseRawModels(rawList: any[], multiplier: number = 1): ApiModel[] {
  return rawList.map((item) => {
    const id = item.id
    const category = getCategory(id)
    const { provider, accent, initials } = getProvider(id)
    const badge = getBadge(id)
    const { conditions, highlight } = parsePricing(item.pricing, multiplier)
    const { lengthK, label: contextLabel } = extractContextLength(id, item.pricing)

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
      context: contextLabel,
      contextLength: lengthK,
      created: Number(item.created) || 0,
      pricing: conditions,
      highlightPrice: highlight,
    }
  })
}

const MODEL_VI_DESCRIPTIONS: Record<string, string> = {
  'deepseek-v4.1-flash':
    'Mô hình DeepSeek V4.1 Flash với cấu trúc siêu nhẹ, tích hợp năng lực thị giác đa phương thức tự nhiên, tốc độ phản hồi cực nhanh cùng thông lượng lớn.',
  'gemini-omni-1.1-flash-preview':
    'Mô hình thế hệ mới của Google hỗ trợ tạo và chỉnh sửa video tương tác đa phương thức thông qua hội thoại ngôn ngữ tự nhiên nhiều vòng.',
  'gpt-4.1-nano':
    'Mô hình có kích thước gọn nhất trong dòng GPT-4.1 của OpenAI, tối ưu hóa độ trễ và chi phí cực thấp cho các ứng dụng AI nhẹ.',
  'gpt-4.1-mini':
    'Mô hình gọn nhẹ của OpenAI với hiệu năng vượt trội GPT-4o, tốc độ xử lý nhanh, cửa sổ ngữ cảnh 1M tokens phù hợp cho tác vụ agent và văn bản dài.',
  'openai/gpt-4.1':
    'Mô hình đa phương thức hợp nhất của OpenAI hỗ trợ hiểu văn bản, hình ảnh, âm thanh và thực thi luồng công việc phức tạp.',
  'gpt-5.5':
    'Mô hình flagship thế hệ mới từ OpenAI, tối ưu chuyên sâu cho công việc thực tế phức tạp và thực thi tác vụ tự chủ end-to-end với hiệu suất suy luận cao.',
  'gpt-6-astra':
    'Mô hình thông minh và căn chỉnh cao nhất của OpenAI, xuất sắc trong vận hành máy tính, duyệt web, lập trình kỹ thuật và nghiên cứu chuyên sâu.',
  'gpt-5.6-sol':
    'Mô hình hàng đầu trong dòng GPT-5.6, lý tưởng cho các luồng công việc chuyên môn phức tạp và suy luận logic đa bước.',
  'gpt-5.6-terra':
    'Mô hình cân bằng hoàn hảo giữa trí tuệ nhân tạo và chi phí vận hành, đáp ứng tối ưu cho các hệ thống ứng dụng quy mô lớn.',
  'gpt-5.6-luna':
    'Mô hình thiết kế tối ưu chi phí cho các tác vụ khối lượng lớn với tốc độ phản hồi thần tốc.',
  'gpt-5.4':
    'Mô hình ngôn ngữ lớn flagship từ OpenAI với năng lực vượt bậc về lập trình, suy luận logic và khả năng xử lý văn bản, tài liệu khổng lồ.',
  'gemini-3.8-flash':
    'Mô hình chủ lực thông minh nhất của Google dành cho tác vụ agent quy mô lớn, kỹ thuật phần mềm và lập trình dài hơi với tốc độ Flash.',
  'claude-fable-5-1':
    'Mô hình hiệu năng cao từ Anthropic dành cho lập trình phức tạp và công việc tri thức, vượt trội về lập kế hoạch tự chủ và sử dụng công cụ.',
  'glm-5.3-flash':
    'Mô hình đa phương thức tự nhiên đầu tiên của dòng GLM-5 từ Zhipu AI, tích hợp kiến trúc thưa và chú ý tuyến tính giúp code và phản hồi siêu nhanh.',
  'qwen3.7-plus':
    'Mô hình agent đa phương thức từ Alibaba Qwen, hỗ trợ đầu vào ảnh, video, màn hình, web và văn bản, khép kín quy trình cảm nhận, suy luận và hành động.',
  'qwen3.7-max':
    'Mô hình flagship hàng đầu của Alibaba Qwen tối ưu cho kỷ nguyên agent thông minh, hỗ trợ ngữ cảnh siêu dài 1M tokens và cơ chế suy nghĩ kép.',
}

function hasChinese(text: string): boolean {
  return /[\u4e00-\u9fff]/.test(text || '')
}

export function parseSquareModels(
  squareList: any[],
  multiplier: number = 1,
  rawPricingList?: any[],
): ApiModel[] {
  const pricingMap = new Map<string, any>()
  if (rawPricingList && Array.isArray(rawPricingList)) {
    for (const item of rawPricingList) {
      if (item && item.id) {
        pricingMap.set(String(item.id).toLowerCase(), item)
      }
    }
  }

  return squareList.map((item) => {
    const id = item.Name || item.Id
    const category = getCategory(id, item.ModelCategory)
    const { provider, accent, initials } = getProvider(id, item.Manufacturer)

    // Đảm bảo tên hãng bằng tiếng Anh / tiếng Việt, không chứa tiếng Trung
    const rawManufacturer = String(item.Manufacturer || '')
    const manufacturer = hasChinese(rawManufacturer) || !rawManufacturer ? provider : rawManufacturer

    const badge = item.MaxModelLenNew >= 999 ? 'Siêu ngữ cảnh' : getBadge(id)

    // Context length từ MaxModelLenNew hoặc MaxModelLen
    const maxLenNew = Number(item.MaxModelLenNew) || 0
    let contextLabel = '128K tokens'
    let lengthK = 128

    if (maxLenNew >= 999) {
      lengthK = maxLenNew >= 999 && maxLenNew <= 2000 ? maxLenNew : Math.round((item.MaxModelLen || 1048576) / 1000)
      contextLabel = `${Math.round(lengthK / 1000) >= 1 ? Math.round(lengthK / 1000) + 'M' : lengthK + 'K'} tokens`
    } else if (item.MaxModelLen >= 999000) {
      lengthK = Math.round(item.MaxModelLen / 1000)
      contextLabel = `${Math.round(lengthK / 1000)}M tokens`
    }

    // Mô tả 100% tiếng Việt, loại bỏ toàn bộ mô tả gốc tiếng Trung từ API
    let description = MODEL_VI_DESCRIPTIONS[id]
    if (!description) {
      const rawDesc = item.SimpleDescribe || item.Describe || ''
      if (rawDesc && !hasChinese(rawDesc)) {
        description = rawDesc
      } else {
        description = `Mô hình ${id} phát triển bởi ${manufacturer}, trang bị cửa sổ ngữ cảnh cực lớn ${contextLabel}, tối ưu hóa cho xử lý văn bản dài và suy luận đa bước.`
      }
    }

    // Tích hợp bảng giá chi tiết nếu khớp từ /v1/models hoặc rawModelsData
    const matchedRaw = pricingMap.get(id.toLowerCase())
    let conditions: ModelPricingCondition[] = []
    let highlightPrice: string = 'Tính theo token'

    if (matchedRaw?.pricing && Array.isArray(matchedRaw.pricing)) {
      const parsedPricing = parsePricing(matchedRaw.pricing, multiplier)
      conditions = parsedPricing.conditions
      if (parsedPricing.highlight) {
        highlightPrice = parsedPricing.highlight
      }
    } else if (item.Pricing?.Prompt) {
      const promptPrice = Number(item.Pricing.Prompt) * multiplier
      highlightPrice = promptPrice > 0 ? `${promptPrice.toFixed(4)} CNY/1k` : 'Tính theo token'
    }

    const timestamp = Math.max(Number(item.UpdateAt) || 0, Number(item.CreateAt) || 0)

    // Tên hiển thị luôn dùng Model ID (tiếng Anh chuẩn), loại bỏ ChineseName
    return {
      id,
      name: id,
      provider: manufacturer,
      category,
      badge,
      description,
      accent,
      initials,
      context: contextLabel,
      contextLength: lengthK,
      created: timestamp,
      pricing: conditions,
      highlightPrice,
    }
  })
}

export const ALL_MODELS: ApiModel[] =
  squareModelsData && Array.isArray(squareModelsData) && squareModelsData.length > 0
    ? parseSquareModels(squareModelsData, 1, rawModelsData)
    : parseRawModels(rawModelsData)

