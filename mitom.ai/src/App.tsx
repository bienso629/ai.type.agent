import logoImg from './assets/images/logo.jpg'
import { useState, useMemo, type ReactNode } from "react"
import {
  Sparkles,
  Brain,
  FileText,
  Eye,
  Image as ImageIcon,
  Video,
  Mic,
  Volume2,
  Layers,
  SlidersHorizontal,
  X,
  Search,
  Check,
  Globe,
  Bot,
  Zap,
} from "lucide-react"

type Category = "chat" | "image" | "code" | "token"
type Page = "home" | "topup" | "success"

export type ModalType =
  | "Multimodal"
  | "Deep Thinking"
  | "Text Generation"
  | "Vision Understanding"
  | "Image Generation"
  | "Video Generation"
  | "Speech Recognition"
  | "Speech Synthesis"
  | "Text Vector"

export type Capability = "Context Caching" | "Batch Inference"

export interface Product {
  id: string
  name: string
  provider: string
  author: string
  tag: Category
  modalTypes: ModalType[]
  capabilities?: Capability[]
  region?: string
  badge?: string
  desc: string
  features: string[]
  accent: string
  initials: string
  eta: string
}

export const CATEGORIES: { id: Category | "all"; label: string }[] = [
  { id: "all", label: "Tất cả" },
  { id: "chat", label: "Trợ lý Chat" },
  { id: "image", label: "Tạo ảnh & Video" },
  { id: "code", label: "Lập trình" },
  { id: "token", label: "Gói Token API" },
]

export const MODEL_AUTHORS = [
  "Anthropic",
  "BAAI",
  "Baidu",
  "Bilibili",
  "Black Forest Labs",
  "ByteDance",
  "DeepSeek",
  "EasyLink",
  "ElevenLabs",
  "Exa",
  "Google",
  "HappyHorse",
  "Kuaishou",
  "Midjourney",
  "MiniMax",
  "Moonshot AI",
  "OpenAI",
  "PixVerse",
  "Qwen",
  "Suno",
  "Vidu",
  "X.AI",
  "Zhipu AI",
  "Xiaomi",
  "蝉镜",
]

export const MODAL_TYPE_SECTIONS = [
  {
    category: "Multimodal",
    items: [
      { id: "Multimodal" as ModalType, label: "Multimodal", icon: Sparkles, color: "#ec4899" },
    ],
  },
  {
    category: "Text",
    items: [
      { id: "Deep Thinking" as ModalType, label: "Deep Thinking", icon: Brain, color: "#f59e0b" },
      { id: "Text Generation" as ModalType, label: "Text Generation", icon: FileText, color: "#3b82f6" },
    ],
  },
  {
    category: "Vision",
    items: [
      { id: "Vision Understanding" as ModalType, label: "Vision Understanding", icon: Eye, color: "#06b6d4" },
      { id: "Image Generation" as ModalType, label: "Image Generation", icon: ImageIcon, color: "#c084fc" },
      { id: "Video Generation" as ModalType, label: "Video Generation", icon: Video, color: "#f43f5e" },
    ],
  },
  {
    category: "Speech",
    items: [
      { id: "Speech Recognition" as ModalType, label: "Speech Recognition", icon: Mic, color: "#0ea5e9" },
      { id: "Speech Synthesis" as ModalType, label: "Speech Synthesis", icon: Volume2, color: "#8b5cf6" },
    ],
  },
  {
    category: "Vector",
    items: [
      { id: "Text Vector" as ModalType, label: "Text Vector", icon: Layers, color: "#10b981" },
    ],
  },
]

export const CAPABILITIES: Capability[] = ["Context Caching", "Batch Inference"]

