import type { CollectionConfig } from 'payload'

export const Users: CollectionConfig = {
  slug: 'users',
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['name', 'email', 'role', 'balance', 'createdAt'],
  },
  auth: true,
  fields: [
    {
      name: 'name',
      type: 'text',
      label: 'Họ tên',
    },
    {
      name: 'avatar',
      type: 'text',
      label: 'Ảnh đại diện',
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
      label: 'Số dư ví (VNĐ)',
    },
    {
      name: 'role',
      type: 'select',
      defaultValue: 'user',
      options: [
        { label: 'Quản trị viên', value: 'admin' },
        { label: 'Khách hàng', value: 'user' },
      ],
      label: 'Vai trò',
    },
  ],
}
