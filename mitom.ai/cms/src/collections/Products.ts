import type { CollectionConfig } from 'payload'

export const Products: CollectionConfig = {
  slug: 'products',
  access: {
    read: () => true,
  },
  admin: {
    useAsTitle: 'name',
    defaultColumns: ['name', 'author', 'salePrice', 'profitMargin', 'modalTypes', 'stock', 'isActive'],
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      label: 'Tên Model / Gói AI',
      required: true,
    },
    {
      name: 'author',
      type: 'select',
      label: 'Nhà phát triển (Model Author)',
      required: true,
      options: [
        { label: 'Anthropic', value: 'Anthropic' },
        { label: 'OpenAI', value: 'OpenAI' },
        { label: 'Google', value: 'Google' },
        { label: 'DeepSeek', value: 'DeepSeek' },
        { label: 'Midjourney', value: 'Midjourney' },
        { label: 'Black Forest Labs', value: 'Black Forest Labs' },
        { label: 'ElevenLabs', value: 'ElevenLabs' },
        { label: 'ByteDance', value: 'ByteDance' },
        { label: 'Qwen (Alibaba)', value: 'Qwen' },
        { label: 'X.AI (Grok)', value: 'X.AI' },
        { label: 'Kuaishou (Kling)', value: 'Kuaishou' },
        { label: 'Suno', value: 'Suno' },
        { label: 'MiniMax', value: 'MiniMax' },
        { label: 'Moonshot AI (Kimi)', value: 'Moonshot AI' },
        { label: 'Zhipu AI (GLM)', value: 'Zhipu AI' },
        { label: 'Baidu', value: 'Baidu' },
        { label: 'BAAI', value: 'BAAI' },
        { label: 'PixVerse', value: 'PixVerse' },
        { label: 'Vidu', value: 'Vidu' },
        { label: 'Xiaomi', value: 'Xiaomi' },
        { label: 'Đa nền tảng', value: 'Multi-provider' },
      ],
    },
    {
      name: 'modalTypes',
      type: 'select',
      hasMany: true,
      label: 'Loại Mô hình (Modal Type)',
      required: true,
      options: [
        { label: 'Multimodal (Đa phương thức)', value: 'Multimodal' },
        { label: 'Deep Thinking (Suy luận sâu)', value: 'Deep Thinking' },
        { label: 'Text Generation (Sinh văn bản / Chat)', value: 'Text Generation' },
        { label: 'Vision Understanding (Nhận diện hình ảnh)', value: 'Vision Understanding' },
        { label: 'Image Generation (Tạo ảnh nghệ thuật)', value: 'Image Generation' },
        { label: 'Video Generation (Tạo video AI)', value: 'Video Generation' },
        { label: 'Speech Synthesis (Giọng đọc AI / TTS)', value: 'Speech Synthesis' },
        { label: 'Speech Recognition (Nhận dạng giọng nói / STT)', value: 'Speech Recognition' },
        { label: 'Text Vector (Embedding vector)', value: 'Text Vector' },
      ],
    },
    {
      name: 'capabilities',
      type: 'select',
      hasMany: true,
      label: 'Tính năng nâng cao (Capabilities)',
      options: [
        { label: 'Context Caching', value: 'Context Caching' },
        { label: 'Batch Inference', value: 'Batch Inference' },
        { label: 'High Speed Inference', value: 'High Speed Inference' },
        { label: 'Coding Composer / Agent', value: 'Coding Composer' },
      ],
    },
    {
      name: 'region',
      type: 'select',
      label: 'Khu vực máy chủ (Inference Region)',
      defaultValue: 'Singapore',
      options: [
        { label: 'Singapore (Độ trễ thấp <30ms)', value: 'Singapore' },
        { label: 'USA (Toàn cầu)', value: 'USA' },
        { label: 'Tokyo (Nhật Bản)', value: 'Tokyo' },
        { label: 'Hong Kong', value: 'Hong Kong' },
      ],
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
      name: 'badge',
      type: 'text',
      label: 'Huy hiệu (Hot, Bán chạy, v.v.)',
    },
    {
      name: 'desc',
      type: 'textarea',
      label: 'Mô tả tóm tắt model / tính năng',
    },
    {
      name: 'features',
      type: 'json',
      label: 'Danh sách tính năng nổi bật',
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