export const PRODUCTS: Product[] = [
  {
    id: "gpt-plus",
    name: "ChatGPT Plus",
    provider: "OpenAI",
    author: "OpenAI",
    tag: "chat",
    modalTypes: ["Deep Thinking", "Multimodal", "Text Generation", "Vision Understanding"],
    capabilities: ["Context Caching"],
    region: "Singapore",
    badge: "Bán chạy",
    desc: "Tài khoản chính chủ, dùng GPT-4o, o3 và các mô hình mới nhất không giới hạn.",
    features: ["Truy cập GPT-4o & o3", "Bảo hành 1 đổi 1", "Kích hoạt trong 5 phút"],
    accent: "#34d399",
    initials: "AI",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "claude-pro",
    name: "Claude Pro",
    provider: "Anthropic",
    author: "Anthropic",
    tag: "chat",
    modalTypes: ["Deep Thinking", "Text Generation", "Vision Understanding"],
    capabilities: ["Context Caching"],
    region: "Singapore",
    desc: "Cửa sổ ngữ cảnh 200K, Claude Opus & Sonnet cho viết lách và phân tích dài.",
    features: ["Context 200K token", "Ưu tiên giờ cao điểm", "Hỗ trợ tải file lớn"],
    accent: "#f5c451",
    initials: "CL",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "deepseek-r1",
    name: "DeepSeek R1 & V3",
    provider: "DeepSeek",
    author: "DeepSeek",
    tag: "chat",
    modalTypes: ["Deep Thinking", "Text Generation"],
    capabilities: ["Context Caching", "Batch Inference"],
    region: "Singapore",
    badge: "Hot",
    desc: "Model suy luận logic mã nguồn mở số 1 thế giới, giải toán và viết code chuyên sâu.",
    features: ["Deep Thinking ngang o1", "Tốc độ phản hồi cực nhanh", "Tiết kiệm 80% chi phí"],
    accent: "#3b82f6",
    initials: "DS",
    eta: "Kích hoạt ~3 phút",
  },
  {
    id: "midjourney",
    name: "Midjourney",
    provider: "Midjourney",
    author: "Midjourney",
    tag: "image",
    modalTypes: ["Image Generation", "Vision Understanding"],
    region: "Singapore",
    badge: "Hot",
    desc: "Gói Basic 200 ảnh/tháng, chất lượng v6.1, dùng qua Discord riêng.",
    features: ["200 lượt tạo ảnh", "Chế độ Fast", "Bản quyền thương mại"],
    accent: "#c084fc",
    initials: "MJ",
    eta: "Kích hoạt ~15 phút",
  },
  {
    id: "flux-pro",
    name: "FLUX.1 Pro",
    provider: "Black Forest Labs",
    author: "Black Forest Labs",
    tag: "image",
    modalTypes: ["Image Generation"],
    region: "Singapore",
    badge: "Mới",
    desc: "Mô hình tạo ảnh thế hệ mới, tái hiện chi tiết văn bản và làn da người siêu thực.",
    features: ["Vẽ chữ chuẩn xác", "Chi tiết chân thực", "Prompt tự nhiên"],
    accent: "#06b6d4",
    initials: "FX",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "gemini",
    name: "Gemini Advanced",
    provider: "Google",
    author: "Google",
    tag: "chat",
    modalTypes: ["Multimodal", "Vision Understanding", "Text Generation", "Deep Thinking"],
    capabilities: ["Context Caching"],
    region: "Singapore",
    desc: "Gemini 2.5 Pro kèm 2TB Google One, tích hợp Gmail, Docs và NotebookLM.",
    features: ["Gemini 2.5 Pro", "Kèm 2TB lưu trữ", "Deep Research"],
    accent: "#60a5fa",
    initials: "GE",
    eta: "Kích hoạt ~10 phút",
  },
  {
    id: "cursor",
    name: "Cursor Pro",
    provider: "Anysphere",
    author: "ByteDance",
    tag: "code",
    modalTypes: ["Deep Thinking", "Text Generation"],
    region: "Singapore",
    badge: "Cho dev",
    desc: "IDE lập trình AI với 500 request nhanh, autocomplete và agent viết code.",
    features: ["500 fast request", "Agent Composer", "Tab hoàn thiện code"],
    accent: "#e2e8f0",
    initials: "CS",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "kling-ai",
    name: "Kling AI 1.5",
    provider: "Kuaishou",
    author: "Kuaishou",
    tag: "image",
    modalTypes: ["Video Generation", "Vision Understanding"],
    region: "Singapore",
    badge: "Video AI",
    desc: "Tạo video chuyển động siêu thực 1080p từ văn bản hoặc hình ảnh tĩnh.",
    features: ["Video chuẩn 1080p", "Chuyển động mượt mà", "Mô phỏng vật lý chân thực"],
    accent: "#f97316",
    initials: "KL",
    eta: "Kích hoạt ~10 phút",
  },
  {
    id: "elevenlabs",
    name: "ElevenLabs Voice Pro",
    provider: "ElevenLabs",
    author: "ElevenLabs",
    tag: "chat",
    modalTypes: ["Speech Synthesis", "Speech Recognition"],
    region: "Singapore",
    desc: "Chuyển văn bản thành giọng nói cảm xúc chuẩn tiếng Việt và 29 ngôn ngữ.",
    features: ["Clone giọng nói", "Đầy đủ cảm xúc", "Audio chất lượng cao"],
    accent: "#ec4899",
    initials: "EL",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "suno-ai",
    name: "Suno v4 Music Pro",
    provider: "Suno",
    author: "Suno",
    tag: "chat",
    modalTypes: ["Speech Synthesis"],
    region: "Singapore",
    badge: "Tạo nhạc",
    desc: "Sáng tác bài hát hoàn chỉnh đầy đủ lời và hòa âm phối khí trong 30 giây.",
    features: ["2.500 credit nạp sẵn", "Tách beat & vocal", "Bản quyền thương mại"],
    accent: "#eab308",
    initials: "SN",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "grok-3",
    name: "Grok 3 (Colossus)",
    provider: "X.AI",
    author: "X.AI",
    tag: "chat",
    modalTypes: ["Deep Thinking", "Text Generation", "Vision Understanding"],
    region: "Singapore",
    badge: "Mới nhất",
    desc: "Siêu AI từ xAI của Elon Musk, suy luận sâu và cập nhật dữ liệu Real-time.",
    features: ["Dữ liệu Real-time X", "Giải toán chuyên sâu", "Tốc độ xử lý cao"],
    accent: "#e2e8f0",
    initials: "GK",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "qwen-max",
    name: "Qwen 2.5 Max",
    provider: "Alibaba",
    author: "Qwen",
    tag: "chat",
    modalTypes: ["Deep Thinking", "Text Generation", "Multimodal"],
    capabilities: ["Context Caching", "Batch Inference"],
    region: "Singapore",
    desc: "Mô hình xử lý đa ngữ hàng đầu Châu Á, tiếng Việt cực kỳ tự nhiên và sắc bén.",
    features: ["Context 128K token", "Toán & Code mạnh mẽ", "Tối ưu hóa chi phí"],
    accent: "#8b5cf6",
    initials: "QW",
    eta: "Kích hoạt ~5 phút",
  },
  {
    id: "token-5m",
    name: "Gói API 5.000K Token",
    provider: "Đa nền tảng",
    author: "OpenAI",
    tag: "token",
    modalTypes: ["Text Vector", "Text Generation", "Deep Thinking"],
    capabilities: ["Context Caching", "Batch Inference"],
    region: "Singapore",
    desc: "Credit API dùng chung cho OpenAI, Claude, Gemini qua cổng trung gian nội địa.",
    features: ["5 triệu token", "Không hết hạn", "Dashboard theo dõi"],
    accent: "#34d399",
    initials: "TK",
    eta: "Giao ngay lập tức",
  },
]

interface TopUp {
  amount: number
  bonusPct: number
  label: string
  highlight: boolean
}

const TOPUPS: TopUp[] = [
  { amount: 100000, bonusPct: 0, label: "Khởi động", highlight: false },
  { amount: 200000, bonusPct: 5, label: "Tiết kiệm", highlight: false },
  { amount: 500000, bonusPct: 10, label: "Phổ biến", highlight: true },
  { amount: 1000000, bonusPct: 15, label: "Đại lý", highlight: false },
]

const PAY_METHODS = [
  { id: "vietqr", label: "VietQR / Chuyển khoản", note: "Quét mã, tự động cộng số dư" },
  { id: "momo", label: "Ví Momo", note: "Thanh toán nhanh qua app" },
  { id: "zalopay", label: "ZaloPay", note: "Liên kết ngân hàng" },
]

const FAQS = [
  {
    q: "Số dư nạp vào có bị hết hạn không?",
    a: "Không. Tiền bạn nạp được cộng vào số dư và dùng đến khi nào hết thì thôi, không có kỳ hạn. Mỗi lần kích hoạt tài khoản hay mua token sẽ trừ trực tiếp vào số dư này.",
  },
  {
    q: "Mua công cụ AI thế nào?",
    a: "Bạn chỉ cần nạp tiền vào số dư, sau đó nhắn Zalo cho shop công cụ muốn dùng. Shop kích hoạt và trừ đúng số tiền vào số dư của bạn — không cần đặt hàng từng món.",
  },
  {
    q: "Thanh toán bằng cách nào?",
    a: "Chúng tôi hỗ trợ chuyển khoản ngân hàng nội địa, Momo, ZaloPay và VietQR. Số dư được cộng tự động sau khi xác nhận thanh toán.",
  },
  {
    q: "Chính sách bảo hành thế nào?",
    a: "Bảo hành 1 đổi 1 trong suốt thời gian sử dụng. Nếu tài khoản gặp lỗi không do người dùng, chúng tôi đổi mới miễn phí trong 24 giờ.",
  },
]

