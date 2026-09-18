import type { CollectionConfig } from 'payload'
import { callUCloudApi, type UCloudApiParams } from '@/lib/ucloudClient'

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
      async ({ data = {}, operation }) => {
        const record = data || {}
        if (Array.isArray(record.permissions)) {
          record.permissions = record.permissions.join(', ')
        }

        // Khi Admin tạo key mới trên CMS (chưa có secretKey hoặc chưa có rawResponse từ AstraFlow)
        if (operation === 'create' && (!record.secretKey || !record.rawResponse)) {
          const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY
          const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY

          if (pubKey && privKey) {
            try {
              const createParams: UCloudApiParams = {
                Action: 'CreateUMInferAPIKey',
                Name: record.name || 'AstraFlow API Key',
              }
              if (record.dailyLimit && record.dailyLimit !== 'Không giới hạn') {
                createParams.DailyLimitAmount = String(record.dailyLimit).replace(/[^0-9.]/g, '')
              }
              if (record.monthlyLimit && record.monthlyLimit !== 'Không giới hạn') {
                createParams.MonthlyLimitAmount = String(record.monthlyLimit).replace(/[^0-9.]/g, '')
              }

              const res = await callUCloudApi(createParams, { publicKey: pubKey, privateKey: privKey })

              if (res?.Data) {
                record.keyId = res.Data.KeyId
                record.maskedKey = res.Data.Key || ''
                record.secretKey = res.Data.Key || ''
                record.rawResponse = res.Data
                record.permissions = record.permissions || 'Sandbox, Modelverse'
                record.status = res.Data.Status === 2 ? 'Disabled' : 'Normal'
              }
            } catch (err: any) {
              console.error('Lỗi khi gọi CreateUMInferAPIKey sang AstraFlow:', err.message)
            }
          }

          if (!record.keyId) {
            record.keyId = `uminferapikey-${Date.now().toString(36)}${Math.random().toString(36).substring(2, 6)}`
          }
        }
        return record
      },
    ],
    afterChange: [
      async ({ doc, previousDoc, operation }) => {
        // Khi Admin sửa key (cập nhật hạn mức hoặc đổi tên), đồng bộ ngay lên AstraFlow
        if (operation === 'update' && doc?.keyId && doc.keyId.startsWith('uminferapikey-')) {
          const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY
          const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY

          if (pubKey && privKey) {
            const hasLimitChanged =
              doc.monthlyLimit !== previousDoc?.monthlyLimit ||
              doc.dailyLimit !== previousDoc?.dailyLimit

            if (hasLimitChanged) {
              try {
                const updateParams: UCloudApiParams = {
                  Action: 'UpdateUMInferAPIKey',
                  KeyId: doc.keyId,
                }
                if (doc.dailyLimit) {
                  updateParams.DailyLimitAmount = doc.dailyLimit === 'Không giới hạn' ? '0' : String(doc.dailyLimit).replace(/[^0-9.]/g, '')
                }
                if (doc.monthlyLimit) {
                  updateParams.MonthlyLimitAmount = doc.monthlyLimit === 'Không giới hạn' ? '0' : String(doc.monthlyLimit).replace(/[^0-9.]/g, '')
                }

                await callUCloudApi(updateParams, { publicKey: pubKey, privateKey: privKey })
                console.log(`[ApiKeys Hook] Đã đồng bộ hạn mức mới lên AstraFlow cho key ${doc.keyId} (${doc.name}): Ngày: ${updateParams.DailyLimitAmount || 'N/A'}, Tháng: ${updateParams.MonthlyLimitAmount || 'N/A'}`)
              } catch (upErr: any) {
                console.error(`[ApiKeys Hook] Lỗi cập nhật hạn mức key ${doc.keyId} trên AstraFlow:`, upErr.message)
              }
            }
          }
        }
      },
    ],
    afterDelete: [
      async ({ doc }) => {
        // Khi xóa key trên CMS, tự động xóa key tương ứng trên AstraFlow
        if (doc?.keyId && doc.keyId.startsWith('uminferapikey-')) {
          const pubKey = process.env.ASTRAFLOW_PUBLIC_KEY || process.env.UCLOUD_PUBLIC_KEY
          const privKey = process.env.ASTRAFLOW_PRIVATE_KEY || process.env.UCLOUD_PRIVATE_KEY

          if (pubKey && privKey) {
            try {
              await callUCloudApi(
                {
                  Action: 'DeleteUMInferAPIKey',
                  KeyId: doc.keyId,
                },
                { publicKey: pubKey, privateKey: privKey },
              )
              console.log(`Đã xóa key ${doc.keyId} (${doc.name}) trên máy chủ AstraFlow thành công.`)
            } catch (err: any) {
              console.error(`Lỗi khi xóa key ${doc.keyId} trên AstraFlow:`, err.message)
            }
          }
        }
      },
    ],
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      required: true,
      label: 'Tên Key',
      admin: {
        placeholder: 'Nhập tên API Key (ví dụ: my-api-key)',
      },
    },
    {
      name: 'dailyLimit',
      type: 'text',
      label: 'Hạn mức ngày',
      defaultValue: 'Không giới hạn',
      admin: {
        description: 'Ngân sách giới hạn theo ngày (USD), ví dụ: 2, 5 hoặc Không giới hạn',
      },
    },
    {
      name: 'monthlyLimit',
      type: 'text',
      label: 'Hạn mức tháng',
      defaultValue: 'Không giới hạn',
      admin: {
        description: 'Ngân sách giới hạn theo tháng (USD), ví dụ: 20, 50 hoặc Không giới hạn',
      },
    },
    {
      name: 'ipWhitelist',
      type: 'text',
      label: 'Giới hạn địa chỉ IP',
      defaultValue: 'Không giới hạn',
      admin: {
        description: 'Danh sách IP được phép truy cập, phân cách bằng dấu phẩy hoặc Không giới hạn',
      },
    },
    {
      name: 'modelAccessMode',
      type: 'select',
      label: 'Giới hạn mô hình truy cập',
      defaultValue: 'All Models',
      options: [
        { label: 'Tất cả mô hình', value: 'All Models' },
        { label: 'Chỉ các mô hình được cấp phép', value: 'whitelist' },
      ],
    },
    {
      name: 'permissions',
      type: 'text',
      label: 'Cấu hình quyền hạn',
      defaultValue: 'Sandbox, Modelverse',
      admin: {
        description: 'Các quyền được cấp: Sandbox, Modelverse',
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
      name: 'keyId',
      type: 'text',
      unique: true,
      label: 'Mã định danh khóa',
      admin: {
        readOnly: true,
        description: 'Hệ thống tự động khởi tạo hoặc lấy mã định danh từ AstraFlow',
      },
    },
    {
      name: 'maskedKey',
      type: 'text',
      label: 'Khóa hiển thị thu gọn',
      admin: {
        readOnly: true,
      },
    },
    {
      name: 'secretKey',
      type: 'text',
      label: 'Khóa bí mật',
      admin: {
        readOnly: true,
        description: 'Khóa bảo mật đầy đủ sau khi được đồng bộ từ AstraFlow',
      },
    },
    {
      name: 'dailySpend',
      type: 'text',
      label: 'Chi tiêu trong ngày',
      defaultValue: '0',
      admin: {
        readOnly: true,
      },
    },
    {
      name: 'monthlySpend',
      type: 'text',
      label: 'Chi tiêu trong tháng',
      defaultValue: '0',
      admin: {
        readOnly: true,
      },
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
