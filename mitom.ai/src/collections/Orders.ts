import type { CollectionConfig } from 'payload'

export const Orders: CollectionConfig = {
  slug: 'orders',
  admin: {
    useAsTitle: 'orderCode',
    defaultColumns: ['orderCode', 'customerEmail', 'product', 'totalAmount', 'paymentStatus', 'fulfillmentStatus', 'createdAt'],
  },
  access: {
    read: () => true,
  },
  fields: [
    {
      name: 'orderCode',
      type: 'text',
      required: true,
      unique: true,
      label: 'Mã đơn hàng',
    },
    {
      name: 'customerEmail',
      type: 'email',
      required: true,
      label: 'Email khách hàng',
    },
    {
      name: 'customerPhone',
      type: 'text',
      label: 'Số điện thoại',
    },
    {
      name: 'product',
      type: 'relationship',
      relationTo: 'products',
      required: true,
      label: 'Sản phẩm',
    },
    {
      name: 'planName',
      type: 'text',
      required: true,
      label: 'Gói đã chọn',
    },
    {
      name: 'totalAmount',
      type: 'number',
      required: true,
      label: 'Tổng tiền (VNĐ)',
    },
    {
      name: 'paymentStatus',
      type: 'select',
      defaultValue: 'pending',
      options: [
        { label: 'Chờ thanh toán', value: 'pending' },
        { label: 'Đã thanh toán', value: 'paid' },
        { label: 'Thất bại / Hủy', value: 'failed' },
        { label: 'Đã hoàn tiền', value: 'refunded' },
      ],
      label: 'Trạng thái thanh toán',
    },
    {
      name: 'fulfillmentStatus',
      type: 'select',
      defaultValue: 'unfulfilled',
      options: [
        { label: 'Chưa cấp tài khoản', value: 'unfulfilled' },
        { label: 'Đang xử lý', value: 'processing' },
        { label: 'Đã giao hàng / Đã kích hoạt', value: 'fulfilled' },
      ],
      label: 'Trạng thái giao hàng',
    },
    {
      name: 'deliveryInfo',
      type: 'textarea',
      label: 'Thông tin bàn giao (Tài khoản / Mật khẩu / API Key bảo mật)',
    },
    {
      name: 'note',
      type: 'textarea',
      label: 'Ghi chú đơn hàng',
    },
  ],
}
