'use client'

import React, { useState } from 'react'
import { ChevronLeft, Copy, Check } from 'lucide-react'

interface StaticPageProps {
  onNavigate: (page: any) => void
}

export function GuideTopupPage({ onNavigate }: StaticPageProps) {
  const [copiedAccount, setCopiedAccount] = useState(false)
  const [copiedSyntax, setCopiedSyntax] = useState(false)

  const copyToClipboard = (text: string, type: 'account' | 'syntax') => {
    navigator.clipboard.writeText(text)
    if (type === 'account') {
      setCopiedAccount(true)
      setTimeout(() => setCopiedAccount(false), 2000)
    } else {
      setCopiedSyntax(true)
      setTimeout(() => setCopiedSyntax(false), 2000)
    }
  }

  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
      <div className="mb-6 flex items-center justify-between">
        <button
          onClick={() => onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
        <span className="font-mono text-xs text-primary font-bold">HƯỚNG DẪN NẠP TIỀN 24/7</span>
      </div>

      <div className="border-b border-border/60 pb-8">
        <span className="font-mono text-xs uppercase tracking-widest text-primary font-bold">
          // Hướng dẫn nạp số dư & Kích hoạt
        </span>
        <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-5xl text-foreground">
          Nạp tiền tài khoản tự động qua VietQR
        </h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground md:text-base max-w-3xl">
          Hệ thống ngân hàng tự động cập nhật số dư của bạn trong vòng 30 giây ngay sau khi giao dịch thành công.
        </p>
      </div>

      <div className="mt-8 grid gap-6 md:grid-cols-3">
        <div className="rounded-xl border border-border bg-card p-6">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary font-bold font-mono">
            01
          </div>
          <h3 className="mt-4 font-display text-base font-bold">Đăng nhập tài khoản</h3>
          <p className="mt-2 text-xs leading-relaxed text-muted-foreground">
            Đăng nhập tài khoản Google hoặc tài khoản email để được cấp mã định danh nạp tiền duy nhất (ví dụ: MITO000123).
          </p>
        </div>

        <div className="rounded-xl border border-border bg-card p-6">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary font-bold font-mono">
            02
          </div>
          <h3 className="mt-4 font-display text-base font-bold">Quét mã VietQR</h3>
          <p className="mt-2 text-xs leading-relaxed text-muted-foreground">
            Vào mục Nạp tiền, chọn gói hạn mức mong muốn và mở App ngân hàng quét mã QR để chuyển khoản chính xác nội dung.
          </p>
        </div>

        <div className="rounded-xl border border-border bg-card p-6">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary font-bold font-mono">
            03
          </div>
          <h3 className="mt-4 font-display text-base font-bold">Nhận số dư & Gọi API</h3>
          <p className="mt-2 text-xs leading-relaxed text-muted-foreground">
            Hệ thống ngân hàng gửi webhook tự động cộng số dư vào ví và sẵn sàng để bạn gọi hơn 130 model AI ngay lập tức.
          </p>
        </div>
      </div>

      <div className="mt-10">
        <h2 className="font-display text-xl font-bold">Thông tin tài khoản thụ hưởng chính thức</h2>
        <p className="mt-1 text-xs text-muted-foreground">Chỉ chuyển khoản vào tài khoản doanh nghiệp chính thức sau đây</p>

        <div className="mt-6 grid gap-5 sm:grid-cols-2">
          <div className="rounded-lg border border-border bg-card p-5">
            <span className="text-xs text-muted-foreground">Ngân hàng thụ hưởng</span>
            <div className="mt-1 font-bold text-sm text-foreground">ACB - NH Thương mại cổ phần Á Châu</div>
            <span className="text-[11px] text-muted-foreground">Chi nhánh Phan Đăng Lưu, TP.HCM</span>
          </div>

          <div className="rounded-lg border border-border bg-card p-5">
            <span className="text-xs text-muted-foreground">Tên đơn vị thụ hưởng</span>
            <div className="mt-1 font-mono font-bold text-sm text-primary">CTY CP CÔNG NGHỆ TADU</div>
            <span className="text-[11px] text-muted-foreground">Pháp nhân chủ quản hệ thống</span>
          </div>

          <div className="rounded-lg border border-border bg-card p-5 flex items-center justify-between">
            <div>
              <span className="text-xs text-muted-foreground">Số tài khoản</span>
              <div className="mt-1 font-mono font-black text-xl text-foreground">199878939</div>
            </div>
            <button
              onClick={() => copyToClipboard('199878939', 'account')}
              className="flex items-center gap-1.5 rounded border border-border bg-secondary px-3 py-1.5 text-xs font-medium hover:border-primary transition-colors"
            >
              {copiedAccount ? <Check size={14} className="text-emerald" /> : <Copy size={14} />}
              <span>{copiedAccount ? 'Đã chép' : 'Sao chép'}</span>
            </button>
          </div>

          <div className="rounded-lg border border-border bg-card p-5 flex items-center justify-between">
            <div>
              <span className="text-xs text-muted-foreground">Cú pháp chuyển khoản</span>
              <div className="mt-1 font-mono font-bold text-base text-emerald">MITO [Mã số của bạn]</div>
            </div>
            <button
              onClick={() => copyToClipboard('MITO', 'syntax')}
              className="flex items-center gap-1.5 rounded border border-border bg-secondary px-3 py-1.5 text-xs font-medium hover:border-primary transition-colors"
            >
              {copiedSyntax ? <Check size={14} className="text-emerald" /> : <Copy size={14} />}
              <span>{copiedSyntax ? 'Đã chép' : 'Sao chép'}</span>
            </button>
          </div>
        </div>
      </div>

      <div className="mt-10">
        <h3 className="font-display text-lg font-bold">Lưu ý quan trọng khi nạp tiền</h3>
        <ul className="mt-4 space-y-2.5 text-sm text-muted-foreground list-disc pl-5">
          <li>Số tiền nạp tối thiểu là <strong>100.000 VNĐ</strong> mỗi lần giao dịch.</li>
          <li>Số dư sau khi nạp <strong>không có hạn sử dụng</strong>, bạn có thể gọi API đến khi nào hết tiền thì thôi.</li>
          <li>Nếu bạn cần xuất hóa đơn VAT điện tử (10%), vui lòng chọn mục <strong>Công ty / Doanh nghiệp</strong> khi nạp tiền.</li>
          <li>Trường hợp chuyển sai nội dung chuyển khoản, hãy liên hệ ngay Hotline/Zalo: <strong className="text-primary font-mono">0908.888.888</strong> để được hỗ trợ kiểm tra và cộng số dư thủ công.</li>
        </ul>
      </div>
    </main>
  )
}

