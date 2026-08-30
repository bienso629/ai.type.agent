import React from 'react'
import { getPayload } from 'payload'
import configPromise from '@payload-config'
import { FrontendApp, DEFAULT_PRODUCTS, Product, Category } from '@/components/frontend/FrontendApp'

export default async function HomePage() {
  let products: Product[] = DEFAULT_PRODUCTS

  try {
    const payload = await getPayload({ config: configPromise })
    const prodDocs = await payload.find({
      collection: 'products',
      where: {
        status: {
          equals: 'active',
        },
      },
      limit: 50,
    })

    if (prodDocs.docs && prodDocs.docs.length > 0) {
      products = prodDocs.docs.map((doc: any) => {
        let tag: Category = 'chat'
        const rawSlug = (doc.slug || '').toLowerCase()
        const rawName = (doc.name || '').toLowerCase()
        if (rawSlug.includes('token') || rawName.includes('token')) tag = 'token'
        else if (rawSlug.includes('image') || rawSlug.includes('midjourney') || rawName.includes('ảnh')) tag = 'image'
        else if (rawSlug.includes('cursor') || rawSlug.includes('code') || rawName.includes('lập trình')) tag = 'code'

        return {
          id: String(doc.id),
          name: doc.name,
          provider: doc.provider || 'Mì Tôm AI',
          tag,
          badge: doc.badge || undefined,
          desc: doc.desc || 'Tài khoản chính chủ kích hoạt tự động.',
          features: (doc.features || []).map((f: any) => (typeof f === 'string' ? f : f.item)),
          accent: doc.accentColor || '#34d399',
          initials: (doc.name || 'AI').substring(0, 2).toUpperCase(),
          eta: doc.eta || 'Kích hoạt ~5 phút',
        }
      })
    }
  } catch (e) {
    console.error('Lỗi khi tải products từ Payload CMS:', e)
    products = DEFAULT_PRODUCTS
  }

  const adminRoute = (await configPromise).routes?.admin || '/admin'

  return <FrontendApp products={products} adminRoute={adminRoute} />
}
