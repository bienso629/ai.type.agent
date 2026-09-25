import crypto from 'crypto'

export interface UCloudApiParams {
  Action: string
  [key: string]: any
}

/**
 * Hàm tính toán chữ ký số chuẩn SHA1 theo thuật toán của UCloud / SCloudSG:
 * 1. Sắp xếp toàn bộ keys theo thứ tự alphabet (bỏ Signature).
 * 2. Ghép chuỗi Params: key + value (không có ký tự phân cách).
 * 3. Nối PrivateKey vào cuối chuỗi: key1value1key2value2...privateKey.
 * 4. Băm SHA1 và chuyển thành mã hex lowercase.
 */
export function generateUCloudSignature(params: Record<string, any>, privateKey: string): string {
  const sortedKeys = Object.keys(params)
    .filter((k) => k !== 'Signature')
    .sort()

  let rawString = ''
  for (const key of sortedKeys) {
    const val = params[key]
    if (val !== undefined && val !== null) {
      if (Array.isArray(val)) {
        val.forEach((item, idx) => {
          rawString += `${key}.${idx}${item}`
        })
      } else {
        rawString += `${key}${val}`
      }
    }
  }

  rawString += privateKey
  return crypto.createHash('sha1').update(rawString, 'utf-8').digest('hex')
}

export interface UCloudRequestOptions {
  publicKey?: string
  privateKey?: string
  baseUrl?: string
  fetchOptions?: RequestInit & { next?: { revalidate?: number | false; tags?: string[] } }
}

/**
 * Gửi request tới UCloud / AstraFlow API Gateway
 */
export async function callUCloudApi<T = any>(
  params: UCloudApiParams,
  options: UCloudRequestOptions = {},
): Promise<T> {
  const publicKey = options.publicKey || process.env.UCLOUD_PUBLIC_KEY || process.env.ASTRAFLOW_PUBLIC_KEY || ''
  const privateKey = options.privateKey || process.env.UCLOUD_PRIVATE_KEY || process.env.ASTRAFLOW_PRIVATE_KEY || ''
  const baseUrl = options.baseUrl || process.env.ASTRAFLOW_API_URL || 'https://api.scloudsg.com/'

  const fullParams: Record<string, any> = {
    ...params,
    PublicKey: publicKey,
  }

  if (privateKey) {
    fullParams.Signature = generateUCloudSignature(fullParams, privateKey)
  }

  const url = new URL(baseUrl)
  Object.keys(fullParams).forEach((key) => {
    if (fullParams[key] !== undefined && fullParams[key] !== null) {
      url.searchParams.append(key, String(fullParams[key]))
    }
  })

  const { fetchOptions } = options
  const res = await fetch(url.toString(), {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      ...(fetchOptions?.headers || {}),
    },
    ...fetchOptions,
  })

  const json = await res.json()
  return json as T
}
