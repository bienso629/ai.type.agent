import React from 'react'
import configPromise from '@payload-config'
import { FrontendApp } from '@/components/frontend/FrontendApp'
import { parseRawModels, parseSquareModels, ApiModel, rawModelsData, squareModelsData } from '@/data/models-parser'
import { callUCloudApi } from '@/lib/ucloudClient'
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

  // 1. Lấy thông tin giá chi tiết từ /v1/models (nếu có)
  let rawPricingList: any[] = rawModelsData
  try {
    const res = await fetch('https://api-vn-sg.mitom.ai/v1/models', {
      signal: AbortSignal.timeout(4000),
      next: { revalidate: 300 },
    })
    if (res.ok) {
      const data = await res.json()
      if (data.data && Array.isArray(data.data) && data.data.length > 0) {
        rawPricingList = data.data
      }
    }
  } catch (e) {
    console.error('Lỗi khi fetch pricing từ API mitom:', e)
  }

  // 2. Lấy danh sách model đầy đủ và chuẩn xác nhất từ API https://api.scloudsg.com/?Action=ListUFSquareModel
  let allSquareList: any[] = []
  try {
    const squareRes = await callUCloudApi(
      {
        Action: 'ListUFSquareModel',
        Limit: 500,
        Offset: 0,
      },
      {
        fetchOptions: {
          signal: AbortSignal.timeout(6000),
          next: { revalidate: 300 },
        },
      },
    )

    if (
      squareRes &&
      squareRes.RetCode === 0 &&
      Array.isArray(squareRes.SquareModels) &&
      squareRes.SquareModels.length > 0
    ) {
      allSquareList = squareRes.SquareModels
    }
  } catch (e) {
    console.error('Lỗi khi fetch ListUFSquareModel từ SCloudSG API:', e)
  }

  // Fallback sang dữ liệu lưu sẵn từ square-models.json nếu API không phản hồi
  if (allSquareList.length === 0) {
    allSquareList = squareModelsData && squareModelsData.length > 0 ? squareModelsData : []
  }

  // Parse toàn bộ danh sách models đầy đủ từ API ListUFSquareModel
  const models: ApiModel[] =
    allSquareList.length > 0
      ? parseSquareModels(allSquareList, multiplier, rawPricingList)
      : parseRawModels(rawPricingList, multiplier)

  // Danh sách model siêu ngữ cảnh (context length >= 999k) dành cho Hero Slider
  const squareModels: ApiModel[] =
    allSquareList.length > 0
      ? parseSquareModels(
          allSquareList.filter((m: any) => (Number(m.MaxModelLenNew) || 0) >= 999),
          multiplier,
          rawPricingList,
        )
      : models.filter((m) => (m.contextLength || 0) >= 999)

  const adminRoute = (await configPromise).routes?.admin || '/admin'

  return <FrontendApp models={models} squareModels={squareModels} adminRoute={adminRoute} />
}