const ZALO = "https://zalo.me/0908888888"
const formatVnd = (n: number) => n.toLocaleString("vi-VN") + "đ"

function Logo({ onClick }: { onClick?: () => void }) {
  return (
    <a
      href="#"
      onClick={(e) => {
        if (onClick) {
          e.preventDefault()
          onClick()
        }
      }}
      className="flex items-center gap-2.5 group"
    >
      <img
        src={logoImg}
        alt="Mitom.ai Logo"
        className="h-9 w-9 rounded-xl object-cover shadow-sm border border-border/60 group-hover:border-primary/50 transition-colors"
      />
      <span className="font-display text-xl font-extrabold tracking-tight">
        Mitom<span className="text-primary">.ai</span>
      </span>
    </a>
  )
}

function ProductCard({ p }: { p: Product }) {
  return (
    <article className="group relative flex flex-col overflow-hidden rounded-xl border border-border bg-card p-5 transition-all duration-300 hover:border-primary/50 hover:-translate-y-1">
      <div
        className="pointer-events-none absolute -right-16 -top-16 h-40 w-40 rounded-full opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-20"
        style={{ background: p.accent }}
      />
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <span
            className="grid h-11 w-11 place-items-center rounded-xl font-mono text-sm font-bold"
            style={{ background: `${p.accent}1a`, color: p.accent }}
          >
            {p.initials}
          </span>
          <div>
            <h3 className="font-display text-lg font-bold leading-none">{p.name}</h3>
            <span className="text-xs text-muted-foreground">{p.author || p.provider}</span>
          </div>
        </div>
        {p.badge && (
          <span className="rounded-full bg-primary px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-primary-foreground">
            {p.badge}
          </span>
        )}
      </div>

      <p className="mt-4 text-sm leading-relaxed text-muted-foreground">{p.desc}</p>

      <ul className="mt-4 flex-1 space-y-2">
        {p.features.map((f) => (
          <li key={f} className="flex items-center gap-2 text-sm text-secondary-foreground">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="shrink-0 text-emerald">
              <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            {f}
          </li>
        ))}
      </ul>

      <div className="mt-5 flex items-center justify-between border-t border-border pt-4">
        <span className="inline-flex items-center gap-1.5 text-xs font-medium text-emerald">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald" style={{ animation: "tokenpulse 2s ease-in-out infinite" }} /> Đang có sẵn
        </span>
        <span className="font-mono text-[11px] text-muted-foreground">{p.eta}</span>
      </div>

      <a
        href={ZALO}
        target="_blank"
        rel="noreferrer"
        className="mt-4 w-full rounded-full bg-secondary py-2.5 text-center text-sm font-semibold text-secondary-foreground transition-colors hover:bg-primary hover:text-primary-foreground focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
      >
        Nhắn Zalo để chọn
      </a>
    </article>
  )
}

function QrMock() {
  return (
    <div className="grid h-24 w-24 shrink-0 place-items-center rounded-xl bg-white p-2">
      <div className="grid h-full w-full grid-cols-5 grid-rows-5 gap-0.5">
        {Array.from({ length: 25 }).map((_, i) => (
          <span key={i} className="rounded-[1px]" style={{ background: (i * 7 + 3) % 3 ? "#0b0c0f" : "transparent" }} />
        ))}
      </div>
    </div>
  )
}

function TopUpPage({ topup, onDone, onNavigate }: { topup: TopUp; onDone: () => void; onNavigate: (p: Page) => void }) {
  const [pay, setPay] = useState("vietqr")
  const bonus = Math.round((topup.amount * topup.bonusPct) / 100)
  const balance = topup.amount + bonus

  return (
    <section className="mx-auto max-w-4xl px-5 py-14 md:px-8">
      <button onClick={() => onNavigate("home")} className="mb-6 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-primary">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg>
        Chọn mức nạp khác
      </button>
      <h1 className="font-display text-3xl font-extrabold tracking-tight">Nạp {formatVnd(topup.amount)} vào số dư</h1>
      <p className="mt-2 text-sm text-muted-foreground">Số dư dùng chung cho mọi công cụ AI, không hết hạn. Kích hoạt tự động ngay sau khi chuyển khoản.</p>

      <div className="mt-8 grid gap-8 md:grid-cols-[1.2fr_0.8fr]">
        <div className="space-y-6">
          <fieldset className="rounded-xl border border-border bg-card p-6">
            <legend className="px-2 font-mono text-xs uppercase tracking-wide text-muted-foreground">1. Thông tin người nhận</legend>
            <div className="space-y-4 pt-2">
              <Field label="Số điện thoại Zalo nhận tài khoản" placeholder="090 123 4567" type="tel" />
              <Field label="Ghi chú (nếu có)" placeholder="Ví dụ: Cần kích hoạt gấp cho công việc" />
            </div>
          </fieldset>

          <fieldset className="rounded-xl border border-border bg-card p-6">
            <legend className="px-2 font-mono text-xs uppercase tracking-wide text-muted-foreground">2. Chọn hình thức thanh toán</legend>
            <div className="space-y-2.5 pt-2">
              {PAY_METHODS.map((m) => (
                <label
                  key={m.id}
                  onClick={() => setPay(m.id)}
                  className={`flex cursor-pointer items-center gap-3 rounded-xl border p-4 transition-colors ${
                    pay === m.id ? "border-primary bg-primary/5" : "border-border bg-card hover:border-primary/40"
                  }`}
                >
                  <span className={`grid h-5 w-5 place-items-center rounded-full border-2 ${pay === m.id ? "border-primary" : "border-border"}`}>
                    {pay === m.id && <span className="h-2.5 w-2.5 rounded-full bg-primary" />}
                  </span>
                  <div className="flex-1">
                    <div className="text-sm font-semibold">{m.label}</div>
                    <div className="text-xs text-muted-foreground">{m.note}</div>
                  </div>
                </label>
              ))}

              <div className="mt-4 flex items-center gap-4 rounded-xl border border-dashed border-border bg-secondary/40 p-4">
                <QrMock />
                <div className="text-xs">
                  <div className="font-mono font-bold text-foreground">VIETQR NỘI ĐỊA 24/7</div>
                  <div className="mt-1 text-muted-foreground">Nội dung chuyển khoản tự động điền: <span className="font-mono font-semibold text-primary">MITOM {topup.amount / 1000}K</span></div>
                  <div className="mt-1 font-mono text-[11px] text-emerald">● Hệ thống quét giao dịch mỗi 5 giây</div>
                </div>
              </div>
            </div>
          </fieldset>
        </div>

        <aside className="h-fit rounded-xl border border-border bg-card p-6">
          <h2 className="font-display text-base font-bold">Chi tiết thanh toán</h2>
          <dl className="mt-4 space-y-3 text-sm">
            <div className="flex justify-between text-muted-foreground"><dt>Mức nạp</dt><dd className="font-mono text-foreground">{formatVnd(topup.amount)}</dd></div>
            {bonus > 0 && <div className="flex justify-between text-emerald"><dt>Khuyến mãi (+{topup.bonusPct}%)</dt><dd className="font-mono">+{formatVnd(bonus)}</dd></div>}
            <div className="border-t border-border pt-3 flex justify-between font-bold text-foreground"><dt>Số dư nhận được</dt><dd className="font-mono text-lg text-primary">{formatVnd(balance)}</dd></div>
            <div className="flex justify-between text-xs text-muted-foreground"><dt>Cần thanh toán</dt><dd className="font-mono font-semibold text-foreground">{formatVnd(topup.amount)}</dd></div>
          </dl>
          <button type="submit" onClick={onDone} className="mt-5 w-full rounded-full bg-primary py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02]">
            Xác nhận đã chuyển khoản
          </button>
          <div className="mt-3 text-center text-xs text-muted-foreground">Bảo hành 1 đổi 1 · Hỗ trợ 24/7 qua Zalo</div>
        </aside>
      </div>
    </section>
  )
}