export function ApiDocsPage({ onNavigate }: StaticPageProps) {
  const [copiedEndpoint, setCopiedEndpoint] = useState(false)
  const [copiedCode, setCopiedCode] = useState(false)
  const [activeTab, setActiveTab] = useState<'python' | 'nodejs' | 'curl'>('python')

  const codeSnippets = {
    python: {
      lang: 'Python (OpenAI SDK)',
      code: `from openai import OpenAI

client = OpenAI(
    base_url="https://api-us-ca.umodelverse.ai/v1",
    api_key="MITOM_API_KEY_CUA_BAN"
)

response = client.chat.completions.create(
    model="deepseek-ai/DeepSeek-V3",
    messages=[
        {"role": "system", "content": "Bạn là trợ lý AI thông minh."},
        {"role": "user", "content": "Xin chào, hãy giới thiệu về bạn!"}
    ]
)

print(response.choices[0].message.content)`
    },
    nodejs: {
      lang: 'Node.js / TypeScript (OpenAI SDK)',
      code: `import OpenAI from 'openai'

const openai = new OpenAI({
  baseURL: 'https://api-us-ca.umodelverse.ai/v1',
  apiKey: 'MITOM_API_KEY_CUA_BAN',
})

async function main() {
  const completion = await openai.chat.completions.create({
    model: 'deepseek-ai/DeepSeek-V3',
    messages: [
      { role: 'user', content: 'Hãy viết một bài thơ ngắn về AI.' }
    ],
  })

  console.log(completion.choices[0].message.content)
}

main()`
    },
    curl: {
      lang: 'cURL Terminal',
      code: `curl https://api-us-ca.umodelverse.ai/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer MITOM_API_KEY_CUA_BAN" \\
  -d '{
    "model": "deepseek-ai/DeepSeek-V3",
    "messages": [
      {"role": "user", "content": "Hello World!"}
    ]
  }'`
    }
  }

  const handleCopyCurrentCode = () => {
    navigator.clipboard.writeText(codeSnippets[activeTab].code)
    setCopiedCode(true)
    setTimeout(() => setCopiedCode(false), 2000)
  }

  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
      <div className="mb-6 flex items-center justify-between">
        <button
          onClick={() => onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
        <span className="font-mono text-xs text-primary font-bold">OPENAI API COMPATIBLE</span>
      </div>

      <div className="border-b border-border/60 pb-8">
        <span className="font-mono text-xs uppercase tracking-widest text-primary font-bold">
          // Tài liệu kỹ thuật & Tích hợp
        </span>
        <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-5xl text-foreground">
          Hướng dẫn kết nối API chuẩn OpenAI
        </h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground md:text-base max-w-3xl">
          Endpoint tương thích 100% với chuẩn OpenAI API. Bạn có thể sử dụng trực tiếp trên Cursor, Cline, Roo Code, LibreChat, Dify hoặc gọi từ Python / Node.js.
        </p>
      </div>

      {/* Code Examples with Tabs */}
      <div className="mt-8">
        <div className="rounded-xl border border-border bg-card overflow-hidden shadow-lg">
          {/* Tabs Header */}
          <div className="flex flex-wrap items-center justify-between border-b border-border bg-secondary/40 px-4 py-2 gap-2">
            <div className="flex items-center gap-1.5">
              <button
                onClick={() => setActiveTab('python')}
                className={`rounded-md px-3.5 py-1.5 font-mono text-xs font-bold transition-colors ${
                  activeTab === 'python'
                    ? 'bg-primary text-primary-foreground shadow-sm'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                }`}
              >
                Python
              </button>
              <button
                onClick={() => setActiveTab('nodejs')}
                className={`rounded-md px-3.5 py-1.5 font-mono text-xs font-bold transition-colors ${
                  activeTab === 'nodejs'
                    ? 'bg-primary text-primary-foreground shadow-sm'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                }`}
              >
                Node.js / TS
              </button>
              <button
                onClick={() => setActiveTab('curl')}
                className={`rounded-md px-3.5 py-1.5 font-mono text-xs font-bold transition-colors ${
                  activeTab === 'curl'
                    ? 'bg-primary text-primary-foreground shadow-sm'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                }`}
              >
                cURL
              </button>
            </div>

            <button
              onClick={handleCopyCurrentCode}
              className="flex items-center gap-1.5 rounded border border-border bg-secondary px-3 py-1.5 text-xs font-medium text-foreground hover:border-primary transition-colors"
            >
              {copiedCode ? <Check size={14} className="text-emerald" /> : <Copy size={14} />}
              <span>{copiedCode ? 'Đã sao chép' : `Sao chép ${activeTab.toUpperCase()}`}</span>
            </button>
          </div>

          {/* Code Viewer */}
          <pre className="p-6 font-mono text-xs md:text-sm overflow-x-auto text-foreground/90 bg-[#0d1117] leading-relaxed min-h-[260px]">
{codeSnippets[activeTab].code}
          </pre>
        </div>
      </div>
    </main>
  )
}

