import { useState, useEffect, type ReactNode } from "react"
import { api, type User, type Product, type Order, type Transaction } from "./services/api"
import logoImg from "./assets/images/logo.jpg"

type Category = "chat" | "image" | "code" | "token"
type Page = "home" | "topup" | "success"

interface TopUp {
  amount: number
  bonusPct: number
  label: string
  highlight: boolean
}

const CATEGORIES: { id: Category | "all"; label: string }[] = [
  { id: "all", label: "Tất cả" },
  { id: "chat", label: "Trợ lý Chat" },
  { id: "image", label: "Tạo ảnh" },
  { id: "code", label: "Lập trình" },
  { id: "token", label: "Gói Token" },
]

const TOPUPS: TopUp[] = [
  { amount: 100000, bonusPct: 0, label: "Khởi động", highlight: false },
  { amount: 200000, bonusPct: 5, label: "Tiết kiệm", highlight: false },
  { amount: 500000, bonusPct: 10, label: "Phổ biến", highlight: true },
  { amount: 1000000, bonusPct: 15, label: "Đại lý", highlight: false },
]

const FAQS = [
  {
    q: "Hệ thống Backend này hoạt động thế nào?",
    a: "Dự án sử dụng Backend độc lập (TypeScript + Express + SQLite/PostgreSQL) với bảo mật JWT, mã hóa bcrypt, giao dịch ACID và phân quyền Admin/Khách hàng tự chủ 100%, không dính vendor lock-in.",
  },
  {
    q: "Số dư nạp vào có bị hết hạn không?",
    a: "Không. Tiền bạn nạp được cộng vào số dư ví cá nhân và dùng đến khi nào hết thì thôi, không có kỳ hạn. Mỗi lần mua tài khoản hay token sẽ trừ trực tiếp vào số dư này.",
  },
  {
    q: "Mua công cụ AI thế nào?",
    a: "Bạn chỉ cần nạp tiền vào số dư, sau đó bấm 'Mua ngay' trên web. Hệ thống Backend sẽ tự động trừ ví và xuất Key / Tài khoản bản quyền ngay lập tức trong 1 giây.",
  },
  {
    q: "Chính sách bảo hành thế nào?",
    a: "Bảo hành 1 đổi 1 trong suốt thời gian sử dụng. Nếu tài khoản gặp lỗi, hệ thống hỗ trợ đổi mới miễn phí trong 24 giờ.",
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
        className="h-8 w-8 rounded-lg object-cover shadow-sm border border-border/60 group-hover:border-primary/50 transition-colors"
      />
      <span className="font-display text-xl font-extrabold tracking-tight">
        Mitom<span className="text-primary">.ai</span>
      </span>
    </a>
  )
}

