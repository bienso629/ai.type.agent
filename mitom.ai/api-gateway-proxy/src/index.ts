import express, { Request, Response } from 'express'
import cors from 'cors'
import dotenv from 'dotenv'

dotenv.config()

const app = express()
const PORT = process.env.PORT || 8008
const UPSTREAM_BASE_URL = process.env.UPSTREAM_BASE_URL || 'https://api-us-ca.umodelverse.ai/v1'

app.use(cors())
app.use(express.json({ limit: '50mb' }))
app.use(express.urlencoded({ extended: true, limit: '50mb' }))

/**
 * Trích xuất API Key từ các header chuẩn (x-api-key hoặc Authorization Bearer)
 */
function extractApiKey(req: Request): string | null {
  const xApiKey = req.headers['x-api-key']
  if (typeof xApiKey === 'string' && xApiKey.trim()) {
    return xApiKey.trim()
  }

  const authHeader = req.headers['authorization']
  if (typeof authHeader === 'string') {
    if (authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7).trim()
    }
    return authHeader.trim()
  }

  return null
}

/**
 * Health check & Ping
 */
app.get('/', (req: Request, res: Response) => {
  res.json({
    status: 'online',
    service: 'Mì Tôm AI Gateway Reverse Proxy',
    version: '1.0.0',
    upstream: UPSTREAM_BASE_URL,
    timestamp: new Date().toISOString(),
  })
})

/**
 * Xử lý mọi yêu cầu /v1/*: Forward trực tiếp sang upstream umodelverse
 * Toàn bộ việc kiểm tra API Key, quyền hạn, quota và số dư do upstream umodelverse đảm nhiệm
 */
app.all('/v1/*', async (req: Request, res: Response): Promise<void> => {
  const subPath = req.params[0]
  const apiKey = extractApiKey(req)

  if (!apiKey) {
    res.status(401).json({
      error: {
        message: 'Bạn chưa cung cấp API Key. Vui lòng truyền header x-api-key hoặc Authorization: Bearer [API_KEY].',
        type: 'authentication_error',
        code: 'missing_api_key',
      },
    })
    return
  }

  const targetUrl = `${UPSTREAM_BASE_URL}/${subPath}`
  const forwardHeaders: Record<string, string> = {
    'Content-Type': req.headers['content-type'] || 'application/json',
    'Accept': req.headers['accept'] || 'application/json',
    'Authorization': `Bearer ${apiKey}`,
  }

  try {
    const fetchOptions: RequestInit = {
      method: req.method,
      headers: forwardHeaders,
    }

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      fetchOptions.body = typeof req.body === 'object' ? JSON.stringify(req.body) : req.body
    }

    const upstreamResponse = await fetch(targetUrl, fetchOptions)

    // Xử lý Streaming (SSE: text/event-stream) nếu client yêu cầu stream
    const isStream = upstreamResponse.headers.get('content-type')?.includes('text/event-stream')

    if (isStream && upstreamResponse.body) {
      res.setHeader('Content-Type', 'text/event-stream')
      res.setHeader('Cache-Control', 'no-cache')
      res.setHeader('Connection', 'keep-alive')

      const reader = upstreamResponse.body.getReader()
      const decoder = new TextDecoder()

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        const chunk = decoder.decode(value, { stream: true })
        res.write(chunk)
      }
      res.end()
      return
    }

    // Xử lý Non-streaming (JSON hoặc Text phản hồi từ upstream)
    const resContentType = upstreamResponse.headers.get('content-type') || ''
    if (resContentType.includes('application/json')) {
      const data = await upstreamResponse.json()
      res.status(upstreamResponse.status).json(data)
    } else {
      const text = await upstreamResponse.text()
      res.status(upstreamResponse.status).send(text)
    }
  } catch (error: any) {
    console.error(`[Gateway Forward Error -> ${targetUrl}]:`, error)
    res.status(502).json({
      error: {
        message: 'Lỗi trong quá trình forward request tới upstream umodelverse: ' + error?.message,
        type: 'gateway_error',
        code: 'bad_gateway',
      },
    })
  }
})

app.listen(PORT, () => {
  console.log(`[Mì Tôm AI Gateway] Proxy đang chạy trên cổng ${PORT}`)
  console.log(`[Mì Tôm AI Gateway] Upstream đích: ${UPSTREAM_BASE_URL}`)
})
