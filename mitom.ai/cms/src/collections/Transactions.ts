import type { CollectionConfig } from 'payload'

export const Transactions: CollectionConfig = {
  slug: 'transactions',
  admin: {
    useAsTitle: 'description',
    defaultColumns: ['user', 'type', 'amount', 'balanceAfter', 'status', 'createdAt'],
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
      name: 'type',
      type: 'select',
      label: 'Loại biến động',
      options: [
        { label: 'Nạp tiền vào ví', value: 'topup' },
        { label: 'Trừ tiền mua dịch vụ', value: 'purchase' },
        { label: 'Hoàn tiền', value: 'refund' },
        { label: 'Admin điều chỉnh', value: 'admin_adjust' },
      ],
      required: true,
    },
    {
      name: 'amount',
      type: 'number',
      label: 'Số tiền biến động (VNĐ)',
      required: true,
    },
    {
      name: 'balanceBefore',
      type: 'number',
      label: 'Số dư trước giao dịch',
    },
    {
      name: 'balanceAfter',
      type: 'number',
      label: 'Số dư sau giao dịch',
    },
    {
      name: 'description',
      type: 'text',
      label: 'Nội dung giao dịch',
      required: true,
    },
    {
      name: 'status',
      type: 'select',
      label: 'Trạng thái',
      defaultValue: 'success',
      options: [
        { label: 'Thành công', value: 'success' },
        { label: 'Đang xử lý', value: 'pending' },
        { label: 'Thất bại', value: 'failed' },
      ],
    },
  ],
}
