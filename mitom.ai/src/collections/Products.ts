import type { CollectionConfig } from 'payload'

export const Products: CollectionConfig = {
  slug: 'products',
  admin: {
    useAsTitle: 'name',
    defaultColumns: ['name', 'category', 'provider', 'price', 'status'],
  },
  access: {
    read: () => true,
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      required: true,
      label: 'Tên sản phẩm',
    },
    {
      name: 'slug',
      type: 'text',
      required: true,
      unique: true,
      label: 'Slug',
    },
    {
      name: 'provider',
      type: 'text',
      required: true,
      label: 'Nhà cung cấp (OpenAI, Anthropic, Midjourney, ...)',
    },
    {
      name: 'category',
      type: 'relationship',
      relationTo: 'categories',
      required: true,
      label: 'Danh mục',
    },
    {
      name: 'badge',
      type: 'text',
      label: 'Nhãn nổi bật (vd: Bán chạy, Phổ biến, Ưu đãi)',
    },
    {
      name: 'desc',
      type: 'textarea',
      required: true,
      label: 'Mô tả ngắn',
    },
    {
      name: 'plans',
      type: 'array',
      label: 'Các gói giá (Plans)',
      fields: [
        {
          name: 'name',
          type: 'text',
          required: true,
          label: 'Tên gói (vd: 1 tháng, 3 tháng, 1M Tokens)',
        },
        {
          name: 'price',
          type: 'number',
          required: true,
          label: 'Giá (VNĐ)',
        },
        {
          name: 'originalPrice',
          type: 'number',
          label: 'Giá gốc (VNĐ)',
        },
        {
          name: 'discount',
          type: 'text',
          label: 'Mức giảm (vd: -20%)',
        },
        {
          name: 'isPopular',
          type: 'checkbox',
          defaultValue: false,
          label: 'Gói phổ biến nhất',
        },
      ],
    },
    {
      name: 'features',
      type: 'array',
      label: 'Tính năng nổi bật',
      fields: [
        {
          name: 'item',
          type: 'text',
          required: true,
          label: 'Chi tiết tính năng',
        },
      ],
    },
    {
      name: 'accentColor',
      type: 'text',
      defaultValue: '#34d399',
      label: 'Màu nhận diện (Hex)',
    },
    {
      name: 'eta',
      type: 'text',
      defaultValue: 'Kích hoạt ~5 phút',
      label: 'Thời gian kích hoạt',
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'active',
      options: [
        { label: 'Đang bán', value: 'active' },
        { label: 'Hết hàng', value: 'out_of_stock' },
        { label: 'Ẩn', value: 'hidden' },
      ],
      label: 'Trạng thái',
    },
  ],
}
