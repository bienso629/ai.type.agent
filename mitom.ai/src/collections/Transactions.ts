import type { CollectionConfig } from 'payload'

export const Transactions: CollectionConfig = {
  slug: 'transactions',
  admin: {
    useAsTitle: 'transactionId',
    defaultColumns: ['transactionId', 'order', 'amount', 'paymentMethod', 'status', 'createdAt'],
  },
  access: {
    read: () => true,
  },
  fields: [
    {
      name: 'transactionId',
      type: 'text',
      required: true,
      unique: true,
      label: 'Mã giao dịch (Bank / QR / SePay / Momo)',
    },
    {
      name: 'order',
      type: 'relationship',
      relationTo: 'orders',
      required: true,
      label: 'Đơn hàng liên kết',
    },
    {
      name: 'amount',
      type: 'number',
      required: true,
      label: 'Số tiền thanh toán (VNĐ)',
    },
    {
      name: 'paymentMethod',
      type: 'select',
      defaultValue: 'vietqr',
      options: [
        { label: 'VietQR / Chuyển khoản ngân hàng', value: 'vietqr' },
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
