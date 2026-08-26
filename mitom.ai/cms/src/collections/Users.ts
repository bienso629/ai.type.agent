import type { CollectionConfig } from 'payload'

export const Users: CollectionConfig = {
  slug: 'users',
  access: {
    create: () => true,
    read: ({ req: { user } }) => Boolean(user),
  },
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['name', 'email', 'balance', 'role', 'createdAt'],
  },
  auth: true,
  fields: [
    {
      name: 'name',
      type: 'text',
      label: 'Họ và tên',
      required: true,
    },
    {
      name: 'role',
      type: 'select',
      label: 'Vai trò',
      defaultValue: 'user',
      options: [
        { label: 'Khách hàng', value: 'user' },
        { label: 'Quản trị viên (Admin)', value: 'admin' },
      ],
      required: true,
    },
    {
      name: 'balance',
      type: 'number',
      label: 'Số dư ví (VNĐ)',
      defaultValue: 0,
      min: 0,
      admin: {
        description: 'Số tiền có sẵn trong tài khoản của khách để trừ dần khi mua hàng.',
      },
    },
  ],
}
