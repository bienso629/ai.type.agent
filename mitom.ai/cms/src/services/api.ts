export interface User {
  id: string
  email: string
  name: string
  role: 'user' | 'admin'
  balance: number
  created_at?: string
}

export interface Product {
  id: string
  name: string
  provider: string
  tag: 'chat' | 'image' | 'code' | 'token'
  badge?: string
  desc: string
  cost_price?: number
  price: number
  profit?: number
  features: string[]
  accent: string
  initials: string
  eta: string
  stock?: number
}

export interface Order {
  id: string
  user_id: string
  user_email: string
  product_id: string
  product_name: string
  cost_price?: number
  amount: number
  profit?: number
  status: 'pending' | 'paid' | 'completed' | 'cancelled'
  payment_method: 'balance' | 'vietqr' | 'momo' | 'zalopay'
  delivery_content?: string
  qr_code_url?: string
  payment_code?: string
  created_at: string
}

export interface Transaction {
  id: string
  user_id: string
  type: 'topup' | 'purchase' | 'refund' | 'admin_adjust'
  amount: number
  balance_before: number
  balance_after: number
  description: string
  status: 'pending' | 'success' | 'failed'
  payment_method?: string
  reference_code?: string
  created_at: string
}

const API_BASE = '/api'
const TOKEN_KEY = 'mitom_auth_token'

export const tokenStorage = {
  get: () => localStorage.getItem(TOKEN_KEY),
  set: (token: string) => localStorage.setItem(TOKEN_KEY, token),
  remove: () => localStorage.removeItem(TOKEN_KEY),
}

async function request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const token = tokenStorage.get()
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  }

  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }

  const res = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers,
  })

  const json = await res.json()
  if (!res.ok || !json.success) {
    throw new Error(json.error || 'Yêu cầu thất bại.')
  }

  return json.data !== undefined ? json.data : json
}

export const api = {
  auth: {
    login: async (email: string, password: string): Promise<{ token: string; user: User }> => {
      const data = await request<{ token: string; user: User }>('/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      })
      tokenStorage.set(data.token)
      return data
    },
    register: async (email: string, password: string, name: string): Promise<{ token: string; user: User }> => {
      const data = await request<{ token: string; user: User }>('/auth/register', {
        method: 'POST',
        body: JSON.stringify({ email, password, name }),
      })
      tokenStorage.set(data.token)
      return data
    },
    getMe: async (): Promise<User> => {
      return await request<User>('/auth/me')
    },
    logout: () => {
      tokenStorage.remove()
    },
  },

  products: {
    getAll: async (): Promise<Product[]> => {
      return await request<Product[]>('/products')
    },
    getById: async (id: string): Promise<Product> => {
      return await request<Product>(`/products/${id}`)
    },
  },

  orders: {
    create: async (productId: string, paymentMethod: 'balance' | 'vietqr' | 'momo' | 'zalopay') => {
      return await request<{
        orderId: string
        status: string
        deliveryContent?: string
        newBalance?: number
        qrCodeUrl?: string
        paymentCode?: string
        amount?: number
        productName?: string
      }>('/orders', {
        method: 'POST',
        body: JSON.stringify({ productId, paymentMethod }),
      })
    },
    getMyOrders: async (): Promise<Order[]> => {
      return await request<Order[]>('/orders/my')
    },
  },

  payments: {
    createTopUp: async (amount: number) => {
      return await request<{
        transactionId: string
        paymentCode: string
        amount: number
        bonusAmount: number
        totalCredit: number
        qrCodeUrl: string
      }>('/payments/topup', {
        method: 'POST',
        body: JSON.stringify({ amount }),
      })
    },
    confirmTopUp: async (transactionId: string) => {
      return await request<{
        transactionId: string
        newBalance: number
      }>('/payments/topup/confirm', {
        method: 'POST',
        body: JSON.stringify({ transactionId }),
      })
    },
    getMyTransactions: async (): Promise<Transaction[]> => {
      return await request<Transaction[]>('/payments/transactions')
    },
  },

  admin: {
    getStats: async () => {
      return await request<{
        stats: {
          totalUsers: number
          totalOrders: number
          totalRevenue: number
          totalCost: number
          totalProfit: number
          profitMarginPct: number
          availableKeys: number
        }
        recentOrders: Order[]
        recentTransactions: Transaction[]
      }>('/admin/stats')
    },
    getUsers: async (): Promise<User[]> => {
      return await request<User[]>('/admin/users')
    },
    updateUserBalance: async (userId: string, amount: number, reason?: string) => {
      return await request('/admin/users/balance', {
        method: 'POST',
        body: JSON.stringify({ userId, amount, reason }),
      })
    },
    updateProductPricing: async (productId: string, costPrice: number, salePrice: number) => {
      return await request('/admin/products/pricing', {
        method: 'POST',
        body: JSON.stringify({ productId, costPrice, salePrice }),
      })
    },
    getOrders: async (): Promise<Order[]> => {
      return await request<Order[]>('/admin/orders')
    },
    updateOrderStatus: async (orderId: string, status: string, deliveryContent?: string) => {
      return await request('/admin/orders/status', {
        method: 'PUT',
        body: JSON.stringify({ orderId, status, deliveryContent }),
      })
    },
    addInventoryKey: async (productId: string, keyData: string) => {
      return await request('/admin/inventory', {
        method: 'POST',
        body: JSON.stringify({ productId, keyData }),
      })
    },
    getInventoryKeys: async () => {
      return await request<any[]>('/admin/inventory')
    },
  },
}
