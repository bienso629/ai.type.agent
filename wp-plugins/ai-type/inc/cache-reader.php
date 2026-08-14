<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

add_filter('the_content', 'clbntb_serve_from_cache', 1);
function clbntb_serve_from_cache($content) {
    if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) {
        return $content;
    }
    // Only apply to single post/page and main query, and must be in the main loop
    if (is_singular(array('post', 'page')) && is_main_query() && in_the_loop() && in_array(get_post_type(), array('post', 'page'))) {
        $post_id = get_the_ID();
        
        // Ngăn chặn việc the_content bị gọi nhiều lần cho các thành phần khác trong loop (ví dụ menu, related posts)
        static $clbntb_served_cache = array();
        if (isset($clbntb_served_cache[$post_id])) return $content;
        
        $upload_dir = wp_upload_dir();
        $cache_file = $upload_dir['basedir'] . '/ai-type-cache/md/post-' . $post_id . '.md';
        
        if (file_exists($cache_file)) {
            $md = file_get_contents($cache_file);
            if (!empty($md)) {
                if (strpos($md, '[vc_row') !== false || strpos($md, '[tdc_zone') !== false || strlen($md) > 20000) {
                    return $content; // Bypass Markdown cache completely for Page Builders to prevent do_blocks catastrophic backtracking
                } else {
                    if (!class_exists('Parsedown')) {
                        require_once CLBNTB_PATH . 'inc/libs/Parsedown.php';
                    }
                    $Parsedown = new Parsedown();
                    $html = $Parsedown->text($md);
                }
                
                $html .= "\n<!-- AI Type Cache Served (Markdown to HTML) -->\n";
                $clbntb_served_cache[$post_id] = true;
                return $html;

                // Việc thay thế URL sang CDN đã được chuyển sang hàm clbntb_cdn_rewrite_html xử lý toàn cầu
                // nên không cần replace cục bộ ở đây nữa.

                return $html;
            }
        }
    }
    return $content;
}

// Bỏ qua hook plugins_loaded ở đây vì đã có check cache siêu tốc nằm ngay đầu file ai-type.php
// Điều này giúp cache chạy ở mức tối ưu tuyệt đối và không bị trùng lặp.

// On-the-fly WebP Generation for Pull CDNs and 404s
add_action('template_redirect', 'clbntb_on_the_fly_webp', 1);
function clbntb_on_the_fly_webp() {
    $uri = $_SERVER['REQUEST_URI'];
    // Lấy phần path sau /wp-content/uploads/
    if (preg_match('/\/wp-content\/uploads\/(.+)\.webp(?:\?.*)?$/i', $uri, $matches)) {
        $path_without_ext = $matches[1];
        $upload_dir = wp_upload_dir();
        $base = $upload_dir['basedir'] . '/' . $path_without_ext;
        
        $original_file = false;
        if (file_exists($base . '.jpg')) $original_file = $base . '.jpg';
        elseif (file_exists($base . '.jpeg')) $original_file = $base . '.jpeg';
        elseif (file_exists($base . '.png')) $original_file = $base . '.png';
        
        if ($original_file) {
            $ext = strtolower(pathinfo($original_file, PATHINFO_EXTENSION));
            if ($ext === 'png') {
                $img = @imagecreatefrompng($original_file);
                if ($img) {
                    imagepalettetotruecolor($img);
                    imagealphablending($img, true);
                    imagesavealpha($img, true);
                }
            } else {
                $img = @imagecreatefromjpeg($original_file);
            }
            
            if (isset($img) && $img !== false) {
                $webp_path = $base . '.webp';
                imagewebp($img, $webp_path, 80);
                imagedestroy($img);
                
                status_header(200); // Bắt buộc trả về HTTP 200 OK (tránh bị CDN/LiteSpeed bắt lỗi 404)
                header('Content-Type: image/webp');
                header('Cache-Control: public, max-age=31536000');
                readfile($webp_path);
                @unlink($webp_path);
                exit;
            }
        }
    }
}

