import type { CollectionConfig } from 'payload'

export const Invoices: CollectionConfig = {
  slug: 'invoices',
  admin: {
    useAsTitle: 'invoiceNumber',
    defaultColumns: ['invoiceNumber', 'order', 'invoiceEmail', 'totalAmount', 'status', 'emailSent', 'createdAt'],
  },
  access: {
    read: ({ req }) => {
      if (!req.user) return true
      if (req.user.role === 'admin') return true
      return {
        invoiceEmail: {
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
      name: 'invoiceNumber',
      type: 'text',
      required: true,
      unique: true,
      label: 'Số hóa đơn',
    },
    {
      name: 'order',
      type: 'relationship',
      relationTo: 'orders',
      label: 'Đơn hàng',
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
    },
    {
      name: 'identityNumber',
      type: 'text',
      label: 'Số CCCD / CMND',
    },
    {
      name: 'companyName',
      type: 'text',
      label: 'Tên công ty',
    },
    {
      name: 'companyTaxCode',
      type: 'text',
      label: 'Mã số thuế',
    },
    {
      name: 'companyAddress',
      type: 'text',
      label: 'Địa chỉ công ty',
    },
    {
      name: 'invoiceEmail',
      type: 'text',
      label: 'Email nhận hóa đơn',
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
      label: 'Tổng tiền gồm VAT (VNĐ)',
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'issued',
      options: [
        { label: 'Đã phát hành', value: 'issued' },
        { label: 'Đã hủy', value: 'canceled' },
      ],
      label: 'Trạng thái hóa đơn',
    },
    {
      name: 'emailSent',
      type: 'checkbox',
      defaultValue: false,
      label: 'Đã gửi email hóa đơn',
    },
    {
      name: 'note',
      type: 'textarea',
      label: 'Ghi chú',
    },
  ],
}