export function TermsPage({ onNavigate }: StaticPageProps) {
  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
      <div className="mb-6 flex items-center justify-between">
        <button
          onClick={() => onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
        <span className="font-mono text-xs text-primary font-bold">ĐIỀU KHOẢN DỊCH VỤ</span>
      </div>

      <div className="border-b border-border/60 pb-8">
        <span className="font-mono text-xs uppercase tracking-widest text-primary font-bold">
          // Quy chế & Thỏa thuận sử dụng
        </span>
        <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-5xl text-foreground">
          Điều khoản sử dụng dịch vụ Mì Tôm AI
        </h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground max-w-3xl">
          Cập nhật lần cuối: Tháng 09/2026. Bằng việc tạo tài khoản và sử dụng hệ thống API, bạn đồng ý với các điều khoản dưới đây.
        </p>
      </div>

      <div className="mt-8 grid gap-6 text-sm text-foreground/90 leading-relaxed md:grid-cols-2">
        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">1. Giới thiệu dịch vụ</h2>
          <p className="mt-2 text-muted-foreground">
            Mì Tôm AI là cổng dịch vụ cung cấp hạ tầng kết nối các mô hình trí tuệ nhân tạo (AI Models) theo chuẩn OpenAI API do Công ty Cổ phần Công nghệ TADU vận hành. Người dùng nạp tiền vào tài khoản để sử dụng các dịch vụ gọi API được cung cấp trên hệ thống.
          </p>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">2. Tài khoản và Số dư</h2>
          <ul className="mt-3 space-y-2 text-muted-foreground list-disc pl-5">
            <li>Người dùng có trách nhiệm bảo mật thông tin tài khoản và API Key của mình. Mọi giao dịch phát sinh từ API Key của bạn đều được tính phí hợp lệ.</li>
            <li>Số dư nạp vào tài khoản không có hạn sử dụng và không hoàn lại dưới dạng tiền mặt sau khi đã sử dụng gọi API.</li>
            <li>Hệ thống thực hiện tính phí theo mức tiêu hao token/thời lượng thực tế theo bảng giá niêm yết tại thời điểm gọi yêu cầu.</li>
          </ul>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">3. Quy định sử dụng hợp pháp</h2>
          <p className="mt-2 text-muted-foreground">
            Người dùng cam kết không sử dụng API để:
          </p>
          <ul className="mt-2 space-y-1.5 text-muted-foreground list-disc pl-5">
            <li>Tạo, phát tán các nội dung vi phạm pháp luật Việt Nam và quốc tế.</li>
            <li>Thực hiện các cuộc tấn công từ chối dịch vụ (DDoS), quét lỗ hổng hoặc can thiệp trái phép vào hệ thống máy chủ.</li>
            <li>Mạo danh người khác hoặc vi phạm quyền sở hữu trí tuệ của bên thứ ba.</li>
          </ul>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">4. Giới hạn trách nhiệm</h2>
          <p className="mt-2 text-muted-foreground">
            Mì Tôm AI nỗ lực đảm bảo hạ tầng kết nối ổn định 99.9% 24/7. Tuy nhiên, chúng tôi không chịu trách nhiệm đối với các nội dung do mô hình AI tự sinh (hallucination) hoặc các thiệt hại gián tiếp phát sinh từ quyết định dựa trên kết quả trả về của các mô hình AI.
          </p>
        </section>
      </div>
    </main>
  )
}

