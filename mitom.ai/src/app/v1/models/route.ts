import { NextRequest, NextResponse } from 'next/server'
import { callUCloudApi } from '@/lib/ucloudClient'
import squareModelsData from '@/data/square-models.json'
import rawModelsData from '@/data/models.json'
import { parseSquareModels, parseRawModels } from '@/data/models-parser'

export const dynamic = 'force-dynamic'
export const revalidate = 0

// In-memory cache de giam do tre khi nhieu client goi lien tuc
let cachedSquareModels: any[] | null = null
let cacheTimestamp = 0
const CACHE_TTL_MS = 5 * 60 * 1000 // 5 phut

// CORS headers chuan
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-api-key, x-action, Accept',
  'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=60',
}

export async function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders,
  })
}

async function getSquareModelsList(): Promise<any[]> {
  const now = Date.now()
  if (cachedSquareModels && now - cacheTimestamp < CACHE_TTL_MS) {
    return cachedSquareModels
  }

  try {
    const res = await callUCloudApi(
      {
        Action: 'ListUFSquareModel',
        Limit: 500,
        Offset: 0,
      },
      {
        fetchOptions: {
          signal: AbortSignal.timeout(6000),
        },
      },
    )

    if (res && res.RetCode === 0 && Array.isArray(res.SquareModels) && res.SquareModels.length > 0) {
      cachedSquareModels = res.SquareModels
      cacheTimestamp = now
      return res.SquareModels
    }
  } catch (error) {
    console.error('Lỗi khi fetch ListUFSquareModel từ SCloudSG:', error)
  }

  // Fallback du lieu da dong bo trong square-models.json
  if (Array.isArray(squareModelsData) && squareModelsData.length > 0) {
    return squareModelsData
  }

  return []
}

function buildOpenAiFormat(squareList: any[]) {
  const pricingMap = new Map<string, any>()
  if (Array.isArray(rawModelsData)) {
    for (const item of rawModelsData) {
      if (item?.id) {
        pricingMap.set(String(item.id).toLowerCase(), item)
      }
    }
  }

  const data = squareList.map((item) => {
    const id = item.Name || item.Id
    const matched = pricingMap.get(String(id).toLowerCase())
    const timestamp = Math.max(Number(item.UpdateAt) || 0, Number(item.CreateAt) || 0) || 1740000000

    let pricing = matched?.pricing
    if (!pricing || !Array.isArray(pricing) || pricing.length === 0) {
      if (item.Pricing?.Prompt) {
        pricing = [
          {
            Condition: 'Mặc định',
            Description: 'Default',
            DescriptionEn: 'Default',
            Rates: [
              {
                ChargeItem: 'input',
                ChargeItemDescription: 'Input',
                ChargeItemDescriptionEn: 'Input',
                Price: Number(item.Pricing.Prompt) || 0,
                Currency: item.Pricing.Currency || 'CNY',
                Unit: item.Pricing.UnitEn || '1K Tokens',
                UnitEn: item.Pricing.UnitEn || '1K Tokens',
              },
              ...(item.Pricing?.Completion
                ? [
                    {
                      ChargeItem: 'output_text_tokens',
                      ChargeItemDescription: 'Output',
                      ChargeItemDescriptionEn: 'Output',
                      Price: Number(item.Pricing.Completion) || 0,
                      Currency: item.Pricing.Currency || 'CNY',
                      Unit: item.Pricing.UnitEn || '1K Tokens',
                      UnitEn: item.Pricing.UnitEn || '1K Tokens',
                    },
                  ]
                : []),
            ],
          },
        ]
      } else {
        pricing = []
      }
    }

    return {
      id,
      object: 'model',
      created: timestamp,
      owned_by: item.Manufacturer || 'UCloud_UModelverse',
      pricing,
      max_model_len: item.MaxModelLenNew ? Number(item.MaxModelLenNew) * 1024 : item.MaxModelLen,
      input_modalities: item.InputModalities || ['text'],
      output_modalities: item.OutputModalities || ['text'],
      capabilities: item.Capabilities || {},
    }
  })

  return {
    object: 'list',
    data,
  }
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const action = searchParams.get('Action') || request.headers.get('x-action')
  const format = searchParams.get('format')

  const squareList = await getSquareModelsList()

  // 1. Dinh dang SCloudSG chuan khi goi Action=ListUFSquareModel hoac format=square/raw
  if (action === 'ListUFSquareModel' || format === 'square' || format === 'raw') {
    return NextResponse.json(
      {
        RetCode: 0,
        Message: 'Success',
        TotalCount: squareList.length,
        SquareModels: squareList,
      },
      { headers: corsHeaders },
    )
  }

  // 2. Dinh dang parsed cho frontend / UI
  if (format === 'parsed' || format === 'app') {
    const parsed = parseSquareModels(squareList, 1, rawModelsData)
    return NextResponse.json(parsed, { headers: corsHeaders })
  }

  // 3. Dinh dang OpenAI chuan mac dinh danh cho cac client OpenAI / SDK / /v1/models
  const openAiResponse = buildOpenAiFormat(squareList)
  return NextResponse.json(openAiResponse, { headers: corsHeaders })
}

export async function POST(request: NextRequest) {
  let body: any = {}
  try {
    body = await request.json()
  } catch {
    body = {}
  }

  const { searchParams } = new URL(request.url)
  const action = body.Action || searchParams.get('Action') || request.headers.get('x-action')
  const format = body.format || searchParams.get('format')

  const squareList = await getSquareModelsList()

  if (action === 'ListUFSquareModel' || format === 'square' || format === 'raw') {
    return NextResponse.json(
      {
        RetCode: 0,
        Message: 'Success',
        TotalCount: squareList.length,
        SquareModels: squareList,
      },
      { headers: corsHeaders },
    )
  }

  if (format === 'parsed' || format === 'app') {
    const parsed = parseSquareModels(squareList, 1, rawModelsData)
    return NextResponse.json(parsed, { headers: corsHeaders })
  }

  const openAiResponse = buildOpenAiFormat(squareList)
  return NextResponse.json(openAiResponse, { headers: corsHeaders })
}