function Field({ label, placeholder, type = "text" }: { label: string; placeholder: string; type?: string }) {
  return (
    <label className="block">
      <span className="text-xs font-semibold text-secondary-foreground">{label}</span>
      <input
        type={type}
        placeholder={placeholder}
        className="w-full rounded-xl border border-border bg-secondary/40 px-3.5 py-2.5 text-sm text-foreground placeholder:text-muted-foreground/60 transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30 mt-1.5"
      />
    </label>
  )
}

function SuccessPage({ topup, onNavigate }: { topup: TopUp; onNavigate: (p: Page) => void }) {
  const bonus = Math.round((topup.amount * topup.bonusPct) / 100)
  return (
    <section className="mx-auto max-w-xl px-5 py-20 text-center md:px-8">
      <div className="rounded-xl border border-emerald/30 bg-card p-10 text-center md:p-14">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-emerald/15" style={{ animation: "tokenpulse 2.4s ease-in-out infinite" }}>
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none"><path d="M20 6 9 17l-5-5" stroke="#34d399" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /></svg>
        </div>
        <h1 className="mt-6 font-display text-2xl font-black">Yêu cầu đã được ghi nhận!</h1>
        <p className="mt-2 text-sm text-muted-foreground">Hệ thống đang đối soát và cộng số dư ví cho bạn trong vòng 1–3 phút.</p>
        <div className="mt-6 space-y-2 rounded-xl border border-border bg-secondary/40 p-4 font-mono text-xs">
          <div className="flex justify-between text-muted-foreground"><span>Số tiền chuyển:</span><span className="text-foreground">{formatVnd(topup.amount)}</span></div>
          <div className="flex justify-between text-muted-foreground"><span>Số dư cộng vào ví:</span><span className="font-bold text-primary">{formatVnd(topup.amount + bonus)}</span></div>
        </div>
        <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:justify-center">
          <a href={ZALO} target="_blank" rel="noreferrer" className="rounded-full bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]">
            Nhắn Zalo xác nhận ngay
          </a>
          <button onClick={() => onNavigate("home")} className="rounded-full border border-border px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60">
            Về trang chủ
          </button>
        </div>
      </div>
    </section>
  )
}

{/* =========================================================================
    FILTER DIALOG COMPONENT
    ========================================================================= */}