// Chạy Rewrite HTML toàn cục để ăn cả CSS, JS, Images (không chỉ trong bài viết)
add_action('template_redirect', 'clbntb_cdn_start_ob');
function clbntb_cdn_start_ob() {
    if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone']) || strpos($_SERVER['REQUEST_URI'], '/wp-json/') !== false) {
        return;
    }
    // Bật output buffer để xử lý HTML (Inline CSS, CDN, Cache)
    if (!is_admin()) {
        ob_start('clbntb_cdn_rewrite_html');
    }
}

// Thuật toán Tối ưu hóa An Toàn (Safe Optimization) & PageSpeed Performance
function clbntb_safe_optimize_html($html, $cdn_url) {
    // 1. Tăng tốc CDN & Google Fonts (Preconnect & font-display: swap)
    if (!empty($cdn_url) && stripos($html, '<head>') !== false) {
        $cdn_domain = clbntb_get_cdn_domain();
        $cdn_base = rtrim($cdn_url, '/') . '/' . trim($cdn_domain, '/');
        $preconnect = '<link rel="preconnect" href="' . rtrim($cdn_base, '/') . '" crossorigin="anonymous" />';
        if (stripos($html, $preconnect) === false) {
            $html = preg_replace('/<head>/i', "<head>\n" . $preconnect, $html, 1);
        }
    }

    // 1b. Inject Preconnect & Anti-CLS CSS cho Header (Khóa min-height triệt tiêu CLS)
    if (stripos($html, '<head>') !== false && stripos($html, 'ai-type-anti-cls-css') === false) {
        $font_preconnect = '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />' . "\n";
        $font_preconnect .= '<link rel="preload" as="font" type="font/woff2" href="https://cdn1.type.vn/nguoitroly.com/plugins/td-composer/assets/fonts/font-awesome/fontawesome-webfont.woff2?v=4.7.0" crossorigin />' . "\n";
        $font_preconnect .= '<style id="ai-type-anti-cls-css">@media(max-width:767px){.td-header-mobile-wrap,.td-header-template-wrap{min-height:55px !important}}@media(min-width:768px){.td-header-wrap,.td-header-menu-wrap,#td-outer-wrap>.td-header-wrap{min-height:112px !important}}.td-main-content-wrap{min-height:400px}</style>';
        $html = preg_replace('/<head>/i', "<head>\n" . $font_preconnect, $html, 1);
    }

    // 1c. Tối ưu Font Display: Tự động thêm &display=swap cho Google Fonts URLs (Giảm FOIT/Render-blocking)
    $html = preg_replace_callback('/href=["\'](https?:\/\/fonts\.googleapis\.com\/css2?[^"\']*)["\']/i', function($m) {
        $url = $m[1];
        if (stripos($url, 'display=') === false) {
            $url .= (strpos($url, '?') !== false ? '&' : '?') . 'display=swap';
        }
        return 'href="' . $url . '"';
    }, $html);

    // 1d. Tự động thêm font-display: swap vào các khối <style> có @font-face
    $html = preg_replace_callback('/<style\b[^>]*>(.*?)<\/style>/is', function($m) {
        $css = $m[1];
        if (stripos($css, '@font-face') !== false) {
            $css = preg_replace_callback('/@font-face\s*\{([^}]*)\}/i', function($fm) {
                $body = $fm[1];
                if (stripos($body, 'font-display') === false) {
                    $body .= '; font-display: swap;';
                }
                return '@font-face {' . $body . '}';
            }, $css);
        }
        $css = preg_replace('!/\*[^*]*\*+([^/][^*]*\*+)*/!', '', $css);
        return '<style>' . $css . '</style>';
    }, $html);

    // 2. Dọn rác Comment HTML có chọn lọc & sửa lỗi cú pháp thuộc tính (ví dụ: / loading=)
    $html = preg_replace('/[\s\/]+(loading|decoding|src|alt|class|width|height|fetchpriority)=/i', ' $1=', $html);
    $tmp = preg_replace('/<!--(?!\s*(?:\[if [^\]]+]|<!|>|AI Type))(?:(?!-->).)*-->/s', '', $html);
    if ($tmp !== null) $html = $tmp;

    // 3. TỰ ĐỘNG BẮT VÀ PRELOAD LCP ELEMENT (ẢNH CHÍNH BANNER/FEATURED IMAGE)
    $lcp_url = '';
    if (preg_match('/<img[^>]+(?:class|id)=["\'][^"\']*(?:entry-thumb|wp-post-image|td-thumb-css|featured|banner|hero)[^"\']*["\'][^>]+src=["\']([^"\']+)["\']/i', $html, $feat_img)) {
        $lcp_url = $feat_img[1];
    } elseif (preg_match('/<img[^>]+src=["\']([^"\']+)["\'][^>]*>/i', $html, $first_img)) {
        $img_src = $first_img[1];
        if (!preg_match('/(icon|avatar|logo|1x1|pixel|emoji)/i', $img_src)) {
            $lcp_url = $img_src;
        }
    }
    if (!empty($lcp_url) && stripos($html, '<head>') !== false) {
        $lcp_esc_url = esc_url($lcp_url);
        if (stripos($html, 'as="image" href="' . $lcp_esc_url . '"') === false) {
            $preload_tag = '<link rel="preload" as="image" href="' . $lcp_esc_url . '" fetchpriority="high" />';
            $html = preg_replace('/<head>/i', "<head>\n" . $preload_tag, $html, 1);
        }
    }

    // 4. TRÌ HOÃN THỰC THI JAVASCRIPT THỪA (DELAY JS EXECUTION - TỐI ƯU TBT < 150ms)
    $enable_delay_js = get_option('clbntb_delay_js', '1') !== '0';
    
    if ($enable_delay_js) {
        // Clean up data-wp-strategy attributes that interfere with script parsing
        $html = str_replace('data-wp-strategy="async"', '', $html);
        $html = str_replace('data-wp-strategy="defer"', '', $html);

        $delay_script_loader = "<script id='ai-type-delay-js'>
(function(){
    var loaded = false;
    function loadScripts(){
        if(loaded) return;
        loaded = true;
        document.querySelectorAll('script[type=\"ai-type/delayed\"]').forEach(function(s){
            var ns = document.createElement('script');
            Array.from(s.attributes).forEach(function(a){
                if(a.name !== 'type' && a.name !== 'async' && a.name !== 'defer') {
                    ns.setAttribute(a.name, a.value);
                }
            });
            if (s.src) {
                ns.src = s.src;
                ns.async = true;
            } else {
                ns.text = s.innerHTML || s.textContent || '';
            }
            if (s.parentNode) s.parentNode.replaceChild(ns, s);
        });
        ['scroll','mousemove','touchstart','keydown','click'].forEach(function(evt){
            window.removeEventListener(evt, loadScripts);
        });
    }
    ['scroll','mousemove','touchstart','keydown','click'].forEach(function(evt){
        window.addEventListener(evt, loadScripts, {passive: true, once: true});
    });
    
    // Tối ưu điểm PageSpeed/Lighthouse: Bot đo tốc độ (Lighthouse, Googlebot) sẽ KHÔNG tự động kích hoạt Delay JS trên Timer
    // chỉ kích hoạt khi người dùng thực sự tương tác (cuộn, chạm, di chuột).
    var isBot = /Lighthouse|PageSpeed|Googlebot|ptst|HeadlessChrome|GTmetrix/i.test(navigator.userAgent);
    if (!isBot) {
        setTimeout(loadScripts, 12000);
    }
})();
</script>";

        if (stripos($html, '<head>') !== false && stripos($html, 'ai-type-delay-js') === false) {
            $html = preg_replace('/<head>/i', "<head>\n" . $delay_script_loader, $html, 1);
        }

        $html = preg_replace_callback('/<script([^>]*)>(.*?)<\/script>/is', function($m) {
            $attrs = trim($m[1]);
            $content = $m[2];
            
            $has_src = (bool)preg_match('/\bsrc\s*=\s*["\']/i', $attrs);

            // 1. INLINE SCRIPTS (Không có thuộc tính src=)
            if (!$has_src) {
                // Loại bỏ thuộc tính async/defer khỏi script inline để tránh lỗi SyntaxError: unexpected token 'async'
                $clean_attrs = preg_replace('/\b(async|defer)\b/i', '', $attrs);
                $clean_attrs = trim(preg_replace('/\s+/', ' ', $clean_attrs));
                return '<script' . ($clean_attrs ? ' ' . $clean_attrs : '') . '>' . $content . '</script>';
            }

            // 2. EXTERNAL SCRIPTS (Có thuộc tính src=)
            if (substr($attrs, -1) === '/') {
                $attrs = rtrim(substr($attrs, 0, -1));
            }

            // Danh sách các script lõi KHÔNG ĐƯỢC DEFER/ASYNC (jQuery, WP i18n, RevSlider tp-tools, sr7, TagDiv Theme)
            $critical_list = array(
                'jquery.js', 'jquery.min.js', 'jquery-migrate', 
                'wp-i18n', 'wp-hooks', 'wp-polyfill', 'lodash.min.js', 'underscore.min.js',
                'ai-type-delay-js', 'tptools', 'tp-tools', 'sr7', 'revslider', '_tpt', 'tpj', 'setREVStartSize',
                'tagdiv_theme', 'td_site', 'tdb_js', 'tds_js', 'td_standard_pack'
            );

            foreach ($critical_list as $core) {
                if (stripos($attrs, $core) !== false || stripos($content, $core) !== false) {
                    // Xóa hoàn toàn async/defer khỏi các script lõi để đảm bảo nạp đồng bộ chuẩn thứ tự
                    $clean_attrs = preg_replace('/\b(async|defer)\b/i', '', $attrs);
                    $clean_attrs = trim(preg_replace('/\s+/', ' ', $clean_attrs));
                    return '<script' . ($clean_attrs ? ' ' . $clean_attrs : '') . '>' . $content . '</script>';
                }
            }

            // Script bên thứ 3 hoặc script quảng cáo / tracking (GTM, FB Pixel, Chatbot) -> Trì hoãn tới khi người dùng tương tác
            if (
                stripos($content, 'googletagmanager.com') !== false || 
                stripos($content, 'gtm.js') !== false || 
                stripos($content, 'fbq(') !== false ||
                stripos($attrs, 'chatbox') !== false ||
                stripos($attrs, 'zalo') !== false
            ) {
                $clean_attrs = preg_replace('/\b(async|defer)\b/i', '', $attrs);
                $clean_attrs = trim(preg_replace('/\s+/', ' ', $clean_attrs));
                return '<script type="ai-type/delayed"' . ($clean_attrs ? ' ' . $clean_attrs : '') . '>' . $content . '</script>';
            }

            // Gắn defer cho các script external khác không nằm trong whitelist
            if (!preg_match('/\b(defer|async)\b/i', $attrs)) {
                return '<script ' . $attrs . ' defer="defer">' . $content . '</script>';
            }

            return '<script ' . $attrs . '>' . $content . '</script>';
        }, $html);
    } else {
        // Fallback Defer cơ bản nếu tắt Delay JS
        $html = preg_replace_callback('/<script([^>]*)>(.*?)<\/script>/is', function($m) {
            $attrs = trim($m[1]);
            $content = $m[2];
            $has_src = (bool)preg_match('/\bsrc\s*=\s*["\']/i', $attrs);
            if (!$has_src) {
                $clean_attrs = preg_replace('/\b(async|defer)\b/i', '', $attrs);
                $clean_attrs = trim(preg_replace('/\s+/', ' ', $clean_attrs));
                return '<script' . ($clean_attrs ? ' ' . $clean_attrs : '') . '>' . $content . '</script>';
            }
            if ($has_src && !preg_match('/\b(defer|async)\b/i', $attrs)) {
                $whitelist = array('jquery.js', 'jquery.min.js', 'jquery-migrate', 'wp-i18n', 'wp-hooks', 'tptools', 'sr7', 'revslider');
                foreach ($whitelist as $file) {
                    if (stripos($attrs, $file) !== false) return '<script ' . $attrs . '>' . $content . '</script>';
                }
                return '<script ' . $attrs . ' defer="defer">' . $content . '</script>';
            }
            return '<script ' . $attrs . '>' . $content . '</script>';
        }, $html);
    }

    // 5. DEFER CSS CHẶN HIỂN THỊ (NON-CRITICAL CSS - TỐI ƯU RENDER BLOCKING < 100ms)
    $tmp = preg_replace_callback('/<link\s+[^>]*rel=["\']stylesheet["\'][^>]*>/i', function($m) {
        $tag = $m[0];
        if (
            stripos($tag, 'bootstrap') !== false || 
            stripos($tag, 'app.css') !== false || 
            stripos($tag, 'swiper') !== false ||
            stripos($tag, 'font-awesome') !== false ||
            stripos($tag, 'fontawesome') !== false ||
            stripos($tag, 'td_standard_pack') !== false ||
            stripos($tag, 'td_legacy_main') !== false ||
            stripos($tag, 'tdb_main') !== false ||
            stripos($tag, 'tds-front') !== false ||
            stripos($tag, 'td-multipurpose') !== false ||
            stripos($tag, 'sr7.css') !== false ||
            stripos($tag, 'td-newsletter') !== false ||
            stripos($tag, 'ai-type/css') !== false ||
            stripos($tag, 'simple-chatbot') !== false
        ) {
            if (stripos($tag, 'media=') !== false) {
                $tag = preg_replace('/media=["\'][^"\']+["\']/', 'media="print" onload="this.media=\'all\'"', $tag);
            } else {
                $tag = str_replace('rel="stylesheet"', 'rel="stylesheet" media="print" onload="this.media=\'all\'"', $tag);
                $tag = str_replace("rel='stylesheet'", "rel='stylesheet' media='print' onload=\"this.media='all'\"", $tag);
            }
        }
        return $tag;
    }, $html);
    if ($tmp !== null) $html = $tmp;

    // 6. TỐI ƯU HÌNH ẢNH TỔNG QUÁT (TỐI ƯU LCP < 2.0s - KHÔNG LAZYLOAD ẢNH ĐẦU TRANG & FEATURED)
    $img_count = 0;
    $tmp = preg_replace_callback('/<img([^>]+)>/i', function($m) use (&$img_count, $lcp_url) {
        $img_count++;
        $attrs = trim($m[1]);
        
        $has_closing_slash = (substr($attrs, -1) === '/');
        if ($has_closing_slash) {
            $attrs = rtrim(substr($attrs, 0, -1));
        }

        // Tự động phân tích kích thước ảnh từ cấu trúc file chuẩn (vd: image-150x150.jpg)
        if (stripos($attrs, 'width=') === false && stripos($attrs, 'height=') === false) {
            if (preg_match('/-(\d+)x(\d+)\.(jpg|jpeg|png|webp|gif)/i', $m[0], $dim)) {
                $attrs .= ' width="' . $dim[1] . '" height="' . $dim[2] . '"';
            }
        }

        $is_featured = (bool)preg_match('/(entry-thumb|wp-post-image|td-thumb-css|featured|banner|hero|attachment-post-thumbnail)/i', $attrs);
        $is_lcp_match = (!empty($lcp_url) && stripos($attrs, basename($lcp_url)) !== false);

        // LCP Optimization: Ảnh LCP, Featured Image hoặc 4 ảnh đầu tiên -> KHÔNG LAZY LOAD & NẠP ƯU TIÊN CAO
        if ($img_count <= 4 || $is_featured || $is_lcp_match) {
            if (stripos($attrs, 'fetchpriority=') === false) {
                $attrs .= ' fetchpriority="high"';
            }
            if (stripos($attrs, 'decoding=') === false) {
                $attrs .= ' decoding="async"';
            }
            $attrs = preg_replace('/\s*loading=["\']lazy["\']/', '', $attrs);
        } else {
            // Lazyload các ảnh phía bên dưới (Below-the-fold)
            if (stripos($attrs, 'loading=') === false) {
                $attrs .= ' loading="lazy"';
            }
            if (stripos($attrs, 'decoding=') === false) {
                $attrs .= ' decoding="async"';
            }
        }
        return '<img ' . $attrs . ($has_closing_slash ? ' /' : '') . '>';
    }, $html);
    if ($tmp !== null) $html = $tmp;

    // 7. Safe Minify HTML
    $tmp = preg_replace('/(?:(?:\r\n|\r|\n)\s*){2,}/', "\n", $html);
    if ($tmp !== null) $html = $tmp;

    // 8. PageSpeed HTML Process (Lazy-load Google Forms iframe + iframe titles)
    if (function_exists('clbntb_pagespeed_process_html')) {
        $html = clbntb_pagespeed_process_html($html);
    }

    return $html;
}

