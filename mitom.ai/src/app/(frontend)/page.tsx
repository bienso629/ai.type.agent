import React from 'react'
import configPromise from '@payload-config'
import { FrontendApp } from '@/components/frontend/FrontendApp'
import { ALL_MODELS, parseRawModels, ApiModel } from '@/data/models-parser'

export default async function HomePage() {
  let models: ApiModel[] = ALL_MODELS

  try {
    const res = await fetch('https://api-vn-sg.mitom.ai/v1/models', {
      next: { revalidate: 300 },
    })
    if (res.ok) {
      const data = await res.json()
      if (data.data && Array.isArray(data.data) && data.data.length > 0) {
        models = parseRawModels(data.data)
      }
    }
  } catch (e) {
    console.error('Lỗi khi fetch models từ API:', e)
    models = ALL_MODELS
  }

  const adminRoute = (await configPromise).routes?.admin || '/admin'

  return <FrontendApp models={models} adminRoute={adminRoute} />
}