function FilterDialog({
  isOpen,
  onClose,
  selectedAuthors,
  toggleAuthor,
  selectedModalTypes,
  toggleModalType,
  selectedCapabilities,
  toggleCapability,
  onReset,
  totalResults,
}: {
  isOpen: boolean
  onClose: () => void
  selectedAuthors: string[]
  toggleAuthor: (author: string) => void
  selectedModalTypes: ModalType[]
  toggleModalType: (type: ModalType) => void
  selectedCapabilities: Capability[]
  toggleCapability: (cap: Capability) => void
  onReset: () => void
  totalResults: number
}) {
  if (!isOpen) return null

  const activeCount = selectedAuthors.length + selectedModalTypes.length + selectedCapabilities.length

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-md">
      <div className="relative flex max-h-[88vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-border bg-card shadow-2xl animate-in fade-in zoom-in-95 duration-200">
        {/* Modal Header */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4 bg-secondary/30">
          <div className="flex items-center gap-2.5">
            <SlidersHorizontal className="h-5 w-5 text-primary" />
            <h3 className="font-display text-lg font-extrabold text-foreground">Bộ Lọc Phân Loại Mô Hình AI</h3>
            {activeCount > 0 && (
              <span className="rounded-full bg-primary/20 border border-primary/40 px-2.5 py-0.5 text-xs font-mono font-bold text-primary">
                {activeCount} đang chọn
              </span>
            )}
          </div>
          <button
            onClick={onClose}
            className="rounded-full p-1.5 text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Modal Scrollable Body */}
        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">
          {/* Section 1: Model Author */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <span className="font-mono text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
                <Bot className="h-4 w-4 text-primary" /> Model Author (Nhà phát triển)
              </span>
              {selectedAuthors.length > 0 && (
                <span className="text-[11px] font-mono text-primary font-bold">
                  Đã chọn {selectedAuthors.length}
                </span>
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              {MODEL_AUTHORS.map((author) => {
                const isSelected = selectedAuthors.includes(author)
                return (
                  <button
                    key={author}
                    onClick={() => toggleAuthor(author)}
                    className={`rounded-full px-3.5 py-1.5 text-xs font-semibold transition-all flex items-center gap-1.5 ${
                      isSelected
                        ? "border border-primary bg-primary text-primary-foreground font-bold shadow-md shadow-primary/20 scale-[1.02]"
                        : "border border-border bg-secondary/50 text-secondary-foreground hover:border-primary/50 hover:bg-secondary"
                    }`}
                  >
                    {isSelected && <Check className="h-3 w-3 shrink-0" />}
                    {author}
                  </button>
                )
              })}
            </div>
          </div>

          {/* Section 2: Modal Type */}
          <div className="border-t border-border pt-5">
            <div className="flex items-center justify-between mb-3">
              <span className="font-mono text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
                <Sparkles className="h-4 w-4 text-emerald" /> Modal Type (Loại Mô Hình)
              </span>
              {selectedModalTypes.length > 0 && (
                <span className="text-[11px] font-mono text-emerald font-bold">
                  Đã chọn {selectedModalTypes.length}
                </span>
              )}
            </div>

            <div className="space-y-3.5">
              {MODAL_TYPE_SECTIONS.map((sec) => (
                <div key={sec.category} className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
                  <span className="w-24 text-[11px] font-mono text-muted-foreground uppercase font-bold shrink-0">
                    {sec.category}:
                  </span>
                  <div className="flex flex-wrap gap-2">
                    {sec.items.map((item) => {
                      const isSelected = selectedModalTypes.includes(item.id)
                      const Icon = item.icon
                      return (
                        <button
                          key={item.id}
                          onClick={() => toggleModalType(item.id)}
                          className={`rounded-full px-3.5 py-1.5 text-xs font-semibold transition-all flex items-center gap-1.5 ${
                            isSelected
                              ? "border-2 border-emerald bg-emerald/20 text-emerald font-bold shadow-sm"
                              : "border border-border bg-secondary/40 text-muted-foreground hover:border-emerald/40 hover:text-foreground"
                          }`}
                        >
                          <Icon className="h-3.5 w-3.5" style={{ color: item.color }} />
                          {item.label}
                        </button>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Section 3: Capabilities */}
          <div className="border-t border-border pt-5">
            <div className="flex items-center justify-between mb-3">
              <span className="font-mono text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
                <Zap className="h-4 w-4 text-amber-400" /> Capabilities (Tính Năng)
              </span>
            </div>
            <div className="flex flex-wrap gap-2">
              {CAPABILITIES.map((cap) => {
                const isSelected = selectedCapabilities.includes(cap)
                return (
                  <button
                    key={cap}
                    onClick={() => toggleCapability(cap)}
                    className={`rounded-full px-3.5 py-1.5 text-xs font-semibold transition-all flex items-center gap-1.5 ${
                      isSelected
                        ? "border border-amber-400 bg-amber-400/20 text-amber-400 font-bold shadow-sm"
                        : "border border-border bg-secondary/40 text-muted-foreground hover:border-amber-400/40 hover:text-foreground"
                    }`}
                  >
                    {isSelected && <Check className="h-3 w-3 shrink-0" />}
                    {cap}
                  </button>
                )
              })}
            </div>
          </div>

          {/* Section 4: Inference Region */}
          <div className="border-t border-border pt-5">
            <span className="font-mono text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5 mb-2">
              <Globe className="h-4 w-4 text-emerald" /> Inference Region (Khu Vực Máy Chủ)
            </span>
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald/40 bg-emerald/10 px-3.5 py-1 text-xs font-mono font-bold text-emerald">
              ● Singapore (&lt;30ms)
            </div>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border bg-secondary/40 px-6 py-4">
          <button
            onClick={onReset}
            disabled={activeCount === 0}
            className="text-xs font-bold text-muted-foreground hover:text-foreground disabled:opacity-40 disabled:hover:text-muted-foreground transition-colors"
          >
            Xóa toàn bộ ({activeCount})
          </button>
          <button
            onClick={onClose}
            className="rounded-full bg-primary px-6 py-2.5 text-xs font-bold text-primary-foreground shadow-md shadow-primary/20 hover:brightness-110 transition-all"
          >
            Xem {totalResults} kết quả
          </button>
        </div>
      </div>
    </div>
  )
}

export function Storefront() {
  const [activeCategory, setActiveCategory] = useState<Category | "all">("all")
  const [page, setPage] = useState<Page>("home")
  const [topup, setTopup] = useState<TopUp | null>(null)
  const [openFaq, setOpenFaq] = useState<number | null>(0)

  // Filter Dialog State
  const [isFilterDialogOpen, setIsFilterDialogOpen] = useState(false)
  const [selectedAuthors, setSelectedAuthors] = useState<string[]>([])
  const [selectedModalTypes, setSelectedModalTypes] = useState<ModalType[]>([])
  const [selectedCapabilities, setSelectedCapabilities] = useState<Capability[]>([])
  const [searchQuery, setSearchQuery] = useState("")

  const toggleAuthor = (author: string) => {
    setSelectedAuthors((prev) =>
      prev.includes(author) ? prev.filter((a) => a !== author) : [...prev, author]
    )
  }

  const toggleModalType = (type: ModalType) => {
    setSelectedModalTypes((prev) =>
      prev.includes(type) ? prev.filter((t) => t !== type) : [...prev, type]
    )
  }

  const toggleCapability = (cap: Capability) => {
    setSelectedCapabilities((prev) =>
      prev.includes(cap) ? prev.filter((c) => c !== cap) : [...prev, cap]
    )
  }

  const resetAllFilters = () => {
    setSelectedAuthors([])
    setSelectedModalTypes([])
    setSelectedCapabilities([])
    setSearchQuery("")
    setActiveCategory("all")
  }

  const filteredProducts = useMemo(() => {
    return PRODUCTS.filter((p) => {
      // 1. Quick Category filter
      if (activeCategory !== "all" && p.tag !== activeCategory) {
        return false
      }

      // 2. Author filter
      if (selectedAuthors.length > 0 && !selectedAuthors.includes(p.author)) {
        return false
      }

      // 3. Modal Types filter (must match at least one)
      if (selectedModalTypes.length > 0) {
        const hasMatch = selectedModalTypes.some((t) => p.modalTypes?.includes(t))
        if (!hasMatch) return false
      }

      // 4. Capabilities filter
      if (selectedCapabilities.length > 0) {
        const hasMatch = selectedCapabilities.some((c) => p.capabilities?.includes(c))
        if (!hasMatch) return false
      }

      // 5. Search query
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase().trim()
        const matchName = p.name.toLowerCase().includes(q)
        const matchDesc = p.desc.toLowerCase().includes(q)
        const matchAuthor = p.author.toLowerCase().includes(q)
        const matchTypes = p.modalTypes?.some((t) => t.toLowerCase().includes(q))
        if (!matchName && !matchDesc && !matchAuthor && !matchTypes) return false
      }

      return true
    })
  }, [activeCategory, selectedAuthors, selectedModalTypes, selectedCapabilities, searchQuery])

  const totalActiveDialogFilters = selectedAuthors.length + selectedModalTypes.length + selectedCapabilities.length

  const handleTopup = (t: TopUp) => {
    setTopup(t)
    setPage("topup")
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  const goPricing = () => {
    setPage("home")
    setTimeout(() => {
      document.getElementById("products")?.scrollIntoView({ behavior: "smooth" })
    }, 50)
  }

  return (
    <div className="min-h-screen bg-background text-foreground font-sans">
      {/* Header */}
      <header className="sticky top-0 z-40 border-b border-border bg-background/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 md:px-8">
          <Logo onClick={() => setPage("home")} />

          <nav className="hidden items-center gap-8 text-sm font-medium text-secondary-foreground md:flex">
            <button onClick={() => setPage("home")} className="transition-colors hover:text-foreground">Trang chủ</button>
            <a href="#products" onClick={() => setPage("home")} className="transition-colors hover:text-foreground">Bảng giá & Model</a>
            <a href="#faq" onClick={() => setPage("home")} className="transition-colors hover:text-foreground">Câu hỏi</a>
            <a href={ZALO} target="_blank" rel="noreferrer" className="transition-colors hover:text-foreground">Liên hệ</a>
          </nav>

          <div className="flex items-center gap-2">
            <a
              href="/admin"
              className="rounded-full border border-amber-500/40 bg-amber-500/10 px-3.5 py-2 text-xs font-bold text-amber-400 hover:bg-amber-500/20 transition-colors"
            >
              👑 Quản trị
            </a>
            <button onClick={goPricing} className="rounded-full bg-primary px-4 py-2 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02]">
              Nạp số dư
            </button>
          </div>
        </div>
      </header>

      {/* Pages */}
      {page === "home" && (
        <>
          {/* Hero */}
          <section
            className="relative overflow-hidden border-b border-border"
            style={{
              backgroundImage:
                "linear-gradient(var(--grid-line) 1px, transparent 1px), linear-gradient(90deg, var(--grid-line) 1px, transparent 1px)",
              backgroundSize: "56px 56px",
            }}
          >
            <div className="pointer-events-none absolute -top-40 left-1/2 h-96 w-[46rem] -translate-x-1/2 rounded-full bg-primary/10 blur-[120px]" />
            <div className="mx-auto grid max-w-7xl gap-12 px-5 py-20 md:px-8 lg:grid-cols-[1.1fr_0.9fr] lg:py-28">
              <div className="flex flex-col justify-center">
                <span className="mb-5 inline-flex w-fit items-center gap-2 rounded-full border border-border bg-card px-3 py-1.5 font-mono text-xs text-muted-foreground">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> Nạp một lần · Dùng dần · Không hết hạn
                </span>
                <h1 className="font-display text-4xl font-black leading-[1.05] tracking-tight md:text-6xl">
                  Một số dư,
                  <br />
                  <span className="text-primary">mọi công cụ</span> AI.
                </h1>
                <p className="mt-6 max-w-lg text-base leading-relaxed text-muted-foreground md:text-lg">
                  Nạp tiền vào tài khoản Mì Tôm AI rồi dùng dần cho ChatGPT Plus, Claude, Midjourney, Gemini và gói token API. Dùng tới đâu trừ tới đó — hết thì nạp thêm.
                </p>
                <div className="mt-8 flex flex-wrap gap-3">
                  <button onClick={goPricing} className="rounded-full bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]">
                    Nạp tiền ngay
                  </button>
                  <a href="#products" className="rounded-full border border-border bg-card px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60">
                    Xem công cụ có sẵn
                  </a>
                </div>
                <div className="mt-10 grid max-w-md grid-cols-3 gap-6 border-t border-border pt-8">
                  {[
                    ["12.400+", "Khách đã nạp"],
                    ["4.9/5", "Đánh giá"],
                    ["24/7", "Hỗ trợ"],
                  ].map(([n, l]) => (
                    <div key={l}>
                      <div className="font-display text-2xl font-extrabold text-foreground">{n}</div>
                      <div className="text-xs text-muted-foreground">{l}</div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Wallet balance mockup */}
              <div className="flex items-center justify-center lg:justify-end">
                <div className="w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-2xl shadow-black/40">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">Số dư Mì Tôm AI</span>
                    <span className="rounded-full bg-emerald/15 px-2.5 py-1 font-mono text-[11px] font-bold text-emerald">Đang hoạt động</span>
                  </div>
                  <div className="mt-3 font-display text-4xl font-black text-primary">550.000đ</div>
                  <div className="mt-1 font-mono text-xs text-muted-foreground">Không kỳ hạn · dùng cho mọi công cụ</div>
                  <div className="mt-5 space-y-3 border-t border-border pt-5">
                    <span className="font-mono text-[11px] uppercase tracking-wide text-muted-foreground">Lịch sử gần đây</span>
                    {[
                      ["Kích hoạt ChatGPT Plus", "−289.000đ", "#34d399", "AI"],
                      ["Mua 5M Token API", "−149.000đ", "#60a5fa", "TK"],
                      ["Nạp qua VietQR", "+1.000.000đ", "#f5c451", "＋"],
                    ].map(([name, amt, c, ini]) => (
                      <div key={name} className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <span className="grid h-9 w-9 place-items-center rounded-xl font-mono text-xs font-bold" style={{ background: `${c}1a`, color: c }}>
                            {ini}
                          </span>
                          <span className="text-sm font-medium">{name}</span>
                        </div>
                        <span className={`font-mono text-sm ${amt.startsWith("+") ? "text-emerald" : "text-foreground"}`}>{amt}</span>
                      </div>
                    ))}
                  </div>
                  <button onClick={goPricing} className="mt-5 w-full rounded-full bg-primary py-3 text-sm font-bold text-primary-foreground">
                    Nạp thêm số dư
                  </button>
                </div>
              </div>
            </div>
          </section>

          {/* Trust bar */}
          <div className="border-b border-border bg-secondary/40">
            <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-center gap-x-10 gap-y-3 px-5 py-4 font-mono text-xs text-muted-foreground md:px-8">
              {["Momo", "ZaloPay", "VietQR", "Vietcombank", "Techcombank", "MB Bank"].map((b) => (
                <span key={b} className="transition-colors hover:text-foreground">{b}</span>
              ))}
            </div>
          </div>

          {/* Products — showcase with Filter Dialog */}
          <section id="products" className="mx-auto max-w-7xl px-5 py-20 md:px-8">
            <div className="flex flex-col gap-6">
              <div className="flex flex-col md:flex-row md:items-end md:justify-between gap-4">
                <div>
                  <span className="font-mono text-xs uppercase tracking-widest text-primary">// Công cụ & Model AI</span>
                  <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Những gì bạn dùng được</h2>
                  <p className="mt-2 max-w-2xl text-sm text-muted-foreground">Nạp tiền vào số dư, rồi nhắn Zalo chọn công cụ bên dưới. Shop kích hoạt và trừ vào số dư của bạn.</p>
                </div>
              </div>

              {/* Action Bar: 1 single row for Category tabs + Filter Dialog Button */}
              <div className="flex items-center gap-2.5 overflow-x-auto pb-1 scrollbar-none">
                {/* Category Pills */}
                {CATEGORIES.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => setActiveCategory(c.id)}
                    className={`whitespace-nowrap shrink-0 rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
                      activeCategory === c.id
                        ? "border-primary bg-primary text-primary-foreground font-bold"
                        : "border-border bg-card text-secondary-foreground hover:border-primary/50"
                    }`}
                  >
                    {c.label}
                  </button>
                ))}

                {/* Filter Dialog Trigger Button */}
                <button
                  onClick={() => setIsFilterDialogOpen(true)}
                  className={`whitespace-nowrap shrink-0 rounded-full border px-4 py-2 text-sm font-bold transition-all flex items-center gap-2 shadow-sm ${
                    totalActiveDialogFilters > 0
                      ? "border-primary bg-primary/15 text-primary shadow-primary/10"
                      : "border-border bg-card text-foreground hover:border-primary hover:text-primary"
                  }`}
                >
                  <SlidersHorizontal className="h-4 w-4" />
                  <span>Bộ lọc nâng cao</span>
                  {totalActiveDialogFilters > 0 && (
                    <span className="rounded-full bg-primary px-2 py-0.5 text-[11px] font-mono text-primary-foreground font-bold">
                      {totalActiveDialogFilters}
                    </span>
                  )}
                </button>
              </div>
            </div>

            {/* Active Filters Bar (if any dialog filter is applied) */}
            {(totalActiveDialogFilters > 0 || searchQuery.trim()) && (
              <div className="mt-6 flex flex-wrap items-center gap-2 rounded-xl border border-border bg-secondary/30 p-3 text-xs">
                <span className="font-mono text-muted-foreground uppercase text-[11px] font-bold mr-1">Đang lọc theo:</span>
                {selectedAuthors.map((a) => (
                  <span
                    key={a}
                    className="inline-flex items-center gap-1.5 rounded-full bg-primary/20 border border-primary/40 px-3 py-1 font-mono font-bold text-primary"
                  >
                    {a}
                    <button onClick={() => toggleAuthor(a)} className="hover:opacity-75">✕</button>
                  </span>
                ))}
                {selectedModalTypes.map((t) => (
                  <span
                    key={t}
                    className="inline-flex items-center gap-1.5 rounded-full bg-emerald/20 border border-emerald/40 px-3 py-1 font-mono font-bold text-emerald"
                  >
                    #{t}
                    <button onClick={() => toggleModalType(t)} className="hover:opacity-75">✕</button>
                  </span>
                ))}
                {selectedCapabilities.map((c) => (
                  <span
                    key={c}
                    className="inline-flex items-center gap-1.5 rounded-full bg-amber-400/20 border border-amber-400/40 px-3 py-1 font-mono font-bold text-amber-400"
                  >
                    {c}
                    <button onClick={() => toggleCapability(c)} className="hover:opacity-75">✕</button>
                  </span>
                ))}
                {searchQuery.trim() && (
                  <span className="inline-flex items-center gap-1.5 rounded-full bg-secondary border border-border px-3 py-1 text-foreground">
                    &quot;{searchQuery}&quot;
                    <button onClick={() => setSearchQuery("")} className="hover:opacity-75">✕</button>
                  </span>
                )}
                <button
                  onClick={resetAllFilters}
                  className="ml-auto text-xs font-bold text-muted-foreground hover:text-foreground underline"
                >
                  Xóa tất cả bộ lọc
                </button>
              </div>
            )}

            {/* Product Cards Grid */}
            <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {filteredProducts.length === 0 ? (
                <div className="col-span-full rounded-xl border border-dashed border-border bg-card p-12 text-center">
                  <Bot className="h-10 w-10 text-muted-foreground mx-auto mb-2" />
                  <p className="text-sm font-bold text-foreground">Không có mô hình nào khớp với bộ lọc</p>
                  <button onClick={resetAllFilters} className="mt-3 rounded-full bg-primary px-4 py-2 text-xs font-bold text-primary-foreground">
                    Xóa bộ lọc để xem tất cả
                  </button>
                </div>
              ) : (
                filteredProducts.map((p) => <ProductCard key={p.id} p={p} />)
              )}
            </div>
          </section>

          {/* Pricing — deposit tiers */}
          <section id="pricing" className="border-t border-border bg-secondary/20 py-20">
            <div className="mx-auto max-w-7xl px-5 md:px-8">
              <div className="text-center">
                <span className="font-mono text-xs uppercase tracking-widest text-primary">// Nạp số dư</span>
                <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Chọn mức nạp phù hợp</h2>
                <p className="mx-auto mt-2 max-w-lg text-sm text-muted-foreground">Nạp một lần, dùng trừ dần cho mọi công cụ. Không lo gia hạn hàng tháng hay quên hủy gói.</p>
              </div>

              <div className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
                {TOPUPS.map((t) => (
                  <div
                    key={t.amount}
                    className={`relative flex flex-col rounded-xl border p-6 transition-transform hover:-translate-y-1 ${
                      t.highlight ? "border-primary bg-card shadow-xl shadow-primary/10" : "border-border bg-card"
                    }`}
                  >
                    {t.highlight && (
                      <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-primary px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-primary-foreground">
                        Khuyên dùng
                      </span>
                    )}
                    <div className="font-display text-lg font-bold">{t.label}</div>
                    <div className="mt-2 font-mono text-3xl font-black tracking-tight text-foreground">{formatVnd(t.amount)}</div>
                    {t.bonusPct > 0 ? (
                      <div className="mt-2 inline-flex w-fit items-center gap-1.5 rounded-full bg-emerald/15 px-2.5 py-1 text-xs font-bold text-emerald">
                        +{t.bonusPct}% thưởng ({formatVnd((t.amount * t.bonusPct) / 100)})
                      </div>
                    ) : (
                      <div className="mt-2 text-xs text-muted-foreground">Dành cho người mới bắt đầu</div>
                    )}
                    <div className="mt-6 flex-1 space-y-2 border-t border-border pt-5 text-xs text-muted-foreground">
                      <div>✓ Dùng cho toàn bộ công cụ AI</div>
                      <div>✓ Không giới hạn thời gian</div>
                      <div>✓ Hỗ trợ kích hoạt 24/7</div>
                    </div>
                    <button
                      onClick={() => handleTopup(t)}
                      className={`mt-6 rounded-full py-3 text-sm font-bold transition-transform hover:scale-[1.02] ${
                        t.highlight ? "bg-primary text-primary-foreground" : "bg-secondary text-secondary-foreground hover:bg-primary hover:text-primary-foreground"
                      }`}
                    >
                      Nạp mức này
                    </button>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* Guarantee */}
          <section className="border-t border-border py-16">
            <div className="mx-auto max-w-7xl px-5 md:px-8">
              <div className="grid gap-6 md:grid-cols-3">
                {[
                  ["Bảo hành 1 đổi 1", "Lỗi do hệ thống đổi mới trong 24h, cam kết không mất tiền của khách."],
                  ["Không kỳ hạn", "Tiền nạp vào ví cá nhân giữ nguyên giá trị, dùng đến khi nào hết thì thôi."],
                  ["Hỗ trợ qua Zalo 24/7", "Đội ngũ kỹ thuật trực liên tục, hướng dẫn cài đặt và sử dụng tận tình."],
                ].map(([t, d]) => (
                  <div key={t} className="flex gap-3 rounded-xl border border-border bg-card p-5">
                    <span className="mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full bg-primary/15 text-primary">✓</span>
                    <div>
                      <h3 className="font-display text-sm font-bold">{t}</h3>
                      <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{d}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* Testimonials */}
          <section className="border-t border-border bg-secondary/20 py-20">
            <div className="mx-auto max-w-7xl px-5 md:px-8">
              <div className="text-center">
                <span className="font-mono text-xs uppercase tracking-widest text-primary">// Đánh giá</span>
                <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Khách hàng nói gì</h2>
              </div>
              <div className="mt-12 grid gap-6 md:grid-cols-3">
                {[
                  ["Hoàng Nam", "Dev Fullstack", "Nạp 500K dùng cả Cursor lẫn token API cả tháng chưa hết. Tiện hơn mua từng tài khoản nhiều."],
                  ["Minh Trang", "Content Creator", "Mình dùng ChatGPT Plus với Midjourney, cứ hết là nhắn Zalo shop trừ tiền ví rồi cấp key luôn trong 2 phút."],
                  ["Tuấn Anh", "Marketing Lead", "Mô hình số dư này rất văn minh, không sợ bị tự động trừ tiền thẻ tín dụng như mua trực tiếp ở nước ngoài."],
                ].map(([n, r, c]) => (
                  <div key={n} className="relative rounded-xl border border-border bg-card p-6">
                    <p className="text-sm leading-relaxed text-secondary-foreground">&ldquo;{c}&rdquo;</p>
                    <div className="mt-4 border-t border-border pt-4">
                      <div className="font-display text-sm font-bold">{n}</div>
                      <div className="text-xs text-muted-foreground">{r}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* FAQ */}
          <section id="faq" className="border-t border-border py-20">
            <div className="mx-auto max-w-3xl px-5 md:px-8">
              <div className="text-center">
                <span className="font-mono text-xs uppercase tracking-widest text-primary">// FAQ</span>
                <h2 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-4xl">Câu hỏi thường gặp</h2>
              </div>
              <div className="mt-10 divide-y divide-border rounded-xl border border-border bg-card">
                {FAQS.map((f, i) => (
                  <div key={f.q} className="p-6">
                    <button
                      onClick={() => setOpenFaq(openFaq === i ? null : i)}
                      className="flex w-full items-center justify-between text-left font-display text-base font-bold"
                    >
                      <span>{f.q}</span>
                      <span className="font-mono text-lg text-primary">{openFaq === i ? "−" : "+"}</span>
                    </button>
                    {openFaq === i && (
                      <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{f.a}</p>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* Bottom CTA */}
          <section className="border-t border-border bg-secondary/30 py-16">
            <div className="mx-auto max-w-5xl px-5 md:px-8">
              <div className="relative overflow-hidden rounded-xl border border-primary/30 bg-card px-8 py-14 text-center md:py-20">
                <div className="pointer-events-none absolute -bottom-24 left-1/2 h-64 w-[40rem] -translate-x-1/2 rounded-full bg-primary/10 blur-[100px]" />
                <h2 className="font-display text-3xl font-extrabold tracking-tight md:text-4xl">Sẵn sàng trải nghiệm AI với chi phí tối ưu?</h2>
                <p className="mx-auto mt-3 max-w-md text-sm text-muted-foreground">Nạp số dư ngay hôm nay — nhận thêm tới 15% thưởng và dùng cho mọi mô hình AI hàng đầu.</p>
                <button onClick={goPricing} className="mt-8 inline-block rounded-full bg-primary px-8 py-4 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.03]">
                  Nạp số dư ngay bây giờ
                </button>
              </div>
            </div>
          </section>
        </>
      )}

      {page === "topup" && topup && (
        <TopUpPage
          topup={topup}
          onDone={() => setPage("success")}
          onNavigate={(p) => setPage(p)}
        />
      )}

      {page === "success" && topup && (
        <SuccessPage
          topup={topup}
          onNavigate={(p) => setPage(p)}
        />
      )}

      {/* Footer */}
      <footer className="border-t border-border bg-card/60 py-12">
        <div className="mx-auto max-w-7xl px-5 md:px-8 flex flex-col md:flex-row items-center justify-between gap-6 text-xs text-muted-foreground">
          <div className="flex items-center gap-3">
            <img src="/logo.jpg" alt="Mì Tôm AI" className="h-8 w-8 rounded-xl object-cover" />
            <span className="font-bold text-foreground">Mì Tôm AI © 2026</span>
            <span>— Nạp số dư một lần, dùng trọn bộ công cụ AI</span>
          </div>

          <div className="flex items-center gap-5">
            <a href="/admin" className="text-amber-400 font-bold hover:underline">
              👑 Bảng Quản Trị Payload CMS
            </a>
            <a href={ZALO} target="_blank" rel="noreferrer" className="hover:text-foreground">
              Zalo Hỗ trợ
            </a>
          </div>
        </div>
      </footer>

      {/* Filter Dialog Modal */}
      <FilterDialog
        isOpen={isFilterDialogOpen}
        onClose={() => setIsFilterDialogOpen(false)}
        selectedAuthors={selectedAuthors}
        toggleAuthor={toggleAuthor}
        selectedModalTypes={selectedModalTypes}
        toggleModalType={toggleModalType}
        selectedCapabilities={selectedCapabilities}
        toggleCapability={toggleCapability}
        onReset={resetAllFilters}
        totalResults={filteredProducts.length}
      />
    </div>
  )
}

export default Storefront
