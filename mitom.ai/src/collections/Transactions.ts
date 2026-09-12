import type { CollectionConfig } from 'payload'

export const Transactions: CollectionConfig = {
  slug: 'transactions',
  admin: {
    useAsTitle: 'transactionId',
    defaultColumns: ['transactionId', 'order', 'amount', 'paymentMethod', 'status', 'createdAt'],
  },
  access: {
    read: ({ req }) => {
      if (!req.user) return true
      if (req.user.role === 'admin') return true
      return {
        user: {
          equals: req.user.id,
        },
      }
    },
    create: () => true,
    update: ({ req }) => req.user?.role === 'admin',
    delete: ({ req }) => req.user?.role === 'admin',
  },
  fields: [
    {
      name: 'transactionId',
      type: 'text',
      required: true,
      unique: true,
      label: 'Mã giao dịch (Bank / VietQR / ACB / Momo)',
    },
    {
      name: 'order',
      type: 'relationship',
      relationTo: 'orders',
      label: 'Đơn hàng liên kết (nếu có)',
    },
    {
      name: 'user',
      type: 'relationship',
      relationTo: 'users',
      label: 'Người dùng được cộng tiền',
    },
    {
      name: 'amount',
      type: 'number',
      required: true,
      label: 'Số tiền thanh toán (VNĐ)',
    },
    {
      name: 'vatRate',
      type: 'number',
      defaultValue: 10,
      label: 'Thuế suất VAT (%)',
    },
    {
      name: 'vatAmount',
      type: 'number',
      label: 'Tiền thuế VAT (VNĐ)',
    },
    {
      name: 'paymentMethod',
      type: 'select',
      defaultValue: 'vietqr',
      options: [
        { label: 'VietQR / Chuyển khoản ACB (TADU)', value: 'vietqr' },
        { label: 'Webhook Ngân Hàng', value: 'bank_webhook' },
        { label: 'Momo', value: 'momo' },
        { label: 'Thẻ tín dụng / Visa', value: 'credit_card' },
        { label: 'USDT / Crypto', value: 'crypto' },
      ],
      label: 'Phương thức thanh toán',
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'pending',
      options: [
        { label: 'Chờ xác nhận', value: 'pending' },
        { label: 'Thành công', value: 'success' },
        { label: 'Thất bại', value: 'failed' },
      ],
      label: 'Trạng thái giao dịch',
    },
    {
      name: 'rawResponse',
      type: 'json',
      label: 'Dữ liệu phản hồi Webhook / Gateway',
    },
  ],
}