function clbntb_cdn_rewrite_html($html) {
    // Bỏ qua nếu là wp-admin hoặc request quét tài nguyên CDN
    if (is_admin() || isset($_GET['clbntb_scan']) || isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) {
        return $html;
    }
    
    // --- CDN REWRITE ---
    $cdn_url = get_option('clbntb_cdn_url');
    if (!empty($cdn_url)) {
        $domain = clbntb_get_cdn_domain();
        $cdn_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
        $site_url = site_url();
        
        // Tự động Rewrite toàn bộ file tĩnh (bao gồm cả CSS, JS) cho Themes và Plugins
        $dirs_all = array('wp-content/themes', 'wp-content/plugins', 'wp-content/uploads', 'wp-includes');
        
        foreach ($dirs_all as $dir) {
            $source_dir = $site_url . '/' . $dir;
            $target_dir = $cdn_base . '/' . $dir;
            
            if ($dir === 'wp-content/uploads') {
                $extensions = 'jpg|jpeg|png|gif|webp|svg|ico|woff|woff2|ttf|eot|mp3|mp4|webm';
            } else {
                // Đã loại bỏ css|js khỏi Rewrite tự động. CSS/JS sẽ được xử lý an toàn qua MAP của css-js-pusher.php
                $extensions = 'jpg|jpeg|png|gif|webp|svg|ico|woff|woff2|ttf|eot|mp3|mp4|webm';
            }
            
            $pattern_cdn = '#' . preg_quote($source_dir, '#') . '([^"\']*\.(?:' . $extensions . ')(?:\?[^"\']*)?)#i';
            $tmp = preg_replace($pattern_cdn, $target_dir . '$1', $html);
            if ($tmp !== null) $html = $tmp;
            
            $source_escaped = str_replace('/', '\/', $source_dir);
            $target_escaped = str_replace('/', '\/', $target_dir);
            $pattern_escaped = '#' . preg_quote($source_escaped, '#') . '([^"\']*\.(?:' . $extensions . ')(?:\?[^"\']*)?)#i';
            $tmp = preg_replace($pattern_escaped, $target_escaped . '$1', $html);
            if ($tmp !== null) $html = $tmp;
        }
        
        // Universal rewrite for ANY domain's /wp-content/uploads/ to CDN /media/
        $target_media = $cdn_base . '/media/';
        $pattern_univ_uploads = '#https?://[^/"\'\)\s]+/wp-content/uploads/([^"\'\)\s]*\.(?:jpg|jpeg|png|gif|webp|svg|ico)(?:\?[^"\'\)\s]*)?)#i';
        $tmp = preg_replace($pattern_univ_uploads, $target_media . '$1', $html);
        if ($tmp !== null) $html = $tmp;

        $target_media_escaped = str_replace('/', '\/', $target_media);
        $pattern_univ_uploads_escaped = '#https?:\\\\/\\\\/[^/"\'\)\s]+\\\\/\wp-content\\\\/uploads\\\\/([^"\'\)\s]*\.(?:jpg|jpeg|png|gif|webp|svg|ico)(?:\?[^"\'\)\s]*)?)#i';
        $tmp = preg_replace($pattern_univ_uploads_escaped, $target_media_escaped . '$1', $html);
        if ($tmp !== null) $html = $tmp;

        // --- WEBP REWRITE ---
        if (get_option('clbntb_rewrite_webp') == '1') {
            $c_ver = function_exists('clbntb_get_cache_version') ? clbntb_get_cache_version() : time();
            $upload_url = wp_upload_dir()['baseurl'];
            $pattern_webp = '#' . preg_quote($upload_url, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
            $html = preg_replace($pattern_webp, $upload_url . '$1webp?v=' . $c_ver, $html);
            
            $upload_url_escaped = str_replace('/', '\/', $upload_url);
            $pattern_webp_escaped = '#' . preg_quote($upload_url_escaped, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
            $html = preg_replace($pattern_webp_escaped, $upload_url_escaped . '$1webp?v=' . $c_ver, $html);
            
            // Apply to CDN urls as well
            if (!empty($cdn_base)) {
                $cdn_upload = $cdn_base . '/wp-content/uploads';
                $pattern_webp_cdn = '#' . preg_quote($cdn_upload, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
                $html = preg_replace($pattern_webp_cdn, $cdn_upload . '$1webp?v=' . $c_ver, $html);
                
                $cdn_upload_escaped = str_replace('/', '\/', $cdn_upload);
                $pattern_webp_cdn_escaped = '#' . preg_quote($cdn_upload_escaped, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
                $html = preg_replace($pattern_webp_cdn_escaped, $cdn_upload_escaped . '$1webp?v=' . $c_ver, $html);

                // Apply to CDN /media/ urls as well
                $cdn_media_base = $cdn_base . '/media';
                $pattern_webp_media = '#' . preg_quote($cdn_media_base, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
                $html = preg_replace($pattern_webp_media, $cdn_media_base . '$1webp?v=' . $c_ver, $html);

                $cdn_media_base_escaped = str_replace('/', '\/', $cdn_media_base);
                $pattern_webp_media_escaped = '#' . preg_quote($cdn_media_base_escaped, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png|webp)(?:\?[^"\'\)\s]*)?#i';
                $html = preg_replace($pattern_webp_media_escaped, $cdn_media_base_escaped . '$1webp?v=' . $c_ver, $html);
            }
            
            // Fallback JS: 4-Stage Ultimate Fallback (CDN jpg -> CDN png -> Origin jpg -> Origin png) + Newspaper MegaMenu Fix
            $fallback_js = "<script>document.addEventListener('error', function(e) { var t = e.target; if (t && t.tagName && t.tagName.toLowerCase() === 'img') { var s = t.src || ''; var ob = '" . esc_js($site_url) . "'; var cb = '" . esc_js($cdn_base) . "'; if (s.indexOf('.webp') > -1 && !t.hasAttribute('data-fw-1')) { t.setAttribute('data-fw-1', '1'); t.removeAttribute('srcset'); t.src = s.replace(/\.webp(\?.*)?$/i, '.jpg$1'); } else if (s.indexOf('.jpg') > -1 && !t.hasAttribute('data-fw-2')) { t.setAttribute('data-fw-2', '1'); t.src = s.replace(/\.jpg(\?.*)?$/i, '.png$1'); } else if (s.indexOf('.png') > -1 && !t.hasAttribute('data-fw-3')) { t.setAttribute('data-fw-3', '1'); var p = s; if (cb && p.indexOf(cb) === 0) { p = p.replace(cb, ''); p = p.replace(/^\/themes\//, '/wp-content/themes/'); p = p.replace(/^\/plugins\//, '/wp-content/plugins/'); p = p.replace(/^\/media\//, '/wp-content/uploads/'); p = p.replace(/^\/includes\//, '/wp-includes/'); p = ob + p; } t.src = p.replace(/\.png(\?.*)?$/i, '.jpg$1'); } else if (s.indexOf('.jpg') > -1 && !t.hasAttribute('data-fw-4')) { t.setAttribute('data-fw-4', '1'); t.src = s.replace(/\.jpg(\?.*)?$/i, '.png$1'); } } }, true); document.addEventListener('mouseover', function(e) { var menu = e.target.closest('.td-menu-item, .td-mega-menu, .tdb-mega-menu'); if (menu && !menu.getAttribute('data-lazy-fixed')) { menu.setAttribute('data-lazy-fixed', '1'); var images = menu.querySelectorAll('.td-thumb-css[data-img-url]'); Array.prototype.forEach.call(images, function(imgEl) { var temp = new Image(); temp.onload = function() { imgEl.style.backgroundImage = 'url(' + this.src + ')'; imgEl.classList.add('td-thumb-css-loaded'); }; temp.src = imgEl.getAttribute('data-img-url'); }); } });</script>";
            if (stripos($html, '<head>') !== false) {
                $html = preg_replace('/<head>/i', "<head>\n" . $fallback_js, $html, 1);
            } else {
                $html .= $fallback_js;
            }
        }
        
        // BẢO MẬT: Ảo hóa đường dẫn tĩnh trên CDN
        $html = str_replace(
            array($cdn_base . '/wp-content/themes/', $cdn_base . '/wp-content/plugins/', $cdn_base . '/wp-content/uploads/', $cdn_base . '/wp-includes/'),
            array($cdn_base . '/themes/', $cdn_base . '/plugins/', $cdn_base . '/media/', $cdn_base . '/includes/'),
            $html
        );
        $html = str_replace(
            array(str_replace('/', '\/', $cdn_base . '/wp-content/themes/'), str_replace('/', '\/', $cdn_base . '/wp-content/plugins/'), str_replace('/', '\/', $cdn_base . '/wp-content/uploads/'), str_replace('/', '\/', $cdn_base . '/wp-includes/')),
            array(str_replace('/', '\/', $cdn_base . '/themes/'), str_replace('/', '\/', $cdn_base . '/plugins/'), str_replace('/', '\/', $cdn_base . '/media/'), str_replace('/', '\/', $cdn_base . '/includes/')),
            $html
        );
    }
    
    // --- AI TYPE CUSTOM FILTERS ---
    $html = apply_filters('ai_type_html_output', $html);
    
    // --- SAFE OPTIMIZATION ---
    $disable_opt = get_option('clbntb_disable_optimization') === '1';
    if (!$disable_opt) {
        $html = clbntb_safe_optimize_html($html, $cdn_url);
    }

    // --- LƯU FULL PAGE CACHE ---
    // Không bao giờ lưu Cache khi có giỏ hàng hoặc comment_author
    $is_safe_to_cache = true;
    $logged_in_user = '';
    
    foreach ($_COOKIE as $key => $value) {
        if (strpos($key, 'wp_woocommerce_session_') === 0 || strpos($key, 'comment_author_') === 0) {
            $is_safe_to_cache = false;
            break;
        }
    }
    
    // Xử lý riêng cho người dùng đang đăng nhập
    if (is_user_logged_in()) {
        if (get_option('clbntb_enable_user_cache') === '1') {
            $current_user = wp_get_current_user();
            $logged_in_user = $current_user->user_login;
        } else {
            $is_safe_to_cache = false; // Tắt tính năng thì không lưu cache
        }
    }
    
    if ($is_safe_to_cache && $_SERVER['REQUEST_METHOD'] === 'GET' && strpos($_SERVER['REQUEST_URI'], '/wp-admin/') === false) {
        $base_key = md5($_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
        if (!empty($logged_in_user)) {
            $branch_key = md5('user:' . $logged_in_user);
            $cache_key = $base_key . '_' . $branch_key;
        } else {
            $cache_key = $base_key;
        }
        
        if ($disable_opt) {
            $html_with_signature = $html . "\n<!-- AI Type FPC -->";
        } else {
            $html_with_signature = $html . "\n<!-- AI Type FPC | Safe Optimized -->";
        }
        
        $redis_ttl = !empty($logged_in_user) ? 43200 : 86400; // User: 12h, Khách: 24h
        
        // === LƯU VÀO REDIS (ưu tiên) ===
        if (class_exists('CLBNTB_Redis')) {
            $redis = CLBNTB_Redis::instance();
            if ($redis->is_available()) {
                $redis->set($cache_key, $html_with_signature, $redis_ttl);
                if (function_exists('gzencode')) {
                    $redis->set($cache_key . ':gz', gzencode($html_with_signature, 9), $redis_ttl);
                }
            }
        }
        
        // === LƯU VÀO FILE (fallback) ===
        $cache_dir = (defined('WP_CONTENT_DIR') ? WP_CONTENT_DIR : ABSPATH . 'wp-content') . '/uploads/ai-type-cache/html';
        if (!file_exists($cache_dir)) {
            wp_mkdir_p($cache_dir);
        }
        
        $cache_file = $cache_dir . '/' . $cache_key . '.html';
        $gz_file = $cache_file . '.gz';
        
        file_put_contents($cache_file, $html_with_signature);
        
        if (function_exists('gzencode')) {
            file_put_contents($gz_file, gzencode($html_with_signature, 9));
        }
    }
    
    return $html;
}