export function PrivacyPage({ onNavigate }: StaticPageProps) {
  return (
    <main className="mx-auto max-w-7xl px-5 py-12 md:px-8">
      <div className="mb-6 flex items-center justify-between">
        <button
          onClick={() => onNavigate('home')}
          className="inline-flex items-center gap-1.5 font-mono text-xs text-muted-foreground hover:text-primary transition-colors"
        >
          <ChevronLeft size={16} /> Quay lại trang chủ
        </button>
        <span className="font-mono text-xs text-primary font-bold">CHÍNH SÁCH BẢO MẬT</span>
      </div>

      <div className="border-b border-border/60 pb-8">
        <span className="font-mono text-xs uppercase tracking-widest text-primary font-bold">
          // An toàn & Bảo vệ dữ liệu
        </span>
        <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight md:text-5xl text-foreground">
          Chính sách bảo mật thông tin
        </h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground max-w-3xl">
          Cam kết bảo vệ quyền riêng tư, bảo mật dữ liệu giao dịch và thông tin gọi API của khách hàng.
        </p>
      </div>

      <div className="mt-8 grid gap-6 text-sm text-foreground/90 leading-relaxed md:grid-cols-2">
        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">1. Thu thập thông tin</h2>
          <p className="mt-2 text-muted-foreground">
            Chúng tôi chỉ thu thập các thông tin tối thiểu cần thiết để vận hành dịch vụ: Email, Tên hiển thị (qua đăng nhập Google hoặc Local), Lịch sử nạp tiền và số lượng token tiêu thụ của từng model API.
          </p>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">2. Cam kết về dữ liệu Prompt và API</h2>
          <ul className="mt-3 space-y-2 text-muted-foreground list-disc pl-5">
            <li><strong>Không lưu trữ nội dung Prompt:</strong> Dữ liệu hội thoại và prompt được chuyển tiếp trực tiếp (pass-through) đến các cụm máy chủ xử lý mô hình AI và không được lưu trữ vĩnh viễn trên cơ sở dữ liệu của chúng tôi.</li>
            <li><strong>Không sử dụng dữ liệu để huấn luyện (No Training):</strong> Mọi dữ liệu gửi qua API của bạn tuyệt đối không được sử dụng để huấn luyện hay tinh chỉnh lại các mô hình AI.</li>
            <li><strong>Mã hóa đầu cuối:</strong> Mọi kết nối truyền tải đều được mã hóa bằng chuẩn TLS/HTTPS 256-bit an toàn cao.</li>
          </ul>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">3. Bảo mật thanh toán</h2>
          <p className="mt-2 text-muted-foreground">
            Các giao dịch chuyển khoản VietQR được đối soát tự động thông qua cổng thanh toán bảo mật của Ngân hàng ACB / SePay. Chúng tôi không lưu giữ thông tin thẻ tín dụng hay mật khẩu ngân hàng của quý khách.
          </p>
        </section>

        <section className="rounded-xl border border-border bg-card p-6 md:p-8">
          <h2 className="font-display text-lg font-bold text-foreground">4. Liên hệ bộ phận an toàn thông tin</h2>
          <p className="mt-2 text-muted-foreground">
            Mọi thắc mắc hoặc yêu cầu xóa dữ liệu tài khoản, quý khách vui lòng liên hệ qua Email: <strong className="text-primary font-mono">support@mitom.ai</strong> hoặc Hotline: <strong className="text-primary font-mono">0908.888.888</strong>.
          </p>
        </section>
      </div>
    </main>
  )
}