export default function App() {
  const [activeCategory, setActiveCategory] = useState<Category | "all">("all")
  const [page, setPage] = useState<Page>("home")
  const [topup, setTopup] = useState<TopUp | null>(null)
  const [openFaq, setOpenFaq] = useState<number | null>(0)

  // Fullstack State
  const [user, setUser] = useState<User | null>(null)
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [authModalOpen, setAuthModalOpen] = useState(false)
  const [adminModalOpen, setAdminModalOpen] = useState(false)
  const [ordersModalOpen, setOrdersModalOpen] = useState(false)
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null)
  const [createdOrderResult, setCreatedOrderResult] = useState<any>(null)
  const [activeTopUpTx, setActiveTopUpTx] = useState<any>(null)

  // Khởi tạo & nạp dữ liệu từ Backend
  useEffect(() => {
    async function initApp() {
      let currentUser: User | null = null
      try {
        const prods = await api.products.getAll()
        setProducts(prods)
      } catch (err) {
        console.error("Lỗi lấy sản phẩm từ API:", err)
      }

      try {
        currentUser = await api.auth.getMe()
        setUser(currentUser)
      } catch {
        // Chưa đăng nhập
      } finally {
        setLoading(false)
      }

      // Tự động mở Admin Modal nếu vào URL /admin hoặc #admin
      const isTryingAdmin = window.location.pathname.includes("/admin") || window.location.hash.includes("admin")
      if (isTryingAdmin) {
        if (currentUser?.role === "admin") {
          setAdminModalOpen(true)
        } else {
          setAuthModalOpen(true)
        }
      }
    }
    initApp()
  }, [])

  const refreshUser = async () => {
    try {
      const me = await api.auth.getMe()
      setUser(me)
    } catch {
      setUser(null)
    }
  }

  const navigate = (p: Page) => {
    setPage(p)
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  const startTopup = async (t: TopUp) => {
    if (!user) {
      setAuthModalOpen(true)
      return
    }
    try {
      const tx = await api.payments.createTopUp(t.amount)
      setActiveTopUpTx(tx)
      setTopup(t)
      navigate("topup")
    } catch (err: any) {
      alert(err.message || "Không thể khởi tạo yêu cầu nạp tiền.")
    }
  }

  const goPricing = () => {
    if (page !== "home") {
      navigate("home")
      setTimeout(() => document.getElementById("pricing")?.scrollIntoView({ behavior: "smooth" }), 60)
    } else {
      document.getElementById("pricing")?.scrollIntoView({ behavior: "smooth" })
    }
  }

  const handleLogout = () => {
    api.auth.logout()
    setUser(null)
    alert("Đã đăng xuất tài khoản.")
  }

  const openAdmin = () => {
    if (user?.role === "admin") {
      setAdminModalOpen(true)
    } else {
      setAuthModalOpen(true)
    }
  }

  const filteredProducts = activeCategory === "all" ? products : products.filter((p) => p.tag === activeCategory)

  let content: ReactNode
  if (page === "topup" && topup && activeTopUpTx) {
    content = (
      <TopUpPage
        topup={topup}
        tx={activeTopUpTx}
        user={user}
        onDone={async () => {
          await refreshUser()
          navigate("success")
        }}
        onNavigate={navigate}
      />
    )
  } else if (page === "success") {
    content = <SuccessPage topup={topup} tx={activeTopUpTx} user={user} onNavigate={navigate} />
  } else {
    content = (
      <HomePage
        active={activeCategory}
        setActive={setActiveCategory}
        products={filteredProducts}
        openFaq={openFaq}
        setOpenFaq={setOpenFaq}
        onTopup={startTopup}
        goPricing={goPricing}
        user={user}
        onBuyProduct={(p) => {
          if (!user) {
            setAuthModalOpen(true)
          } else {
            setSelectedProduct(p)
          }
        }}
      />
    )
  }

  return (
    <div className="min-h-screen w-full bg-background text-foreground font-sans selection:bg-primary/20">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-border bg-background/85 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-3.5 md:px-8">
          <Logo onClick={() => navigate("home")} />

          <nav className="hidden items-center gap-7 text-sm font-medium text-secondary-foreground md:flex">
            <button onClick={() => navigate("home")} className="transition-colors hover:text-primary">
              Trang chủ
            </button>
            <button onClick={goPricing} className="transition-colors hover:text-primary">
              Bảng giá & Gói AI
            </button>
            <button onClick={goPricing} className="transition-colors hover:text-primary">
              Nạp tiền ví
            </button>
            <button onClick={openAdmin} className="transition-colors text-amber-400 hover:text-amber-300 font-semibold flex items-center gap-1">
              👑 Quản trị (Admin)
            </button>
            <a href={ZALO} target="_blank" rel="noreferrer" className="transition-colors hover:text-primary">
              Hỗ trợ Zalo
            </a>
          </nav>

          <div className="flex items-center gap-3">
            {user ? (
              <div className="flex items-center gap-3">
                {/* User Balance Badge */}
                <div
                  onClick={goPricing}
                  className="flex cursor-pointer items-center gap-2 rounded-lg border border-emerald/30 bg-emerald/10 px-3.5 py-1.5 transition-all hover:bg-emerald/20 shadow-sm"
                  title="Bấm để nạp thêm số dư"
                >
                  <span className="h-2 w-2 rounded-full bg-emerald animate-ping" />
                  <div className="text-left">
                    <div className="text-[10px] uppercase font-bold text-emerald leading-none">Số dư ví</div>
                    <div className="font-mono text-xs font-extrabold text-foreground leading-tight">
                      {formatVnd(user.balance)}
                    </div>
                  </div>
                </div>

                {/* My Orders Button */}
                <button
                  onClick={() => setOrdersModalOpen(true)}
                  className="hidden sm:inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-3.5 py-2 text-xs font-semibold hover:border-primary/50 transition-colors shadow-sm"
                >
                  📦 Đơn hàng
                </button>

                {/* Admin Button */}
                {user.role === "admin" && (
                  <button
                    onClick={() => setAdminModalOpen(true)}
                    className="rounded-lg bg-amber-500/15 border border-amber-500/30 px-3.5 py-2 text-xs font-bold text-amber-400 hover:bg-amber-500/25 transition-colors shadow-sm"
                  >
                    👑 Admin Panel
                  </button>
                )}

                {/* Logout */}
                <button
                  onClick={handleLogout}
                  className="rounded-lg border border-border bg-secondary px-3 py-2 text-xs font-semibold text-muted-foreground hover:text-foreground hover:border-destructive/50 transition-colors"
                  title="Đăng xuất"
                >
                  Thoát
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-2">
                <button
                  onClick={openAdmin}
                  className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs font-bold text-amber-400 hover:bg-amber-500/20 transition-colors"
                >
                  👑 Admin
                </button>
                <button
                  onClick={() => setAuthModalOpen(true)}
                  className="rounded-lg bg-primary px-4 py-2 text-xs md:text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02] shadow-md shadow-primary/20"
                >
                  Đăng nhập
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main>{content}</main>

      {/* Footer */}
      <footer className="border-t border-border bg-card/40">
        <div className="mx-auto grid max-w-7xl gap-8 px-5 py-14 md:grid-cols-4 md:px-8">
          <div className="md:col-span-1">
            <Logo onClick={() => navigate("home")} />
            <p className="mt-4 max-w-xs text-xs text-muted-foreground leading-relaxed">
              Hệ thống bán tài khoản & Token AI tự động. Backend độc lập, tự chủ 100% dữ liệu, giao dịch an toàn và minh bạch.
            </p>
          </div>
          {[
            ["Công cụ AI", ["ChatGPT Plus", "Claude Pro", "Midjourney", "Gói Token API 5M"]],
            ["Hỗ trợ & Bảo mật", ["Hướng dẫn nạp tiền", "Bảo hành 1 đổi 1", "Chính sách riêng tư", "API Docs"]],
            ["Tài khoản Test", ["Admin: admin@mitom.ai", "Pass: admin123456", "Demo: demo@mitom.ai", "Pass: demo123456"]],
          ].map(([title, links]) => (
            <div key={title as string}>
              <h4 className="font-display text-xs font-bold uppercase tracking-wide text-foreground">{title as string}</h4>
              <ul className="mt-3.5 space-y-2.5 text-xs text-muted-foreground">
                {(links as string[]).map((l) => (
                  <li key={l}>
                    <span className="hover:text-primary transition-colors cursor-pointer">{l}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="border-t border-border">
          <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-2 px-5 py-5 text-xs text-muted-foreground md:flex-row md:px-8">
            <span>© 2026 Mitom.ai — Fullstack E-Commerce Powered by Node.js & React</span>
            <span className="font-mono text-emerald text-xs">● Backend API Online (Local SQLite/WAL)</span>
          </div>
        </div>
      </footer>

      {/* MODALS */}
      {authModalOpen && (
        <AuthModal
          onClose={() => setAuthModalOpen(false)}
          onSuccess={(loggedInUser) => {
            setUser(loggedInUser)
            setAuthModalOpen(false)
          }}
        />
      )}

      {selectedProduct && (
        <PurchaseModal
          product={selectedProduct}
          user={user}
          onClose={() => {
            setSelectedProduct(null)
            setCreatedOrderResult(null)
          }}
          orderResult={createdOrderResult}
          onPurchaseSuccess={async (res) => {
            setCreatedOrderResult(res)
            await refreshUser()
          }}
          onNeedTopUp={() => {
            setSelectedProduct(null)
            goPricing()
          }}
        />
      )}

      {ordersModalOpen && (
        <OrdersModal
          onClose={() => setOrdersModalOpen(false)}
          onOpenProductDetail={() => {
            setOrdersModalOpen(false)
            goPricing()
          }}
        />
      )}

      {adminModalOpen && (
        <AdminModal
          onClose={() => setAdminModalOpen(false)}
          onDataChanged={async () => {
            const prods = await api.products.getAll()
            setProducts(prods)
            await refreshUser()
          }}
        />
      )}
    </div>
  )
}

/* =========================================================================
   HOME PAGE
   ========================================================================= */
function HomePage({
  active,
  setActive,
  products,
  openFaq,
  setOpenFaq,
  onTopup,
  goPricing,
  user,
  onBuyProduct,
}: {
  active: Category | "all"
  setActive: (c: Category | "all") => void
  products: Product[]
  openFaq: number | null
  setOpenFaq: (n: number | null) => void
  onTopup: (t: TopUp) => void
  goPricing: () => void
  user: User | null
  onBuyProduct: (p: Product) => void
}) {
  return (
    <>
      {/* Hero Section */}
      <section
        className="relative overflow-hidden border-b border-border"
        style={{
          backgroundImage:
            "linear-gradient(var(--grid-line, rgba(255,255,255,0.04)) 1px, transparent 1px), linear-gradient(90deg, var(--grid-line, rgba(255,255,255,0.04)) 1px, transparent 1px)",
          backgroundSize: "56px 56px",
        }}
      >
        <div className="pointer-events-none absolute -top-40 left-1/2 h-96 w-[46rem] -translate-x-1/2 rounded-full bg-primary/10 blur-[120px]" />
        <div className="mx-auto grid max-w-7xl gap-10 px-5 py-16 md:px-8 lg:grid-cols-[1.1fr_0.9fr] lg:py-24">
          <div className="flex flex-col justify-center">
            <span className="mb-4 inline-flex w-fit items-center gap-2 rounded-lg border border-border bg-card px-3.5 py-1.5 font-mono text-xs text-muted-foreground shadow-sm">
              <span className="h-2 w-2 rounded-full bg-emerald animate-ping" />
              Tự động kích hoạt & giao mã trong 1s
            </span>
            <h1 className="font-display text-4xl font-black leading-[1.08] tracking-tight md:text-5xl lg:text-6xl">
              Một số dư ví,
              <br />
              <span className="text-primary">mọi công cụ</span> AI.
            </h1>
            <p className="mt-5 max-w-lg text-sm leading-relaxed text-muted-foreground md:text-base">
              Nạp tiền vào tài khoản Mitom.ai rồi mua ngay ChatGPT Plus, Claude Pro, Midjourney, Gemini hay Token API. Hệ thống Backend độc lập tự động trừ ví và giao tài khoản tức thì!
            </p>
            <div className="mt-7 flex flex-wrap gap-3">
              <button
                onClick={goPricing}
                className="rounded-lg bg-primary px-6 py-3.5 text-sm font-bold text-primary-foreground transition-transform hover:scale-[1.02] shadow-md shadow-primary/20"
              >
                Nạp tiền ngay
              </button>
              <a
                href="#products"
                className="rounded-lg border border-border bg-card px-6 py-3.5 text-sm font-semibold text-secondary-foreground transition-colors hover:border-primary/60 shadow-sm"
              >
                Xem các gói AI ({products.length})
              </a>
            </div>
            <div className="mt-8 grid max-w-md grid-cols-3 gap-4 border-t border-border pt-6">
              {[
                ["100%", "Tự chủ Server"],
                ["< 1s", "Giao key tự động"],
                ["24/7", "Bảo hành 1-1"],
              ].map(([n, l]) => (
                <div key={l}>
                  <div className="font-display text-xl font-extrabold text-foreground">{n}</div>
                  <div className="text-xs text-muted-foreground">{l}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Wallet balance mockup / Live user state */}
          <div className="flex items-center justify-center">
            <div className="w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-2xl">
              <div className="flex items-center justify-between">
                <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
                  {user ? `Ví: ${user.name}` : "Ví Demo Mitom.ai"}
                </span>
                <span className="rounded-lg bg-emerald/15 px-2.5 py-1 font-mono text-[11px] font-bold text-emerald">
                  ● Trực tuyến
                </span>
              </div>
              <div className="mt-3 font-display text-3xl font-black text-primary">
                {user ? formatVnd(user.balance) : "1.000.000đ"}
              </div>
              <div className="mt-1 font-mono text-xs text-muted-foreground">Không kỳ hạn · Mua tự động không cần chờ</div>
              <div className="mt-5 space-y-3 border-t border-border pt-5">
                <span className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">Giao dịch gần đây</span>
                {[
                  ["Mua ChatGPT Plus", "−480.000đ", "#34d399", "AI"],
                  ["Mua Gói 5M Token API", "−350.000đ", "#60a5fa", "TK"],
                  ["Nạp qua VietQR", "+1.000.000đ", "#f5c451", "＋"],
                ].map(([name, amt, c, ini]) => (
                  <div key={name} className="flex items-center justify-between text-xs">
                    <div className="flex items-center gap-2.5">
                      <span
                        className="grid h-8 w-8 place-items-center rounded-lg font-mono text-xs font-bold"
                        style={{ background: `${c}20`, color: c }}
                      >
                        {ini}
                      </span>
                      <span className="font-medium">{name}</span>
                    </div>
                    <span className={`font-mono text-xs font-semibold ${amt.startsWith("+") ? "text-emerald" : "text-foreground"}`}>
                      {amt}
                    </span>
                  </div>
                ))}
              </div>
              <button
                onClick={goPricing}
                className="mt-5 w-full rounded-lg bg-primary py-3 text-xs font-bold text-primary-foreground hover:opacity-95 transition-opacity shadow-sm"
              >
                Nạp thêm số dư ví
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Trust bar */}
      <div className="border-b border-border bg-secondary/40">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-center gap-x-8 gap-y-2.5 px-5 py-3.5 font-mono text-xs text-muted-foreground md:px-8">
          {["VietQR Tự động", "MB Bank", "Vietcombank", "Techcombank", "Momo", "Bảo mật HMAC"].map((b) => (
            <span key={b} className="transition-colors hover:text-foreground">
              {b}
            </span>
          ))}
        </div>
      </div>

      {/* Products list */}
      <section id="products" className="mx-auto max-w-7xl px-5 py-20 md:px-8">
        <div className="flex flex-col gap-5 md:flex-row md:items-end md:justify-between">
          <div>
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Danh mục gói AI</span>
            <h2 className="mt-1 font-display text-2xl font-extrabold tracking-tight md:text-3xl">Các gói sẵn sàng mua</h2>
            <p className="mt-1.5 max-w-lg text-xs text-muted-foreground">
              Tất cả sản phẩm đều được quản lý trên Database SQLite Backend, mua và kích hoạt tức thì.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            {CATEGORIES.map((c) => (
              <button
                key={c.id}
                onClick={() => setActive(c.id)}
                className={`rounded-lg border px-3.5 py-1.5 text-xs font-medium transition-colors ${
                  active === c.id
                    ? "border-primary bg-primary text-primary-foreground font-bold shadow-sm"
                    : "border-border bg-card text-secondary-foreground hover:border-primary/50"
                }`}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {products.map((p) => (
            <article
              key={p.id}
              className="group relative flex flex-col overflow-hidden rounded-xl border border-border bg-card p-6 transition-all duration-200 hover:border-primary/50 hover:-translate-y-1 shadow-sm"
            >
              <div
                className="pointer-events-none absolute -right-16 -top-16 h-40 w-40 rounded-full opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-20"
                style={{ background: p.accent }}
              />
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <span
                    className="grid h-11 w-11 place-items-center rounded-lg font-mono text-xs font-bold"
                    style={{ background: `${p.accent}20`, color: p.accent }}
                  >
                    {p.initials}
                  </span>
                  <div>
                    <h3 className="font-display text-base font-bold leading-none">{p.name}</h3>
                    <span className="text-xs text-muted-foreground">{p.provider}</span>
                  </div>
                </div>
                {p.badge && (
                  <span className="rounded-md bg-primary/15 border border-primary/30 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-primary">
                    {p.badge}
                  </span>
                )}
              </div>

              <div className="mt-4 flex items-baseline gap-1.5">
                <span className="font-mono text-2xl font-black text-primary">{formatVnd(p.price)}</span>
                <span className="text-xs text-muted-foreground">/ tài khoản</span>
              </div>

              <p className="mt-2.5 text-xs leading-relaxed text-muted-foreground">{p.desc}</p>

              <ul className="mt-4 flex-1 space-y-2">
                {p.features.map((f) => (
                  <li key={f} className="flex items-center gap-2 text-xs text-secondary-foreground">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="shrink-0 text-emerald">
                      <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    {f}
                  </li>
                ))}
              </ul>

              <div className="mt-5 flex items-center justify-between border-t border-border pt-4 text-xs">
                <span className="inline-flex items-center gap-1.5 font-medium text-emerald text-xs">
                  <span className="h-2 w-2 rounded-full bg-emerald animate-pulse" /> Sẵn trong kho ({p.stock ?? 99})
                </span>
                <span className="font-mono text-muted-foreground text-xs">{p.eta}</span>
              </div>

              <button
                onClick={() => onBuyProduct(p)}
                className="mt-4 w-full rounded-lg bg-primary py-2.5 text-center text-xs font-bold text-primary-foreground transition-all hover:brightness-110 shadow-sm shadow-primary/20"
              >
                ⚡ Mua ngay
              </button>
            </article>
          ))}
        </div>
      </section>

      {/* Pricing / Top-Up Section */}
      <section id="pricing" className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-7xl px-5 py-20 md:px-8">
          <div className="text-center">
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Nạp tiền số dư</span>
            <h2 className="mt-1 font-display text-2xl font-extrabold tracking-tight md:text-3xl">Nạp một lần, dùng thoải mái</h2>
            <p className="mx-auto mt-2 max-w-xl text-xs text-muted-foreground">
              Quét mã VietQR tự động cộng số dư vào ví trong 5 giây. Khuyến mãi lên tới +15% giá trị nạp.
            </p>
          </div>

          <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {TOPUPS.map((t) => {
              const bonus = Math.round((t.amount * t.bonusPct) / 100)
              return (
                <div
                  key={t.amount}
                  className={`relative flex flex-col rounded-xl border p-6 transition-transform hover:-translate-y-1 ${
                    t.highlight ? "border-primary bg-card shadow-xl shadow-primary/10" : "border-border bg-card"
                  }`}
                >
                  {t.highlight && (
                    <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-md bg-primary px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-primary-foreground shadow-sm">
                      Nhiều người chọn
                    </span>
                  )}
                  <span className="font-mono text-xs uppercase tracking-wide text-muted-foreground">{t.label}</span>
                  <div className="mt-2.5 font-display text-3xl font-black">{formatVnd(t.amount)}</div>
                  {t.bonusPct > 0 ? (
                    <div className="mt-2 inline-flex w-fit items-center gap-1.5 rounded-lg bg-emerald/15 px-2.5 py-0.5 text-xs font-bold text-emerald">
                      +{t.bonusPct}% tặng {formatVnd(bonus)}
                    </div>
                  ) : (
                    <div className="mt-2 text-xs text-muted-foreground">Nạp nhanh, dùng ngay</div>
                  )}
                  <div className="mt-5 border-t border-border pt-4 text-xs text-muted-foreground">Số dư thực nhận</div>
                  <div className="font-mono text-lg font-bold text-primary">{formatVnd(t.amount + bonus)}</div>
                  <button
                    onClick={() => onTopup(t)}
                    className={`mt-5 rounded-lg py-3 text-xs font-bold transition-transform hover:scale-[1.02] shadow-sm ${
                      t.highlight
                        ? "bg-primary text-primary-foreground"
                        : "border border-border bg-secondary text-secondary-foreground hover:border-primary/60"
                    }`}
                  >
                    Nạp {formatVnd(t.amount)}
                  </button>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="border-t border-border bg-secondary/20">
        <div className="mx-auto grid max-w-7xl gap-8 px-5 py-20 md:px-8 lg:grid-cols-[0.8fr_1.2fr]">
          <div>
            <span className="font-mono text-xs uppercase tracking-widest text-primary">// Hỏi đáp & Kỹ thuật</span>
            <h2 className="mt-1 font-display text-2xl font-extrabold tracking-tight md:text-3xl">Giải đáp thắc mắc</h2>
            <p className="mt-3 text-xs text-muted-foreground leading-relaxed">
              Hệ thống được thiết kế theo mô hình Self-Hosted độc lập, đảm bảo hiệu năng và an toàn dữ liệu.
            </p>
          </div>
          <div className="divide-y divide-border rounded-xl border border-border bg-card">
            {FAQS.map((item, i) => (
              <button
                key={item.q}
                onClick={() => setOpenFaq(openFaq === i ? null : i)}
                className="flex w-full flex-col px-6 py-4.5 text-left"
              >
                <div className="flex items-center justify-between gap-4">
                  <span className="font-display text-sm font-bold">{item.q}</span>
                  <svg
                    width="16"
                    height="16"
                    viewBox="0 0 24 24"
                    fill="none"
                    className={`shrink-0 text-primary transition-transform ${openFaq === i ? "rotate-45" : ""}`}
                  >
                    <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                  </svg>
                </div>
                <div className={`grid transition-all duration-200 ${openFaq === i ? "mt-3 grid-rows-[1fr]" : "grid-rows-[0fr]"}`}>
                  <p className="overflow-hidden text-xs leading-relaxed text-muted-foreground">{item.a}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      </section>
    </>
  )
}

/* =========================================================================
   TOP UP PAGE
   ========================================================================= */
function TopUpPage({
  topup,
  tx,
  user,
  onDone,
  onNavigate,
}: {
  topup: TopUp
  tx: any
  user: User | null
  onDone: () => void
  onNavigate: (p: Page) => void
}) {
  const [submitting, setSubmitting] = useState(false)
  const bonus = tx?.bonusAmount ?? Math.round((topup.amount * topup.bonusPct) / 100)
  const totalCredit = tx?.totalCredit ?? topup.amount + bonus

  const handleConfirm = async () => {
    setSubmitting(true)
    try {
      await api.payments.confirmTopUp(tx.transactionId)
      onDone()
    } catch (err: any) {
      alert(err.message || "Xác nhận nạp tiền thất bại.")
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="mx-auto max-w-4xl px-5 py-14 md:px-8">
      <button
        onClick={() => onNavigate("home")}
        className="mb-5 inline-flex items-center gap-1.5 text-xs text-muted-foreground transition-colors hover:text-primary"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
          <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Quay lại bảng giá
      </button>

      <h1 className="font-display text-3xl font-extrabold tracking-tight">Nạp {formatVnd(topup.amount)} vào số dư ví</h1>

      <div className="mt-8 grid gap-6 lg:grid-cols-[1.5fr_1fr]">
        <div className="space-y-6">
          {/* VietQR Scan Card */}
          <div className="rounded-xl border border-primary/40 bg-card p-6 shadow-md">
            <h2 className="font-display text-base font-bold flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald animate-ping" /> Quét mã VietQR chuyển khoản
            </h2>

            <div className="mt-5 flex flex-col sm:flex-row items-center gap-5 bg-secondary/30 p-5 rounded-xl border border-border">
              {tx.qrCodeUrl ? (
                <img src={tx.qrCodeUrl} alt="VietQR" className="h-44 w-44 rounded-lg bg-white p-1.5 border shadow-sm" />
              ) : (
                <div className="h-44 w-44 rounded-lg bg-white flex items-center justify-center text-xs text-black">Mã QR</div>
              )}
              <div className="space-y-2 text-xs">
                <div>
                  <span className="text-[11px] text-muted-foreground block">Ngân hàng & Số tài khoản:</span>
                  <span className="font-mono font-bold text-sm">MB Bank · 0908888888</span>
                </div>
                <div>
                  <span className="text-[11px] text-muted-foreground block">Chủ tài khoản:</span>
                  <span className="font-bold text-sm">NGUYEN VAN A</span>
                </div>
                <div>
                  <span className="text-[11px] text-muted-foreground block">Số tiền chính xác:</span>
                  <span className="font-mono font-bold text-primary text-base">{formatVnd(topup.amount)}</span>
                </div>
                <div className="rounded-lg bg-primary/10 border border-primary/30 p-2.5">
                  <span className="text-[10px] text-muted-foreground block">Nội dung chuyển khoản (bắt buộc):</span>
                  <span className="font-mono font-extrabold text-primary text-sm select-all">{tx.paymentCode}</span>
                </div>
              </div>
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              💡 Sau khi chuyển khoản xong với nội dung trên, bấm nút <strong>"Xác nhận đã chuyển"</strong> để hệ thống cộng ngay số dư.
            </p>
          </div>
        </div>

        {/* Summary Card */}
        <aside className="h-fit rounded-xl border border-border bg-card p-6 shadow-md">
          <h2 className="font-display text-base font-bold">Tóm tắt nạp tiền</h2>
          <dl className="mt-4 space-y-2.5 text-xs">
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Tài khoản</dt>
              <dd className="font-medium text-foreground">{user?.email}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Số tiền nạp</dt>
              <dd className="font-mono">{formatVnd(topup.amount)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Khuyến mãi ({topup.bonusPct}%)</dt>
              <dd className="font-mono text-emerald">+{formatVnd(bonus)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Phí nạp</dt>
              <dd className="font-mono text-emerald">0đ (Miễn phí)</dd>
            </div>
          </dl>
          <div className="mt-5 flex items-baseline justify-between border-t border-border pt-4">
            <span className="text-xs text-muted-foreground">Số dư thực nhận</span>
            <span className="font-mono text-2xl font-black text-primary">{formatVnd(totalCredit)}</span>
          </div>

          <button
            onClick={handleConfirm}
            disabled={submitting}
            className="mt-6 w-full rounded-lg bg-primary py-3.5 text-xs font-bold text-primary-foreground transition-transform hover:scale-[1.02] disabled:opacity-50 shadow-md shadow-primary/20"
          >
            {submitting ? "Đang xác thực..." : "Xác nhận đã chuyển khoản"}
          </button>
        </aside>
      </div>
    </section>
  )
}

/* =========================================================================
   SUCCESS PAGE
   ========================================================================= */
function SuccessPage({ topup, tx, user, onNavigate }: { topup: TopUp | null; tx: any; user: User | null; onNavigate: (p: Page) => void }) {
  const totalCredit = tx?.totalCredit ?? (topup ? topup.amount + Math.round((topup.amount * topup.bonusPct) / 100) : 0)

  return (
    <section className="mx-auto max-w-2xl px-5 py-20 md:px-8">
      <div className="rounded-xl border border-emerald/30 bg-card p-10 text-center shadow-2xl">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald/15 animate-bounce">
          <svg width="28" height="28" viewBox="0 0 24 24" fill="none" className="text-emerald">
            <path d="M20 6 9 17l-5-5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h1 className="mt-5 font-display text-2xl font-black tracking-tight">Nạp tiền thành công!</h1>
        <p className="mx-auto mt-2 max-w-md text-muted-foreground text-xs">
          Số dư <strong className="text-emerald font-mono">+{formatVnd(totalCredit)}</strong> đã được ghi nhận vào ví của tài khoản{" "}
          <strong className="text-foreground">{user?.email}</strong>.
        </p>

        <div className="mx-auto mt-6 max-w-xs space-y-3">
          <div className="flex items-center justify-between rounded-lg border border-border bg-secondary/40 px-5 py-3.5">
            <span className="text-xs text-muted-foreground">Số dư hiện tại</span>
            <span className="font-mono text-base font-bold text-primary">{user ? formatVnd(user.balance) : formatVnd(totalCredit)}</span>
          </div>
          <div className="flex items-center justify-between rounded-lg border border-border bg-secondary/40 px-5 py-3.5">
            <span className="text-xs text-muted-foreground">Mã giao dịch</span>
            <span className="font-mono text-xs font-bold">{tx?.transactionId || "#TX-SUCCESS"}</span>
          </div>
        </div>

        <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
          <button
            onClick={() => onNavigate("home")}
            className="rounded-lg bg-primary px-6 py-3 text-xs font-bold text-primary-foreground transition-transform hover:scale-[1.02] shadow-md shadow-primary/20"
          >
            Mua gói công cụ ngay
          </button>
        </div>
      </div>
    </section>
  )
}

/* =========================================================================
   AUTH MODAL (LOGIN & REGISTER)
   ========================================================================= */
function AuthModal({ onClose, onSuccess }: { onClose: () => void; onSuccess: (u: User) => void }) {
  const [tab, setTab] = useState<"login" | "register">("login")
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [name, setName] = useState("")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      if (tab === "login") {
        const res = await api.auth.login(email, password)
        onSuccess(res.user)
      } else {
        const res = await api.auth.register(email, password, name)
        onSuccess(res.user)
      }
    } catch (err: any) {
      setError(err.message || "Có lỗi xảy ra.")
    } finally {
      setLoading(false)
    }
  }

  const quickLogin = async (quickEmail: string, quickPass: string) => {
    setEmail(quickEmail)
    setPassword(quickPass)
    setError(null)
    setLoading(true)
    try {
      const res = await api.auth.login(quickEmail, quickPass)
      onSuccess(res.user)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-md rounded-xl border border-border bg-card p-6 shadow-2xl">
        <button onClick={onClose} className="absolute right-4 top-4 text-muted-foreground hover:text-foreground">
          ✕
        </button>

        <div className="flex border-b border-border mb-5">
          <button
            onClick={() => {
              setTab("login")
              setError(null)
            }}
            className={`flex-1 pb-3 text-xs font-bold transition-colors ${
              tab === "login" ? "border-b-2 border-primary text-primary" : "text-muted-foreground"
            }`}
          >
            Đăng nhập
          </button>
          <button
            onClick={() => {
              setTab("register")
              setError(null)
            }}
            className={`flex-1 pb-3 text-xs font-bold transition-colors ${
              tab === "register" ? "border-b-2 border-primary text-primary" : "text-muted-foreground"
            }`}
          >
            Đăng ký tài khoản
          </button>
        </div>

        {/* Quick Test Accounts for 1-Click login */}
        <div className="mb-5 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3">
          <span className="text-[11px] font-bold text-amber-400 block mb-2">
            ⚡ Đăng nhập nhanh 1-Click (Không cần gõ mật khẩu):
          </span>
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => quickLogin("admin@mitom.ai", "admin123456")}
              disabled={loading}
              className="rounded-lg border border-amber-500/40 bg-amber-500/20 p-2.5 text-left text-xs hover:bg-amber-500/30 transition-all font-semibold disabled:opacity-50"
            >
              <div className="font-bold text-amber-300 flex items-center gap-1">👑 Admin Quản trị</div>
              <div className="text-[10px] text-muted-foreground font-mono">admin@mitom.ai</div>
            </button>
            <button
              onClick={() => quickLogin("demo@mitom.ai", "demo123456")}
              disabled={loading}
              className="rounded-lg border border-border bg-secondary/80 p-2.5 text-left text-xs hover:border-primary/50 transition-all font-semibold disabled:opacity-50"
            >
              <div className="font-bold text-foreground flex items-center gap-1">👤 Khách Demo</div>
              <div className="text-[10px] text-emerald font-mono">Ví 1.000.000đ</div>
            </button>
          </div>
        </div>

        {error && <div className="mb-4 rounded-lg bg-destructive/15 border border-destructive/30 p-3 text-xs text-destructive">{error}</div>}

        <form onSubmit={handleSubmit} className="space-y-4">
          {tab === "register" && (
            <div>
              <label className="block text-xs font-semibold text-muted-foreground mb-1">Họ và tên</label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
                placeholder="Nguyễn Văn A"
                className="w-full rounded-lg border border-border bg-secondary/50 px-3.5 py-2.5 text-xs focus:border-primary focus:outline-none"
              />
            </div>
          )}
          <div>
            <label className="block text-xs font-semibold text-muted-foreground mb-1">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              placeholder="user@example.com"
              className="w-full rounded-lg border border-border bg-secondary/50 px-3.5 py-2.5 text-xs focus:border-primary focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-muted-foreground mb-1">Mật khẩu</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              placeholder="••••••••"
              className="w-full rounded-lg border border-border bg-secondary/50 px-3.5 py-2.5 text-xs focus:border-primary focus:outline-none"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-primary py-3 text-xs font-bold text-primary-foreground hover:brightness-110 disabled:opacity-50 shadow-sm"
          >
            {loading ? "Đang xử lý..." : tab === "login" ? "Đăng nhập" : "Đăng ký ngay"}
          </button>
        </form>
      </div>
    </div>
  )
}

/* =========================================================================
   PURCHASE MODAL
   ========================================================================= */
function PurchaseModal({
  product,
  user,
  onClose,
  orderResult,
  onPurchaseSuccess,
  onNeedTopUp,
}: {
  product: Product
  user: User | null
  onClose: () => void
  orderResult: any
  onPurchaseSuccess: (res: any) => Promise<void>
  onNeedTopUp: () => void
}) {
  const [method, setMethod] = useState<"balance" | "vietqr">("balance")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleBuy = async () => {
    if (!user) return
    setError(null)
    setLoading(true)
    try {
      const res = await api.orders.create(product.id, method)
      await onPurchaseSuccess(res)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const hasEnoughBalance = (user?.balance ?? 0) >= product.price

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-md rounded-xl border border-border bg-card p-6 shadow-2xl">
        <button onClick={onClose} className="absolute right-4 top-4 text-muted-foreground hover:text-foreground">
          ✕
        </button>

        {orderResult ? (
          <div className="text-center py-4">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald/20 text-emerald text-xl mb-3 animate-bounce">
              ✓
            </div>
            <h2 className="font-display text-xl font-black">Mua hàng thành công!</h2>
            <p className="text-xs text-muted-foreground mt-1">Đơn hàng: <strong className="font-mono text-foreground">{orderResult.orderId}</strong></p>

            <div className="mt-5 rounded-lg border border-emerald/40 bg-emerald/10 p-4 text-left">
              <span className="text-[11px] uppercase font-bold text-emerald block mb-1">🔑 Thông tin tài khoản / Key nhận được:</span>
              <div className="rounded-lg bg-black/40 p-3 font-mono text-xs text-foreground select-all break-all border border-emerald/30">
                {orderResult.deliveryContent}
              </div>
            </div>

            <button
              onClick={onClose}
              className="mt-5 w-full rounded-lg bg-primary py-3 text-xs font-bold text-primary-foreground shadow-md shadow-primary/20"
            >
              Hoàn tất
            </button>
          </div>
        ) : (
          <div>
            <h2 className="font-display text-xl font-black">Xác nhận thanh toán</h2>
            <div className="mt-4 flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-4">
              <span
                className="grid h-10 w-10 place-items-center rounded-lg font-mono text-xs font-bold"
                style={{ background: `${product.accent}20`, color: product.accent }}
              >
                {product.initials}
              </span>
              <div className="flex-1">
                <div className="font-bold text-xs">{product.name}</div>
                <div className="text-[11px] text-muted-foreground">{product.provider}</div>
              </div>
              <div className="font-mono font-bold text-primary text-sm">{formatVnd(product.price)}</div>
            </div>

            {error && <div className="mt-3.5 rounded-lg bg-destructive/15 border border-destructive/30 p-3 text-xs text-destructive">{error}</div>}

            <div className="mt-4 space-y-3">
              <label className="block text-xs font-semibold text-muted-foreground">Chọn hình thức thanh toán:</label>

              <label
                className={`flex cursor-pointer items-center justify-between rounded-lg border p-3.5 transition-colors ${
                  method === "balance" ? "border-primary bg-primary/5" : "border-border hover:border-primary/40"
                }`}
              >
                <div className="flex items-center gap-3">
                  <input type="radio" checked={method === "balance"} onChange={() => setMethod("balance")} className="sr-only" />
                  <span className={`grid h-4 w-4 place-items-center rounded-full border-2 ${method === "balance" ? "border-primary" : "border-border"}`}>
                    {method === "balance" && <span className="h-2 w-2 rounded-full bg-primary" />}
                  </span>
                  <div>
                    <div className="text-xs font-bold">Số dư ví cá nhân</div>
                    <div className="text-[11px] text-muted-foreground font-mono">
                      Hiện có: {formatVnd(user?.balance ?? 0)}
                    </div>
                  </div>
                </div>
                {hasEnoughBalance ? (
                  <span className="text-[11px] text-emerald font-semibold">Khả dụng</span>
                ) : (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      onNeedTopUp()
                    }}
                    className="text-[11px] font-bold text-amber-400 hover:underline"
                  >
                    + Nạp thêm
                  </button>
                )}
              </label>

              <label
                className={`flex cursor-pointer items-center justify-between rounded-lg border p-3.5 transition-colors ${
                  method === "vietqr" ? "border-primary bg-primary/5" : "border-border hover:border-primary/40"
                }`}
              >
                <div className="flex items-center gap-3">
                  <input type="radio" checked={method === "vietqr"} onChange={() => setMethod("vietqr")} className="sr-only" />
                  <span className={`grid h-4 w-4 place-items-center rounded-full border-2 ${method === "vietqr" ? "border-primary" : "border-border"}`}>
                    {method === "vietqr" && <span className="h-2 w-2 rounded-full bg-primary" />}
                  </span>
                  <div>
                    <div className="text-xs font-bold">Quét VietQR chuyển khoản</div>
                    <div className="text-[11px] text-muted-foreground">Tự động kích hoạt sau khi thanh toán</div>
                  </div>
                </div>
              </label>
            </div>

            <button
              onClick={handleBuy}
              disabled={loading || (method === "balance" && !hasEnoughBalance)}
              className="mt-5 w-full rounded-lg bg-primary py-3 text-xs font-bold text-primary-foreground hover:brightness-110 disabled:opacity-50 shadow-md shadow-primary/20"
            >
              {loading ? "Đang xử lý đơn hàng..." : `Thanh toán ${formatVnd(product.price)}`}
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

/* =========================================================================
   MY ORDERS MODAL
   ========================================================================= */
function OrdersModal({ onClose, onOpenProductDetail }: { onClose: () => void; onOpenProductDetail: () => void }) {
  const [orders, setOrders] = useState<Order[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.orders
      .getMyOrders()
      .then(setOrders)
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-xl max-h-[85vh] flex flex-col rounded-xl border border-border bg-card p-6 shadow-2xl">
        <button onClick={onClose} className="absolute right-4 top-4 text-muted-foreground hover:text-foreground">
          ✕
        </button>

        <h2 className="font-display text-xl font-black mb-1">📦 Đơn hàng & Kho Key của tôi</h2>
        <p className="text-xs text-muted-foreground mb-4">Các tài khoản và key bản quyền đã mua được lưu trữ bảo mật tại đây.</p>

        <div className="flex-1 overflow-y-auto space-y-3 pr-1">
          {loading ? (
            <div className="text-center py-10 text-muted-foreground text-xs">Đang tải đơn hàng...</div>
          ) : orders.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <div className="text-3xl mb-2">🛒</div>
              <div className="text-xs font-semibold">Chưa có đơn hàng nào</div>
              <button onClick={onOpenProductDetail} className="mt-3 text-xs text-primary font-bold hover:underline">
                Xem danh mục sản phẩm
              </button>
            </div>
          ) : (
            orders.map((o) => (
              <div key={o.id} className="rounded-lg border border-border bg-secondary/20 p-4 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-mono font-bold text-xs text-foreground">{o.id}</span>
                  <span
                    className={`rounded-md px-2.5 py-0.5 text-[10px] font-bold ${
                      o.status === "completed"
                        ? "bg-emerald/20 text-emerald"
                        : o.status === "paid"
                        ? "bg-blue-500/20 text-blue-400"
                        : "bg-amber-500/20 text-amber-400"
                    }`}
                  >
                    {o.status === "completed" ? "Đã giao hàng" : o.status === "paid" ? "Đã thanh toán" : "Đang chờ"}
                  </span>
                </div>
                <div className="flex justify-between items-baseline text-xs">
                  <span className="font-bold text-sm">{o.product_name}</span>
                  <span className="font-mono font-bold text-primary text-sm">{formatVnd(o.amount)}</span>
                </div>
                {o.delivery_content && (
                  <div className="mt-2 rounded-lg bg-black/40 border border-border p-2.5 font-mono text-[11px] text-muted-foreground select-all break-all">
                    🔑 {o.delivery_content}
                  </div>
                )}
                <div className="text-[10px] text-muted-foreground font-mono">
                  {new Date(o.created_at).toLocaleString("vi-VN")}
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

/* =========================================================================
   ADMIN DASHBOARD MODAL
   ========================================================================= */
function AdminModal({ onClose, onDataChanged }: { onClose: () => void; onDataChanged: () => Promise<void> }) {
  const [tab, setTab] = useState<"stats" | "pricing" | "users" | "orders" | "inventory">("stats")
  const [stats, setStats] = useState<any>(null)
  const [products, setProducts] = useState<Product[]>([])
  const [users, setUsers] = useState<User[]>([])
  const [orders, setOrders] = useState<Order[]>([])
  const [inventory, setInventory] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  // Edit price states
  const [editingPrices, setEditingPrices] = useState<Record<string, { cost: number; sale: number }>>({})
  const [savingPriceId, setSavingPriceId] = useState<string | null>(null)

  // Form states
  const [newKeyProd, setNewKeyProd] = useState("gpt-plus")
  const [newKeyData, setNewKeyData] = useState("")
  const [grantUserId, setGrantUserId] = useState("")
  const [grantAmount, setGrantAmount] = useState(100000)

  const loadData = async () => {
    setLoading(true)
    try {
      const [s, prods, u, o, inv] = await Promise.all([
        api.admin.getStats(),
        api.products.getAll(),
        api.admin.getUsers(),
        api.admin.getOrders(),
        api.admin.getInventoryKeys(),
      ])
      setStats(s.stats)
      setProducts(prods)
      setUsers(u)
      setOrders(o)
      setInventory(inv)

      const initialPrices: Record<string, { cost: number; sale: number }> = {}
      for (const p of prods) {
        initialPrices[p.id] = {
          cost: p.cost_price ?? 0,
          sale: p.price,
        }
      }
      setEditingPrices(initialPrices)
    } catch (err: any) {
      alert(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadData()
  }, [])

  const handleSavePrice = async (prodId: string) => {
    const edit = editingPrices[prodId]
    if (!edit) return
    setSavingPriceId(prodId)
    try {
      await api.admin.updateProductPricing(prodId, edit.cost, edit.sale)
      alert("Đã cập nhật giá gốc và giá bán thành công!")
      await loadData()
      await onDataChanged()
    } catch (err: any) {
      alert(err.message)
    } finally {
      setSavingPriceId(null)
    }
  }

  const handleAddKey = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newKeyData) return
    try {
      await api.admin.addInventoryKey(newKeyProd, newKeyData)
      setNewKeyData("")
      alert("Đã thêm key vào kho thành công!")
      await loadData()
      await onDataChanged()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const handleGrantBalance = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!grantUserId) return
    try {
      await api.admin.updateUserBalance(grantUserId, grantAmount, "Admin nạp trực tiếp")
      alert("Đã cập nhật số dư người dùng thành công!")
      await loadData()
      await onDataChanged()
    } catch (err: any) {
      alert(err.message)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-4xl max-h-[90vh] flex flex-col rounded-xl border border-border bg-card p-6 shadow-2xl">
        <button onClick={onClose} className="absolute right-4 top-4 text-muted-foreground hover:text-foreground">
          ✕
        </button>

        <div className="flex items-center gap-2 mb-4">
          <span className="rounded-md bg-amber-500/20 text-amber-400 px-2.5 py-0.5 text-[10px] font-bold font-mono">ADMIN</span>
          <h2 className="font-display text-xl font-black">Bảng điều khiển Quản trị Mì Tôm AI</h2>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 border-b border-border pb-3 mb-4 overflow-x-auto">
          {[
            ["stats", "📊 Thống kê & Lợi nhuận"],
            ["pricing", `🏷️ Quản lý Giá gốc & Giá bán (${products.length})`],
            ["users", `👥 Khách hàng (${users.length})`],
            ["orders", `📦 Đơn hàng (${orders.length})`],
            ["inventory", `🔑 Kho Key (${inventory.length})`],
          ].map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id as any)}
              className={`rounded-lg px-3.5 py-2 text-xs font-bold transition-colors shrink-0 ${
                tab === id ? "bg-primary text-primary-foreground shadow-sm" : "bg-secondary/60 text-secondary-foreground hover:bg-secondary"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <div className="flex-1 overflow-y-auto pr-1">
          {loading ? (
            <div className="text-center py-14 text-muted-foreground text-xs">Đang tải dữ liệu Quản trị...</div>
          ) : tab === "stats" && stats ? (
            <div className="space-y-6">
              {/* Stat Cards with Profit Margin */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <div className="rounded-lg border border-border bg-secondary/30 p-4">
                  <span className="text-[11px] text-muted-foreground block font-medium">💰 Tổng Doanh Thu</span>
                  <span className="font-mono text-xl font-black text-primary mt-1 block">{formatVnd(stats.totalRevenue)}</span>
                  <span className="text-[10px] text-muted-foreground">Tổng tiền bán ra</span>
                </div>
                <div className="rounded-lg border border-border bg-secondary/30 p-4">
                  <span className="text-[11px] text-muted-foreground block font-medium">📦 Tiền Vốn (Giá gốc)</span>
                  <span className="font-mono text-xl font-black text-amber-400 mt-1 block">{formatVnd(stats.totalCost)}</span>
                  <span className="text-[10px] text-muted-foreground">Tổng chi phí vốn nhập</span>
                </div>
                <div className="rounded-lg border border-emerald/40 bg-emerald/10 p-4 shadow-sm">
                  <span className="text-[11px] text-emerald block font-bold">📈 Lợi Nhuận Ròng (Lãi)</span>
                  <span className="font-mono text-xl font-black text-emerald mt-1 block">+{formatVnd(stats.totalProfit)}</span>
                  <span className="text-[10px] text-emerald font-mono">Tỷ suất lãi: {stats.profitMarginPct}%</span>
                </div>
                <div className="rounded-lg border border-border bg-secondary/30 p-4">
                  <span className="text-[11px] text-muted-foreground block font-medium">🔑 Key còn trong kho</span>
                  <span className="font-mono text-xl font-black text-foreground mt-1 block">{stats.availableKeys}</span>
                  <span className="text-[10px] text-muted-foreground">{stats.totalOrders} đơn đã hoàn tất</span>
                </div>
              </div>

              {/* Nạp tiền nhanh cho user */}
              <div className="rounded-lg border border-border bg-secondary/20 p-5">
                <h3 className="font-bold text-xs mb-3">⚡ Điều chỉnh / Cộng số dư ví trực tiếp cho Khách hàng</h3>
                <form onSubmit={handleGrantBalance} className="flex flex-wrap gap-3 items-center">
                  <select
                    value={grantUserId}
                    onChange={(e) => setGrantUserId(e.target.value)}
                    required
                    className="rounded-lg border border-border bg-card px-3 py-2 text-xs"
                  >
                    <option value="">-- Chọn Khách hàng --</option>
                    {users.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.name} ({u.email}) - Ví: {formatVnd(u.balance)}
                      </option>
                    ))}
                  </select>
                  <input
                    type="number"
                    value={grantAmount}
                    onChange={(e) => setGrantAmount(Number(e.target.value))}
                    step={10000}
                    placeholder="Số tiền (+/-)"
                    className="w-36 rounded-lg border border-border bg-card px-3 py-2 text-xs font-mono"
                  />
                  <button type="submit" className="rounded-lg bg-emerald px-4 py-2 text-xs font-bold text-black hover:opacity-90 shadow-sm">
                    Cập nhật số dư
                  </button>
                </form>
              </div>
            </div>
          ) : tab === "pricing" ? (
            <div className="space-y-4">
              <div className="rounded-lg border border-primary/30 bg-primary/5 p-3.5 text-xs text-muted-foreground">
                💡 <strong>Cơ chế Giá gốc & Giá bán:</strong> Bạn có thể tùy chỉnh tiền vốn nhập vào (Giá gốc) và giá bán niêm yết cho khách. Hệ thống sẽ tự động tính toán tiền lãi (+VNĐ) và tỷ suất lợi nhuận trên mỗi đơn hàng bán ra.
              </div>

              <div className="divide-y divide-border rounded-lg border border-border bg-card overflow-hidden">
                {products.map((p) => {
                  const edit = editingPrices[p.id] || { cost: p.cost_price ?? 0, sale: p.price }
                  const profit = edit.sale - edit.cost
                  const profitPct = edit.sale > 0 ? Math.round((profit / edit.sale) * 100) : 0

                  return (
                    <div key={p.id} className="p-4 flex flex-col md:flex-row md:items-center justify-between gap-4">
                      <div className="min-w-[180px]">
                        <div className="font-bold text-sm text-foreground">{p.name}</div>
                        <div className="text-xs text-muted-foreground font-mono">{p.provider} · ID: {p.id}</div>
                      </div>

                      <div className="flex flex-wrap items-center gap-3">
                        <div>
                          <label className="block text-[10px] text-muted-foreground font-medium mb-1">Giá gốc (Vốn nhập)</label>
                          <input
                            type="number"
                            value={edit.cost}
                            onChange={(e) =>
                              setEditingPrices((prev) => ({
                                ...prev,
                                [p.id]: { ...edit, cost: Number(e.target.value) },
                              }))
                            }
                            step={10000}
                            className="w-32 rounded-lg border border-border bg-secondary px-2.5 py-1.5 font-mono text-xs text-amber-400 font-bold"
                          />
                        </div>

                        <div>
                          <label className="block text-[10px] text-muted-foreground font-medium mb-1">Giá bán ra</label>
                          <input
                            type="number"
                            value={edit.sale}
                            onChange={(e) =>
                              setEditingPrices((prev) => ({
                                ...prev,
                                [p.id]: { ...edit, sale: Number(e.target.value) },
                              }))
                            }
                            step={10000}
                            className="w-32 rounded-lg border border-border bg-secondary px-2.5 py-1.5 font-mono text-xs text-primary font-bold"
                          />
                        </div>

                        <div className="min-w-[110px]">
                          <label className="block text-[10px] text-muted-foreground font-medium mb-1">Tiền lãi dự kiến</label>
                          <div className="font-mono text-xs font-black text-emerald">
                            +{formatVnd(profit)}
                            <span className="text-[10px] text-muted-foreground ml-1">({profitPct}%)</span>
                          </div>
                        </div>

                        <button
                          onClick={() => handleSavePrice(p.id)}
                          disabled={savingPriceId === p.id}
                          className="mt-4 md:mt-0 rounded-lg bg-primary px-3.5 py-1.5 text-xs font-bold text-primary-foreground hover:brightness-110 disabled:opacity-50 shadow-sm"
                        >
                          {savingPriceId === p.id ? "Đang lưu..." : "Lưu giá"}
                        </button>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          ) : tab === "users" ? (
            <div className="divide-y divide-border rounded-lg border border-border bg-card">
              {users.map((u) => (
                <div key={u.id} className="flex items-center justify-between p-3.5 text-xs">
                  <div>
                    <div className="font-bold text-foreground">
                      {u.name} {u.role === "admin" && <span className="text-amber-400 font-mono">(Admin)</span>}
                    </div>
                    <div className="text-muted-foreground font-mono">{u.email}</div>
                  </div>
                  <div className="text-right font-mono">
                    <div className="font-bold text-primary">{formatVnd(u.balance)}</div>
                    <div className="text-[10px] text-muted-foreground">{u.id}</div>
                  </div>
                </div>
              ))}
            </div>
          ) : tab === "orders" ? (
            <div className="space-y-3">
              {orders.map((o) => (
                <div key={o.id} className="rounded-lg border border-border bg-secondary/20 p-3.5 text-xs space-y-1.5">
                  <div className="flex justify-between items-center">
                    <span className="font-mono font-bold">{o.id} · {o.user_email}</span>
                    <span className="rounded-md px-2 py-0.5 font-bold bg-emerald/20 text-emerald text-[10px]">{o.status}</span>
                  </div>
                  <div className="flex justify-between items-baseline font-bold">
                    <span>{o.product_name}</span>
                    <div className="space-x-3 font-mono">
                      <span className="text-muted-foreground text-[11px]">Vốn: {formatVnd(o.cost_price ?? 0)}</span>
                      <span className="text-primary">Thu: {formatVnd(o.amount)}</span>
                      <span className="text-emerald">Lãi: +{formatVnd(o.profit ?? o.amount - (o.cost_price ?? 0))}</span>
                    </div>
                  </div>
                  {o.delivery_content && (
                    <div className="rounded-lg bg-black/40 p-2.5 font-mono text-[11px] text-muted-foreground select-all">
                      {o.delivery_content}
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="space-y-5">
              {/* Add Key Form */}
              <form onSubmit={handleAddKey} className="rounded-lg border border-border bg-secondary/20 p-4 space-y-3">
                <h3 className="font-bold text-xs">➕ Thêm Key / Tài khoản vào kho tự động giao</h3>
                <div className="grid sm:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[11px] text-muted-foreground mb-1">Chọn sản phẩm</label>
                    <select
                      value={newKeyProd}
                      onChange={(e) => setNewKeyProd(e.target.value)}
                      className="w-full rounded-lg border border-border bg-card px-3 py-2 text-xs"
                    >
                      {products.map((p) => (
                        <option key={p.id} value={p.id}>{p.name}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] text-muted-foreground mb-1">Nội dung Key / Tài khoản</label>
                    <input
                      type="text"
                      value={newKeyData}
                      onChange={(e) => setNewKeyData(e.target.value)}
                      required
                      placeholder="Email: pass hoặc API Key sk-..."
                      className="w-full rounded-lg border border-border bg-card px-3 py-2 text-xs"
                    />
                  </div>
                </div>
                <button type="submit" className="rounded-lg bg-primary px-4 py-2 text-xs font-bold text-primary-foreground shadow-sm">
                  Lưu vào kho
                </button>
              </form>

              {/* Keys list */}
              <div className="divide-y divide-border rounded-lg border border-border bg-card">
                {inventory.map((k) => (
                  <div key={k.id} className="flex items-center justify-between p-3 text-xs">
                    <div>
                      <span className="font-bold text-foreground">{k.product_name || k.product_id}</span>
                      <div className="font-mono text-muted-foreground select-all text-[11px]">{k.key_data}</div>
                    </div>
                    <span className={`font-mono text-[10px] font-bold ${k.is_used ? "text-muted-foreground" : "text-emerald"}`}>
                      {k.is_used ? "Đã giao" : "Có sẵn"}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
