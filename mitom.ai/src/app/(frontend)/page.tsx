import React from 'react'
import configPromise from '@payload-config'
import { FrontendApp } from '@/components/frontend/FrontendApp'
import { ALL_MODELS, parseRawModels, parseSquareModels, ApiModel, rawModelsData } from '@/data/models-parser'

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

  // Gọi API ListUFSquareModelGuest để lấy đúng 49 model mạnh nhất có context length 999k+ (MaxModelLenNew >= 999)
  let squareModels: ApiModel[] = []
  try {
    const squareRes = await fetch('https://api.scloudsg.com/?Action=ListUFSquareModelGuest', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        Action: 'ListUFSquareModelGuest',
        Limit: 500,
        Offset: 0,
      }),
      signal: AbortSignal.timeout(4000),
      next: { revalidate: 300 },
    })
    if (squareRes.ok) {
      const squareData = await squareRes.json()
      const list = squareData.SquareModels || []
      const filtered49 = list.filter((m: any) => (Number(m.MaxModelLenNew) || 0) >= 999)
      if (filtered49.length > 0) {
        squareModels = parseSquareModels(filtered49, multiplier)
      }
    }
  } catch (e) {
    // Fallback sang dữ liệu lưu sẵn từ squareModelsData
  }

  if (squareModels.length === 0) {
    const fallbackData = require('@/data/square-models.json')
    squareModels = parseSquareModels(fallbackData, multiplier)
  }

  const adminRoute = (await configPromise).routes?.admin || '/admin'

  return <FrontendApp models={models} squareModels={squareModels} adminRoute={adminRoute} />
}

