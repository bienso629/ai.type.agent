import type { CollectionConfig } from 'payload'

export const Orders: CollectionConfig = {
  slug: 'orders',
  admin: {
    useAsTitle: 'orderCode',
    defaultColumns: ['orderCode', 'customerEmail', 'product', 'totalAmount', 'paymentStatus', 'fulfillmentStatus', 'createdAt'],
  },
  access: {
    read: ({ req }) => {
      if (!req.user) return true
      if (req.user.role === 'admin') return true
      return {
        customerEmail: {
          equals: req.user.email,
        },
      }
    },
    create: () => true,
    update: ({ req }) => req.user?.role === 'admin',
    delete: ({ req }) => req.user?.role === 'admin',
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
      name: 'subtotal',
      type: 'number',
      label: 'Tiền trước thuế (VNĐ)',
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
      name: 'totalAmount',
      type: 'number',
      required: true,
      label: 'Tổng tiền thanh toán gồm VAT (VNĐ)',
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
      name: 'customerType',
      type: 'select',
      defaultValue: 'personal',
      options: [
        { label: 'Cá nhân', value: 'personal' },
        { label: 'Công ty / Doanh nghiệp', value: 'company' },
      ],
      label: 'Đối tượng khách hàng',
    },
    {
      name: 'customerName',
      type: 'text',
      label: 'Họ và tên cá nhân',
      admin: {
        condition: (data) => data?.customerType === 'personal',
      },
    },
    {
      name: 'identityNumber',
      type: 'text',
      label: 'Số CCCD / CMND cá nhân',
      admin: {
        condition: (data) => data?.customerType === 'personal',
      },
    },
    {
      name: 'invoiceEmail',
      type: 'text',
      label: 'Email nhận hóa đơn điện tử',
    },
    {
      name: 'companyName',
      type: 'text',
      label: 'Tên công ty / Doanh nghiệp',
      admin: {
        condition: (data) => data?.customerType === 'company',
      },
    },
    {
      name: 'companyTaxCode',
      type: 'text',
      label: 'Mã số thuế công ty (MST)',
      admin: {
        condition: (data) => data?.customerType === 'company',
      },
    },
    {
      name: 'companyAddress',
      type: 'text',
      label: 'Địa chỉ công ty xuất hóa đơn',
      admin: {
        condition: (data) => data?.customerType === 'company',
      },
    },
    {
      name: 'note',
      type: 'textarea',
      label: 'Ghi chú đơn hàng',
    },
  ],
}
