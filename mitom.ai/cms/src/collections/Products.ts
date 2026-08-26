import type { CollectionConfig } from 'payload'

export const Products: CollectionConfig = {
  slug: 'products',
  access: {
    read: () => true,
  },
  admin: {
    useAsTitle: 'name',
    defaultColumns: ['name', 'provider', 'costPrice', 'salePrice', 'profitMargin', 'stock', 'isActive'],
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      label: 'Tên gói AI / Dịch vụ',
      required: true,
    },
    {
      name: 'provider',
      type: 'text',
      label: 'Nhà cung cấp (OpenAI, Anthropic, Google...)',
      required: true,
    },
    {
      name: 'tag',
      type: 'select',
      label: 'Phân loại',
      defaultValue: 'chat',
      options: [
        { label: 'Trợ lý Chat', value: 'chat' },
        { label: 'Tạo ảnh', value: 'image' },
        { label: 'Lập trình', value: 'code' },
        { label: 'Gói Token', value: 'token' },
      ],
      required: true,
    },
    {
      type: 'row',
      fields: [
        {
          name: 'costPrice',
          type: 'number',
          label: 'Giá gốc nhập vào (VNĐ)',
          required: true,
          admin: {
            description: 'Chi phí vốn bỏ ra (mua sỉ / nạp token gốc)',
            width: '50%',
          },
        },
        {
          name: 'salePrice',
          type: 'number',
          label: 'Giá bán ra cho khách (VNĐ)',
          required: true,
          admin: {
            description: 'Giá niêm yết trừ vào ví của khách',
            width: '50%',
          },
        },
      ],
    },
    {
      name: 'profitMargin',
      type: 'number',
      label: 'Lợi nhuận dự kiến (VNĐ/đơn)',
      admin: {
        readOnly: true,
        description: 'Tự động tính: Giá bán - Giá gốc',
      },
      hooks: {
        beforeChange: [
          ({ data }) => {
            if (data?.salePrice && data?.costPrice) {
              return Number(data.salePrice) - Number(data.costPrice)
            }
            return 0
          },
        ],
      },
    },
    {
      name: 'desc',
      type: 'textarea',
      label: 'Mô tả sản phẩm',
    },
    {
      name: 'stock',
      type: 'number',
      label: 'Số lượng tồn kho',
      defaultValue: 99,
    },
    {
      name: 'isActive',
      type: 'checkbox',
      label: 'Đang mở bán',
      defaultValue: true,
    },
  ],
}
