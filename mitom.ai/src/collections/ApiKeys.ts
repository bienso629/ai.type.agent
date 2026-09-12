import type { CollectionConfig } from 'payload'

export const ApiKeys: CollectionConfig = {
  slug: 'api-keys',
  labels: {
    singular: 'API Key AstraFlow',
    plural: 'Quản lý Keys',
  },
  admin: {
    useAsTitle: 'name',
    defaultColumns: ['name', 'keyId', 'maskedKey', 'status', 'dailyLimit', 'monthlyLimit', 'updatedAt'],
    group: 'AstraFlow',
  },
  access: {
    // Chỉ Admin mới được xem, tạo, sửa, xóa
    read: ({ req }) => req.user?.role === 'admin',
    create: ({ req }) => req.user?.role === 'admin',
    update: ({ req }) => req.user?.role === 'admin',
    delete: ({ req }) => req.user?.role === 'admin',
  },
  hooks: {
    beforeValidate: [
      ({ data, operation }) => {
        if (operation === 'create' || !data?.keyId) {
          if (!data?.keyId) {
            data = data || {}
            data.keyId = `key-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 8)}`
          }
        }
        return data
      },
    ],
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      required: true,
      label: 'Tên Key',
    },
    {
      name: 'keyId',
      type: 'text',
      unique: true,
      label: 'Mã định danh khóa',
      defaultValue: () => `key-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 8)}`,
      admin: {
        description: 'Tự động sinh mã định danh nếu không nhập thủ công',
      },
    },
    {
      name: 'maskedKey',
      type: 'text',
      label: 'Khóa hiển thị thu gọn',
    },
    {
      name: 'secretKey',
      type: 'text',
      label: 'Khóa bí mật',
      admin: {
        description: 'Khóa bảo mật đầy đủ nếu có',
      },
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'Normal',
      options: [
        { label: 'Đang hoạt động', value: 'Normal' },
        { label: 'Đã tắt', value: 'Disabled' },
        { label: 'Hết hạn', value: 'Expired' },
      ],
      label: 'Trạng thái',
    },
    {
      name: 'permissions',
      type: 'text',
      label: 'Quyền hạn',
      defaultValue: 'Sandbox, Modelverse',
    },
    {
      name: 'dailyLimit',
      type: 'text',
      label: 'Hạn mức ngày',
      defaultValue: 'Không giới hạn',
    },
    {
      name: 'monthlyLimit',
      type: 'text',
      label: 'Hạn mức tháng',
      defaultValue: 'Không giới hạn',
    },
    {
      name: 'dailySpend',
      type: 'text',
      label: 'Chi tiêu trong ngày',
      defaultValue: '0',
    },
    {
      name: 'monthlySpend',
      type: 'text',
      label: 'Chi tiêu trong tháng',
      defaultValue: '0',
    },
    {
      name: 'modelAccessMode',
      type: 'text',
      label: 'Chế độ truy cập mô hình',
      defaultValue: 'Tất cả mô hình',
    },
    {
      name: 'expiryTime',
      type: 'text',
      label: 'Hạn sử dụng',
      defaultValue: 'Vĩnh viễn',
    },
    {
      name: 'rawResponse',
      type: 'json',
      label: 'Dữ liệu JSON gốc từ AstraFlow',
      admin: {
        readOnly: true,
      },
    },
  ],
}
