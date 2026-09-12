import type { CollectionConfig } from 'payload'

export const Users: CollectionConfig = {
  slug: 'users',
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['email', 'name', 'authProvider', 'balance', 'role', 'createdAt'],
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
    afterChange: [
      async ({ doc, req, operation }) => {
        // Tự động gán mã khách hàng chuẩn MITO + pad(id, 6)
        if (doc && doc.id) {
          const expectedCode = `MITO${String(doc.id).padStart(6, '0')}`
          if (doc.customerCode !== expectedCode) {
            try {
              await req.payload.update({
                collection: 'users',
                id: doc.id,
                data: {
                  customerCode: expectedCode,
                },
              })
              doc.customerCode = expectedCode
            } catch (e) {
              // Bỏ qua nếu đang trong transaction lock
            }
          }
        }
        return doc
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
