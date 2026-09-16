import type { CollectionConfig } from 'payload'
import { generateCustomerCode } from '@/lib/customerCode'

export const Users: CollectionConfig = {
  slug: 'users',
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['email', 'name', 'authProvider', 'customerCode', 'balance', 'role', 'createdAt'],
  },
  auth: true,
  access: {
    // Chỉ admin mới có quyền đăng nhập vào giao diện quản trị Payload CMS (/101)
    admin: ({ req }) => req.user?.role === 'admin',
    // Chỉ admin mới có thể tạo người dùng qua CMS
    create: ({ req }) => req.user?.role === 'admin',
    // Khách hàng có thể đọc thông tin cơ bản; admin đọc tất cả
    read: () => true,
    // Chỉ admin mới có thể sửa tài khoản người khác; người dùng chỉ sửa chính mình (nếu đăng nhập)
    update: ({ req, id }) => {
      if (!req.user) return false
      if (req.user.role === 'admin') return true
      return req.user.id === id
    },
    // Chỉ admin mới có quyền xóa người dùng
    delete: ({ req }) => req.user?.role === 'admin',
  },
  hooks: {
    beforeChange: [
      async ({ data, operation }) => {
        // Tự động sinh mã định danh khách hàng ngẫu nhiên bảo mật (không lộ ID tuần tự)
        if (operation === 'create' || (data && !data.customerCode)) {
          data.customerCode = data.customerCode || generateCustomerCode()
        }
        return data
      },
    ],
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
      access: {
        update: ({ req }) => req.user?.role === 'admin',
      },
    },
    {
      name: 'customerCode',
      type: 'text',
      index: true,
      label: 'Mã khách hàng hoặc cú pháp nạp',
      admin: {
        description: 'Mã nhận diện nạp tiền tự động qua cổng ngân hàng',
      },
    },
    {
      name: 'apiKey',
      type: 'text',
      index: true,
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
      access: {
        update: ({ req }) => req.user?.role === 'admin',
      },
    },
    {
      name: 'resetOtp',
      type: 'text',
      admin: {
        readOnly: true,
      },
    },
    {
      name: 'resetOtpExpiration',
      type: 'date',
      admin: {
        readOnly: true,
      },
    },
  ],
}
