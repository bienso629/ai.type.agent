// === BEGIN server.js (fonts fixed: CORS + CSS url() rewrite + minify + pull-through) ===
const express = require('express');
const app = express();
const port = 3333;

const request = require('request').defaults({ encoding: null });
const url = require('url');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const mime = require('mime-types');
const helmet = require('helmet');

// ===== SECURITY CONFIGURATION =====
const SECRET_API_KEY = process.env.API_KEY;
const ALLOWED_DOMAINS = ['yenai.vn', 'ai.type.vn', 'nguoitroly.com', 'tanngoctax.vn', 'plugin.type.vn', 'plugins.type.vn', 'hopthu.vn'];
const ALLOWED_EXTS = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.css', '.js', '.woff', '.woff2', '.ttf', '.eot', '.json', '.xml', '.txt', '.pdf'];
// ==================================

// (Các import “gen ai …” của bạn nếu cần, để nguyên như bản cũ)

// — Minifiers —
const Terser = require('terser'); // JS
const csso = require('csso');   // CSS

// ===== Global CORS (an toàn cho API); riêng /assets sẽ override thành wildcard =====
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use((req, res, next) => {
  const origin = req.get('origin');
  res.header('Access-Control-Allow-Origin', origin || '*');
  res.header('Vary', 'Origin');
  res.header('Access-Control-Allow-Credentials', 'true');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH, HEAD');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Accept, X-Requested-With, Referer, Range, x-api-key');
  if (req.method === 'OPTIONS') return res.status(200).send({ ok: true });
  next();
});

app.use((req, res, next) => { // No-cache cho route động
  res.setHeader('Cache-Control', 'no-store');
  next();
});

app.get('/', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.sendFile(path.join(__dirname, 'views', 'homepage.html'));
});

// ===== /assets =====
const ASSETS_ROOT = path.join(__dirname, 'assets');

// Helpers
function ensureDirSync(dirPath) { try { fs.mkdirSync(dirPath, { recursive: true }); } catch (_) { } }

