import React from 'react'
import configPromise from '@payload-config'
import { FrontendApp } from '@/components/frontend/FrontendApp'
import { ALL_MODELS, parseRawModels, ApiModel, rawModelsData } from '@/data/models-parser'

import { getPayload } from 'payload'
import { getListPriceMultiplier } from '@/lib/currency'

export default async function HomePage() {
  let multiplier = getListPriceMultiplier()
  try {
    const payload = await getPayload({ config: configPromise })
    const settings = await payload.findGlobal({ slug: 'system-settings' })
    if (settings && (settings as any).listPriceMultiplier && Number((settings as any).listPriceMultiplier) >= 1) {
      multiplier = Number((settings as any).listPriceMultiplier)
    }
  } catch {
    // Fallback multiplier từ getListPriceMultiplier()
  }

  let models: ApiModel[] = parseRawModels(rawModelsData, multiplier)

  try {
    const res = await fetch('https://api-vn-sg.mitom.ai/v1/models', {
      next: { revalidate: 300 },
    })
    if (res.ok) {
      const data = await res.json()
      if (data.data && Array.isArray(data.data) && data.data.length > 0) {
        models = parseRawModels(data.data, multiplier)
      }
    }
  } catch (e) {
    console.error('Lỗi khi fetch models từ API:', e)
    models = parseRawModels(rawModelsData, multiplier)
  }

  const adminRoute = (await configPromise).routes?.admin || '/admin'

  return <FrontendApp models={models} adminRoute={adminRoute} />
}
