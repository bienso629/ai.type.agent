import type { GlobalConfig } from 'payload'

export const SystemSettings: GlobalConfig = {
  slug: 'system-settings',
  label: 'Cài đặt hệ thống',
  admin: {
    group: 'Cài đặt',
  },
  access: {
    read: () => true,
    update: ({ req }) => req.user?.role === 'admin',
  },
  fields: [
    {
      name: 'usdRate',
      type: 'number',
      label: 'Tỷ giá USD trên VNĐ',
      defaultValue: 26000,
      required: true,
      admin: {
        description: 'Tỷ giá áp dụng khi quy đổi tiền nạp VNĐ sang hạn mức USD gọi các model API',
      },
    },
    {
      name: 'siteName',
      type: 'text',
      label: 'Tên hệ thống',
      defaultValue: 'Mì Tôm AI',
    },
    {
      name: 'supportZalo',
      type: 'text',
      label: 'Hotline / Zalo hỗ trợ',
      defaultValue: '0908.888.888',
    },
  ],
}