function parseCdnTargetToLocalPath(targetUrl) {
  try {
    const u = new URL(targetUrl);
    let p = decodeURIComponent(u.pathname || '');
    p = p.replace(/^\//, ''); // Remove leading slash

    // BẢO MẬT: Chống Path Traversal
    if (p.includes('..') || p.includes('\0')) return null;

    // BẢO MẬT: Chống upload file thực thi (PHP, HTML, EXE, SH...)
    const ext = path.extname(p).toLowerCase();
    if (ext && !ALLOWED_EXTS.includes(ext)) {
      console.warn(`[SECURITY] Blocked unsupported file extension: ${ext}`);
      return null;
    }

    if (p.startsWith('upload/') || p.startsWith('public/')) return null; // Avoid reserved paths

    const abs = path.normalize(path.join(ASSETS_ROOT, p));

    // BẢO MẬT: Đảm bảo file được ghi tuyệt đối nằm trong thư mục assets
    if (!abs.startsWith(path.normalize(ASSETS_ROOT))) {
      console.warn(`[SECURITY] Blocked path escaping ASSETS_ROOT: ${abs}`);
      return null;
    }

    return { abs, rel: p };
  } catch (e) { return null; }
}

function downloadToBuffer(fileUrl, headers = {}) {
  return new Promise((resolve, reject) => {
    request.get(
      {
        url: fileUrl, encoding: null, headers: Object.assign({
          'User-Agent': 'Mozilla/5.0',
          'Accept': '*/*',
          'Cache-Control': 'no-cache'
        }, headers)
      },
      (err, resp, body) => {
        if (err) return reject(err);
        if (!resp || resp.statusCode >= 400) return reject(new Error(`Download failed: ${resp && resp.statusCode}`));
        resolve(Buffer.isBuffer(body) ? body : Buffer.from(body || ''));
      }
    );
  });
}

// ——— CSS url() -> tuyệt đối về /assets/{host}/… để font/images không lệch ———
function rewriteCssRelativeUrlsToCdn(cssText, targetAbsPath) {
  // targetAbsPath = <...>/assets/{host}/<full/site/path>/file.css
  const relFromAssets = path.relative(ASSETS_ROOT, targetAbsPath); // host/…/file.css
  const parts = relFromAssets.split(path.sep);
  const host = parts.shift();
  const cssAbsDir = path.dirname(path.join(ASSETS_ROOT, relFromAssets)); // abs dir chứa CSS

  // regex url(...) cơ bản, bỏ qua data:, http:, //, absolute /
  return cssText.replace(/url\(\s*(['"]?)([^'")]+)\1\s*\)/gi, (m, quote, raw) => {
    let v = raw.trim();
    if (/^(data:|https?:|\/\/)/i.test(v)) return m; // giữ nguyên
    // tách query/hash
    let suffix = '';
    const q = v.indexOf('?'); const h = v.indexOf('#');
    let cut = -1;
    if (q >= 0 && h >= 0) cut = Math.min(q, h);
    else if (q >= 0) cut = q;
    else if (h >= 0) cut = h;
    if (cut >= 0) { suffix = v.slice(cut); v = v.slice(0, cut); }

    let abs;
    if (v.startsWith('/')) {
      // Root-relative so với site → /assets/{host}/ + v
      abs = path.join(ASSETS_ROOT, host, v.replace(/^\/+/, ''));
    } else {
      // relative to CSS directory
      abs = path.normalize(path.join(cssAbsDir, v));
      // guard: nếu thoát ra ngoài host thì ép về host root
      const hostRoot = path.join(ASSETS_ROOT, host);
      if (!abs.startsWith(hostRoot)) {
        abs = path.join(hostRoot, v.replace(/^\/+/, ''));
      }
    }
    const relUrl = path.relative(ASSETS_ROOT, abs).split(path.sep).join('/'); // e.g. yenai.vn/wp-content/themes/...
    const parts2 = relUrl.split('/');
    const domainHost = parts2.shift();
    let cleanPath = parts2.join('/');

    // Ảo hóa đường dẫn trong CSS
    if (cleanPath.startsWith('wp-content/themes/')) cleanPath = cleanPath.slice(11);
    else if (cleanPath.startsWith('wp-content/plugins/')) cleanPath = cleanPath.slice(11);
    else if (cleanPath.startsWith('wp-content/uploads/')) cleanPath = 'media/' + cleanPath.slice(19);
    else if (cleanPath.startsWith('wp-includes/')) cleanPath = 'includes/' + cleanPath.slice(12);

    return `url(/${domainHost}/${cleanPath.split('/').map(encodeURIComponent).join('/')}${suffix})`;
  });
}

async function minifyIfPossible(buf, targetAbsPath) {
  const ext = (path.extname(targetAbsPath) || '').toLowerCase();

  try {
    if (ext === '.css') {
      // Rewriter trước khi minify
      const text = buf.toString('utf8');
      const rewritten = rewriteCssRelativeUrlsToCdn(text, targetAbsPath);
      const out = csso.minify(rewritten, { restructure: true });
      return Buffer.from(out.css, 'utf8');
    }
    if (ext === '.js') {
      if (/\.min\.js$/i.test(targetAbsPath)) return buf;
      const text = buf.toString('utf8');
      const result = await Terser.minify(text, {
        compress: true, mangle: true, format: { comments: false }
      });
      if (result && result.code) return Buffer.from(result.code, 'utf8');
      return buf;
    }
  } catch (_) { return buf; }

  return buf;
}

// CORS cho toàn bộ file tĩnh CDN (kể cả font)
// đặt *trước* express.static('/assets', ...)
app.use('/assets', (req, res, next) => {
  // Nếu muốn chặt chẽ hơn, thay * bằng 'https://huyenthuyen.vn'
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.removeHeader('Access-Control-Allow-Credentials'); // font không cần credentials
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Range');
  res.setHeader('Access-Control-Expose-Headers', 'Accept-Ranges, Content-Encoding, Content-Range');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin'); // cho phép load font/img cross-origin
  res.setHeader('Timing-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// Static + MIME đúng cho font
app.use('/', express.static(ASSETS_ROOT, {
  setHeaders: (res, filePath) => {
    // cache dài cho file tĩnh
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');

    // MIME chuẩn cho font
    if (filePath.endsWith('.woff2')) res.setHeader('Content-Type', 'font/woff2');
    else if (filePath.endsWith('.woff')) res.setHeader('Content-Type', 'font/woff');
    else if (filePath.endsWith('.ttf')) res.setHeader('Content-Type', 'font/ttf');
    else if (filePath.endsWith('.eot')) res.setHeader('Content-Type', 'application/vnd.ms-fontobject');
    else if (filePath.endsWith('.svg')) res.setHeader('Content-Type', 'image/svg+xml');
  }
}));

// CATCH-ALL CHO RELATIVE ASSETS TRONG CSS (Ví dụ Font / Ảnh nền)
// Khi CSS (đã được Push) gọi url('font.woff'), trình duyệt sẽ nạp /assets/yenai.vn/...
// Nếu file chưa có trên đĩa, tĩnh express.static sẽ bỏ qua. Route này sẽ "bắt" và Pull về.
app.get(/^\/assets\/([^\/]+)\/(.+)$/, async (req, res, next) => {
  try {
    const host = req.params[0];
    const rel = req.params[1];
    const search = url.parse(req.originalUrl).search || '';

    // BẢO MẬT
    if (rel.includes('..') || rel.includes('\0')) return next();
    if (!ALLOWED_DOMAINS.includes(host.split(':')[0])) return next();
    if (!host.match(/^[a-zA-Z0-9.:-]+$/)) return next();
    if (host.includes('127.0.0.1') || host.includes('localhost') || host.startsWith('192.168.')) return next();

    const protocol = (host.includes('localhost') || host === '127.0.0.1') ? 'http' : 'https';
    const originUrl = `${protocol}://${host}/${rel}${search}`;
    const ext = path.extname(rel).toLowerCase();

    if (ext && !ALLOWED_EXTS.includes(ext)) {
      return res.redirect(302, originUrl);
    }

    const localAbs = path.join(ASSETS_ROOT, 'assets', host, rel);
    const buf = await downloadToBuffer(originUrl);
    ensureDirSync(path.dirname(localAbs));

    // LƯU Ý: Không minify font/image, ghi trực tiếp!
    fs.writeFileSync(localAbs, buf);

    const fileName = path.basename(localAbs);
    const immutable = /\.[0-9a-f]{8,}\./i.test(fileName);
    res.setHeader('Cache-Control', immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=86400');
    return res.sendFile(localAbs);
  } catch (e) {
    return next();
  }
});

// Pull-through: nếu file chưa có => tự tải từ origin, rewrite CSS url(), minify, lưu rồi trả
app.get(/^\/([^\/]+)\/(.+)$/, async (req, res, next) => {
  try {
    const host = req.params[0];
    if (['assets', 'public', 'upload', 'debug-log'].includes(host)) return next();

    let rel = req.params[1];
    const search = url.parse(req.originalUrl).search || '';

    // Phiên dịch ngược đường dẫn ảo về đường dẫn gốc
    let mappedRel = rel;
    if (mappedRel.startsWith('themes/')) mappedRel = 'wp-content/' + mappedRel;
    else if (mappedRel.startsWith('plugins/')) mappedRel = 'wp-content/' + mappedRel;
    else if (mappedRel.startsWith('media/')) mappedRel = 'wp-content/uploads/' + mappedRel.slice(6);
    else if (mappedRel.startsWith('includes/')) mappedRel = 'wp-includes/' + mappedRel.slice(9);

    // BẢO MẬT: Chống Path Traversal trên đường dẫn đã map
    if (mappedRel.includes('..') || mappedRel.includes('\0')) return next();

    const localAbs = path.join(ASSETS_ROOT, host, mappedRel);

    // 1) Nếu file đã tồn tại trên đĩa local (do đã Đồng bộ qua API Key hợp lệ) -> Serve luôn không cần quan tâm ALLOWED_DOMAINS
    if (fs.existsSync(localAbs) && fs.statSync(localAbs).isFile()) {
      try {
        const fileName = path.basename(localAbs);
        const immutable = /\.[0-9a-f]{8,}\./i.test(fileName);
        res.setHeader('Cache-Control', immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=86400');
        return res.sendFile(localAbs);
      } catch (e) {
        return next();
      }
    }

    // ==========================================
    // 2) Kéo từ origin (Pull-through proxy tự động)
    // ==========================================
    // BẢO MẬT: Chống Open Proxy (Chỉ cho phép pull tự động từ danh sách chỉ định)
    if (!ALLOWED_DOMAINS.includes(host.split(':')[0])) {
      return next(); // Bỏ qua nếu không phải domain hợp lệ
    }

    // BẢO MẬT: Chỉ cho phép HTTP/HTTPS, chặn local IP/localhost
    if (!host.match(/^[a-zA-Z0-9.:-]+$/)) return next();
    if (host.includes('127.0.0.1') || host.includes('localhost') || host.startsWith('192.168.')) return next();

    const protocol = (host.includes('localhost') || host === '127.0.0.1') ? 'http' : 'https';
    const originUrl = `${protocol}://${host}/${mappedRel}${search}`;

    // NẾU LÀ TỆP KHÔNG ĐƯỢC HỖ TRỢ (VÍ DỤ VIDEO MP4) -> CHUYỂN HƯỚNG VỀ NGUỒN GỐC ĐỂ KHÔNG BỊ LỖI WEB
    const ext = path.extname(mappedRel).toLowerCase();
    if (ext && !ALLOWED_EXTS.includes(ext)) {
      return res.redirect(302, originUrl);
    }
    const buf = await downloadToBuffer(originUrl);
    ensureDirSync(path.dirname(localAbs));
    const out = await minifyIfPossible(buf, localAbs);
    fs.writeFileSync(localAbs, out);

    const ctype = mime.lookup(localAbs) || 'application/octet-stream';
    res.setHeader('Content-Type', ctype);
    const fileName = path.basename(localAbs);
    const immutable = /\.[0-9a-f]{8,}\./i.test(fileName);
    res.setHeader('Cache-Control', immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=86400');
    return res.sendFile(localAbs);
  } catch (e) {
    console.error('[PULL ERROR]', e);
    return next(); // để static/404 xử lý
  }
});

// Static serve (có CORS + cache headers)
app.use('/', express.static(ASSETS_ROOT, {
  setHeaders: (res, filePath) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', '*');
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    res.setHeader('Timing-Allow-Origin', '*');

    const fileName = path.basename(filePath);
    const immutable = /\.[0-9a-f]{8,}\./i.test(fileName);
    res.setHeader('Cache-Control', immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=86400');
  }
}));

// ===== /public (serve uploaded files) =====
const UPLOADS_ROOT = path.join(__dirname, 'uploads');
ensureDirSync(UPLOADS_ROOT);

app.use('/public', (req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.removeHeader('Access-Control-Allow-Credentials');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.use('/public', express.static(UPLOADS_ROOT, {
  setHeaders: (res, filePath) => {
    res.setHeader('Cache-Control', 'public, max-age=86400');
    // MIME chuẩn cho ảnh
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.jpg' || ext === '.jpeg') res.setHeader('Content-Type', 'image/jpeg');
    else if (ext === '.png') res.setHeader('Content-Type', 'image/png');
    else if (ext === '.webp') res.setHeader('Content-Type', 'image/webp');
  }
}));

// ===== Uploads / API =====
app.use(helmet());

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (!fs.existsSync('uploads')) fs.mkdirSync('uploads');
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    const ts = Date.now(), ext = path.extname(file.originalname).toLowerCase();
    let name = `${ts}${ext}`, p = path.join('uploads', name), i = 0;
    while (fs.existsSync(p) && i < 100) { name = `${ts}-${i++}${ext}`; p = path.join('uploads', name); }
    cb(null, name);
  }
});

const fileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname).toLowerCase();
  if (!ALLOWED_EXTS.includes(ext)) {
    console.warn(`[SECURITY] Blocked unsupported multipart file extension: ${ext}`);
    return cb(new Error('Extension not allowed'), false);
  }
  cb(null, true);
};

const upload = multer({ storage, fileFilter });

app.post('/upload', upload.array('files'), async (req, res) => {
  // BẢO MẬT: Xác thực API Key
  const apiKey = req.headers['x-api-key'] || req.body?.api_key || req.query?.api_key;
  if (apiKey !== SECRET_API_KEY) {
    return res.status(403).send({ error: { message: 'Unauthorized: Invalid API Key' } });
  }

  try {
    // Nhánh cho plugin WP: { path, target } hoặc { target, file_base64 }
    const sourceUrl = (req.body && (req.body.path || req.body.source || req.body.url)) || null;
    const targetUrl = (req.body && (req.body.target || req.body.cdn)) || null;
    const fileBase64 = (req.body && req.body.file_base64) || null;

    if (targetUrl && (sourceUrl || fileBase64)) {
      const parsed = parseCdnTargetToLocalPath(targetUrl);
      if (!parsed) return res.status(200).send({ error: { message: 'Target URL không hợp lệ hoặc nằm trong đường dẫn cấm' } });

      let buf;
      if (fileBase64) {
        buf = Buffer.from(fileBase64, 'base64');
      } else {
        buf = await downloadToBuffer(sourceUrl);
      }

      ensureDirSync(path.dirname(parsed.abs));
      const out = await minifyIfPossible(buf, parsed.abs);
      fs.writeFileSync(parsed.abs, out);
      return res.status(200).send({ ok: true, url: targetUrl, path: `/${parsed.rel}` });
    }

    // Multipart files (giữ logic cũ)
    if (!req.files || req.files.length === 0) return res.status(200).send({ error: { message: 'No file uploaded' } });
    const files = req.files.map(f => ({
      url: `${req.headers.origin}/public/${f.filename}`,
      filename: f.filename
    }));
    return res.status(200).send(files.length === 1 ? files[0] : { files });
  } catch (err) {
    return res.status(500).send({ error: { message: `Multer uploading error: ${err.message}` } });
  }
});

// ===== Debug endpoint - ghi lại payload để debug =====
app.post('/debug-log', (req, res) => {
  const timestamp = new Date().toISOString();
  const body = req.body || {};

  // Truncate image base64 data để log không quá lớn
  const logData = JSON.parse(JSON.stringify(body));
  if (logData.payload?.parameters?.image_list) {
    logData.payload.parameters.image_list = logData.payload.parameters.image_list.map(img => ({
      ...img,
      image_url: img.image_url ? `${img.image_url.substring(0, 100)}... [${img.image_url.length} chars total]` : 'EMPTY'
    }));
  }

  const logEntry = `\n===== ${timestamp} =====\n${JSON.stringify(logData, null, 2)}\n`;

  // Ghi vào file
  const logFile = path.join(__dirname, 'debug.log');
  fs.appendFileSync(logFile, logEntry);

  // In ra console
  console.log(`\n🔍 DEBUG LOG:`);
  console.log(logEntry);

  res.json({ ok: true, logged: timestamp });
});

// (Các endpoint phụ khác của bạn…)

// ===== Listen on 0.0.0.0 để cloudflared vào được =====
app.listen(port, '0.0.0.0', () => {
  console.log(`CDN server listening on http://0.0.0.0:${port}`);
});
// === END server.js ===
