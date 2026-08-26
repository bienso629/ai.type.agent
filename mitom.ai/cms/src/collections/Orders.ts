import type { CollectionConfig } from 'payload'

export const Orders: CollectionConfig = {
  slug: 'orders',
  admin: {
    useAsTitle: 'id',
    defaultColumns: ['id', 'user', 'product', 'saleAmount', 'costAmount', 'netProfit', 'status', 'createdAt'],
  },
  fields: [
    {
      name: 'user',
      type: 'relationship',
      relationTo: 'users',
      label: 'Khách hàng',
      required: true,
    },
    {
      name: 'product',
      type: 'relationship',
      relationTo: 'products',
      label: 'Gói AI đã mua',
      required: true,
    },
    {
      type: 'row',
      fields: [
        {
          name: 'saleAmount',
          type: 'number',
          label: 'Doanh thu thu về (VNĐ)',
          required: true,
          admin: { width: '33%' },
        },
        {
          name: 'costAmount',
          type: 'number',
          label: 'Tiền vốn gốc (VNĐ)',
          required: true,
          admin: { width: '33%' },
        },
        {
          name: 'netProfit',
          type: 'number',
          label: 'Lợi nhuận ròng (VNĐ)',
          admin: { width: '33%', readOnly: true },
          hooks: {
            beforeChange: [
              ({ data }) => {
                if (data?.saleAmount && data?.costAmount) {
                  return Number(data.saleAmount) - Number(data.costAmount)
                }
                return 0
              },
            ],
          },
        },
      ],
    },
    {
      name: 'status',
      type: 'select',
      label: 'Trạng thái đơn',
      defaultValue: 'completed',
      options: [
        { label: 'Chờ thanh toán', value: 'pending' },
        { label: 'Đã thanh toán', value: 'paid' },
        { label: 'Đã giao Key / Hoàn tất', value: 'completed' },
        { label: 'Đã hủy', value: 'cancelled' },
      ],
      required: true,
    },
    {
      name: 'paymentMethod',
      type: 'select',
      label: 'Hình thức thanh toán',
      defaultValue: 'balance',
      options: [
        { label: 'Trừ số dư ví cá nhân', value: 'balance' },
        { label: 'Quét VietQR', value: 'vietqr' },
        { label: 'Ví Momo', value: 'momo' },
      ],
    },
    {
      name: 'deliveryKey',
      type: 'textarea',
      label: 'Thông tin tài khoản / Key giao cho khách',
    },
  ],
}
