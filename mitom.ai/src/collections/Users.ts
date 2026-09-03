import type { CollectionConfig } from 'payload'

export const Users: CollectionConfig = {
  slug: 'users',
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['email', 'name', 'authProvider', 'balance', 'role', 'createdAt'],
  },
  auth: true,
  access: {
    read: () => true,
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      label: 'Họ và tên',
    },
    {
      name: 'avatar',
      type: 'text',
      label: 'Ảnh đại diện URL',
    },
    {
      name: 'authProvider',
      type: 'select',
      defaultValue: 'local',
      options: [
        { label: 'Tài khoản Local / Mật khẩu', value: 'local' },
        { label: 'Google Account', value: 'google' },
        { label: 'Tadu Cloud', value: 'tadu' },
      ],
      label: 'Phương thức xác thực',
    },
    {
      name: 'taduUserId',
      type: 'text',
      label: 'Tadu User ID',
      admin: {
        readOnly: true,
      },
    },
    {
      name: 'googleId',
      type: 'text',
      label: 'Google ID',
      admin: {
        readOnly: true,
      },
    },
    {
      name: 'balance',
      type: 'number',
      defaultValue: 0,
      label: 'Số dư tài khoản (VNĐ)',
    },
    {
      name: 'customerCode',
      type: 'text',
      label: 'Mã khách hàng / Cú pháp nạp (Ví dụ: MITO000123)',
      admin: {
        description: 'Mã nhận diện nạp tiền tự động qua Webhook ngân hàng (Định dạng MITOxxxxxx với xxxxxx là ID người dùng)',
      },
    },
    {
      name: 'apiKey',
      type: 'text',
      label: 'API Key truy cập',
    },
    {
      name: 'role',
      type: 'select',
      defaultValue: 'user',
      options: [
        { label: 'Quản trị viên', value: 'admin' },
        { label: 'Người dùng', value: 'user' },
      ],
      label: 'Vai trò',
    },
  ],
}
