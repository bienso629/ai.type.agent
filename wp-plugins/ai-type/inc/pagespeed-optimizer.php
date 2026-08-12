<?php
/**
 * PageSpeed Optimizer Module
 * 
 * Fix các vấn đề PageSpeed Insights cho nguoitroly.com:
 * 1. Render-blocking JS (800ms wasted) → defer scripts
 * 2. Render-blocking CSS → non-blocking load
 * 3. Google Forms iframe nặng (1,700ms CPU) → lazy-load
 * 4. Font display (150ms FCP) → swap + preconnect
 * 5. iframe thiếu title → auto-add (Accessibility)
 * 6. Unused CSS/JS → remove khi không cần
 * 7. Preconnect third-party domains
 */

if (!defined('ABSPATH')) exit;

class CLBNTB_PageSpeed_Optimizer {

    private static $instance = null;

    public static function instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        if (is_admin()) return;

        // Defer render-blocking JS
        add_filter('script_loader_tag', [$this, 'defer_render_blocking_js'], 10, 3);

        // Non-blocking CSS
        add_filter('style_loader_tag', [$this, 'optimize_css_loading'], 10, 4);

        // Preconnect + preload
        add_action('wp_head', [$this, 'add_preconnect_hints'], 1);

        // Remove unused assets
        add_action('wp_enqueue_scripts', [$this, 'remove_unused_assets'], 9999);
    }

    /**
     * FIX 1: Defer render-blocking JavaScript
     * 
     * Các file đang block render (từ Lighthouse):
     *   sr7.js (RevSlider)     → 522ms wasted
     *   tptools.js (RevSlider) → 482ms wasted
     *   td_standard_pack       → 402ms wasted (CSS nhưng JS cũng có)
     *   jquery.min.js          → 322ms wasted
     *   jquery-migrate         → 162ms wasted
     */
    public function defer_render_blocking_js($tag, $handle, $src) {
        // Đã có defer/async thì bỏ qua
        if (strpos($tag, 'defer') !== false || strpos($tag, 'async') !== false) {
            return $tag;
        }

        // jQuery core & migrate không defer được (nhiều script inline phụ thuộc)
        $no_defer = ['jquery-core', 'jquery', 'jquery-migrate'];
        if (in_array($handle, $no_defer)) {
            return $tag;
        }

        // Các handle cần defer
        $defer_handles = [
            'tp-tools',             // RevSlider tptools - 482ms
            'revmin',               // RevSlider sr7 - 522ms
            'rs-sr7',               // RevSlider alt handle
            'rs-rbtools',           // RevSlider tools
            'td-site-min',          // tagdiv theme
            'tdb-js',               // td cloud library
            'tds_js',               // td subscription
            'td_standard_pack-js',  // td standard pack
            'wpcf7-recaptcha',      // CF7 recaptcha
        ];

        // Defer nếu handle match hoặc URL chứa keyword
        $should_defer = in_array($handle, $defer_handles)
            || strpos($src, 'revslider') !== false
            || strpos($src, 'td-composer') !== false
            || strpos($src, 'td-standard-pack') !== false
            || strpos($src, 'td-cloud-library') !== false
            || strpos($src, 'contact-form-7') !== false
            || strpos($src, 'td-subscription') !== false;

        if ($should_defer) {
            $tag = str_replace(' src=', ' defer src=', $tag);
        }

        // Google Analytics → async
        if (strpos($src, 'googletagmanager.com/gtag') !== false 
            || strpos($src, 'google-analytics.com') !== false) {
            $tag = str_replace(' src=', ' async src=', $tag);
        }

        return $tag;
    }

    /**
     * FIX 2 + 4: Optimize CSS loading & font-display
     * 
     * Render-blocking CSS (từ Lighthouse):
     *   td_legacy_main.css       → 402ms
     *   td_standard_pack_main    → 402ms
     *   style.css (theme)        → 402ms
     *   tds-front.css            → 282ms
     *   ai-type CSS              → 202ms
     *   revslider CSS            → 202ms
     *   contact-form-7 CSS       → 202ms
     *   td-multipurpose CSS      → 202ms + 242ms
     *   td-cloud CSS             → 162ms
     * 
     * Font display:
     *   Roboto Bold              → 150ms wasted
     *   Roboto Regular           → 20ms
     *   multipurpose.woff        → 15ms
     *   Montserrat               → 15ms
     *   Merriweather             → 15ms
     */
    public function optimize_css_loading($tag, $handle, $href, $media) {
        // Non-critical CSS: chuyển sang media=print, onload đổi lại all
        $defer_css = [
            'tds-front-css',            // td-subscription - 282ms
            'contact-form-7',           // CF7 - 202ms
            'rs-plugin-settings',       // RevSlider CSS - 202ms
            'td-multipurpose-font-css', // multipurpose font - 202ms
        ];

        if (in_array($handle, $defer_css)) {
            $tag = str_replace(
                ["media='all'", 'media="all"'],
                ["media='print' onload=\"this.media='all'\"", 'media="print" onload="this.media=\'all\'"'],
                $tag
            );
            // Fallback noscript
            $noscript = '<noscript>' . str_replace(
                ["media='print' onload=\"this.media='all'\"", 'media="print" onload="this.media=\'all\'"'],
                ["media='all'", 'media="all"'],
                $tag
            ) . '</noscript>';
            $tag .= $noscript;
        }

        // Google Fonts: thêm display=swap
        if (strpos($href, 'fonts.googleapis.com') !== false && strpos($href, 'display=') === false) {
            $new_href = $href . (strpos($href, '?') !== false ? '&' : '?') . 'display=swap';
            $tag = str_replace($href, $new_href, $tag);
        }

        return $tag;
    }

    /**
     * FIX 7: Preconnect hints cho third-party domains
     */
    public function add_preconnect_hints() {
        echo '<link rel="preconnect" href="https://fonts.googleapis.com">' . "\n";
        echo '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' . "\n";
        echo '<link rel="dns-prefetch" href="//www.googletagmanager.com">' . "\n";
        echo '<link rel="dns-prefetch" href="//docs.google.com">' . "\n";
        echo '<link rel="preload" as="font" type="font/woff2" href="https://cdn1.type.vn/nguoitroly.com/plugins/td-composer/assets/fonts/font-awesome/fontawesome-webfont.woff2?v=4.7.0" crossorigin>' . "\n";
        echo '<style id="ai-type-anti-cls-css">@media(max-width:767px){.td-header-mobile-wrap,.td-header-template-wrap{min-height:55px !important}}@media(min-width:768px){.td-header-wrap,.td-header-menu-wrap,#td-outer-wrap>.td-header-wrap{min-height:112px !important}}.td-main-content-wrap{min-height:400px}</style>' . "\n";
    }

    /**
     * FIX 6: Remove unused CSS/JS khi không cần thiết
     * 
     * Unused CSS (từ Lighthouse):
     *   td_standard_pack_main → 50KB unused
     *   td_legacy_main        → 22KB unused
     *   style.css             → 18KB unused
     */
    public function remove_unused_assets() {
        global $post;

        // Contact Form 7: chỉ load khi trang có shortcode
        if ($post && !has_shortcode($post->post_content, 'contact-form-7')
            && !has_shortcode($post->post_content, 'contact-form')) {
            wp_dequeue_style('contact-form-7');
            wp_dequeue_script('contact-form-7');
            wp_dequeue_script('wpcf7-recaptcha');
        }
    }
}

CLBNTB_PageSpeed_Optimizer::instance();


/**
 * FIX 3 + 5: Xử lý HTML output (Google Forms lazy-load + iframe title)
 * 
 * Dùng output buffer để modify HTML trước khi gửi cho browser.
 * Chạy trong cache-builder nếu có, hoặc standalone.
 * 
 * Google Forms iframe:
 *   - freebird/viewer_base JS chiếm 1,700ms+ CPU (thủ phạm #1)
 *   - Gây third-party cookies issues (5 cookies)
 *   → Lazy-load bằng IntersectionObserver
 * 
 * iframe thiếu title:
 *   - 2 Google Forms iframe thiếu title attribute
 *   → Auto-add title cho accessibility
 */
function clbntb_pagespeed_process_html($html) {
    if (empty($html) || is_admin()) return $html;

    // Tránh chạy 2 lần
    if (strpos($html, 'clbntb-pagespeed-processed') !== false) return $html;

    // --- Inject Polyfill sửa lỗi Newspaper Theme & jQuery 3+ .load(fn) crash ---
    $viewport_polyfill = <<<'JS'
<script id="ai-type-viewport-fix">
(function(){
    function patchJQueryLoad(jq) {
        if (jq && jq.fn && jq.fn.load && !jq.fn.load.__aitype) {
            var _origLoad = jq.fn.load;
            jq.fn.load = function(url, params, callback) {
                if (typeof url === 'function') {
                    return this.on('load', url);
                }
                return _origLoad.apply(this, arguments);
            };
            jq.fn.load.__aitype = true;
        }
    }
    if (window.jQuery) {
        patchJQueryLoad(window.jQuery);
    } else {
        var _jq = window.jQuery;
        try {
            Object.defineProperty(window, 'jQuery', {
                configurable: true,
                enumerable: true,
                get: function() { return _jq; },
                set: function(val) {
                    _jq = val;
                    if (_jq) patchJQueryLoad(_jq);
                }
            });
        } catch(e) {}
    }

    var _orig = window.isElementInViewport;
    window.isElementInViewport = function(el) {
        if (!el || typeof el.getBoundingClientRect !== 'function') return false;
        var rect = el.getBoundingClientRect();
        return (rect.bottom >= 0 && rect.top <= (window.innerHeight || document.documentElement.clientHeight));
    };
})();
</script>
JS;
    if (stripos($html, '<head>') !== false) {
        $html = preg_replace('/<head>/i', "<head>\n" . $viewport_polyfill, $html, 1);
    }

    // --- Lazy-load Google Forms iframes ---
    $html = preg_replace_callback(
        '/<iframe([^>]*?)src=["\']([^"\']*(?:docs\.google\.com\/forms|forms\.gle)[^"\']*)["\']([^>]*?)>/is',
        function($matches) {
            if (strpos($matches[0], 'clbntb-lazy-iframe') !== false) {
                return $matches[0];
            }

            $before = $matches[1];
            $src = $matches[2];
            $after = $matches[3];

            // Thêm title nếu chưa có
            if (stripos($before . $after, 'title=') === false) {
                $after .= ' title="Form đăng ký"';
            }

            return '<iframe' . $before . 'src="about:blank" data-src="' . esc_url($src) . '"' . $after . ' class="clbntb-lazy-iframe" loading="lazy">';
        },
        $html
    );

    // --- Add title cho các iframe khác thiếu title ---
    $html = preg_replace_callback(
        '/<iframe([^>]*?)>/i',
        function($matches) {
            $attrs = $matches[1];
            if (stripos($attrs, 'title=') !== false) return $matches[0];

            $title = 'Nội dung nhúng';
            if (stripos($attrs, 'youtube.com') !== false || stripos($attrs, 'youtu.be') !== false) {
                $title = 'Video YouTube';
            } elseif (stripos($attrs, 'google.com/maps') !== false) {
                $title = 'Bản đồ Google Maps';
            } elseif (stripos($attrs, 'facebook.com') !== false) {
                $title = 'Nội dung Facebook';
            }

            return '<iframe' . $attrs . ' title="' . esc_attr($title) . '">';
        },
        $html
    );

    // --- Bổ sung width / height tự động cho tất cả img và iframe thiếu kích thước ---
    $html = clbntb_add_missing_image_dimensions($html);

    // --- Inject lazy-load script trước </body> ---
    $lazy_script = <<<'JS'
<script id="ai-type-lazy-iframe-js">
(function(){
    var iframes = document.querySelectorAll('.clbntb-lazy-iframe');
    if (!iframes.length) return;
    if ('IntersectionObserver' in window) {
        var obs = new IntersectionObserver(function(entries) {
            entries.forEach(function(e) {
                if (e.isIntersecting) {
                    var el = e.target;
                    var src = el.getAttribute('data-src');
                    if (src && src !== 'about:blank') { 
                        el.src = src; 
                        el.removeAttribute('data-src'); 
                        el.classList.remove('clbntb-lazy-iframe'); 
                    }
                    obs.unobserve(el);
                }
            });
        }, { rootMargin: '400px 0px' });
        iframes.forEach(function(f) { obs.observe(f); });
    } else {
        iframes.forEach(function(f) { 
            var src = f.getAttribute('data-src');
            if (src && src !== 'about:blank') f.src = src; 
        });
    }
})();
</script>
<!-- clbntb-pagespeed-processed -->
JS;

    if (stripos($html, '</body>') !== false && stripos($html, 'ai-type-lazy-iframe-js') === false) {
        $html = str_replace('</body>', $lazy_script . "\n</body>", $html);
    }

    return $html;
}

/**
 * Tự động bổ sung thuộc tính width và height cho các thẻ <img> và <iframe> thiếu kích thước
 * Giúp triệt tiêu lỗi layout shift (CLS) theo chuẩn Google Lighthouse.
 */
function clbntb_add_missing_image_dimensions($html) {
    if (empty($html)) return $html;

    $upload_dir = function_exists('wp_upload_dir') ? wp_upload_dir() : [];
    $basedir = isset($upload_dir['basedir']) ? $upload_dir['basedir'] : (defined('WP_CONTENT_DIR') ? WP_CONTENT_DIR . '/uploads' : '');
    $baseurl = isset($upload_dir['baseurl']) ? $upload_dir['baseurl'] : (defined('WP_CONTENT_URL') ? WP_CONTENT_URL . '/uploads' : '');

    // 1. Xử lý thẻ <img> thiếu width / height
    $html = preg_replace_callback('/<img([^>]+)>/i', function($matches) use ($basedir, $baseurl) {
        $img_tag = $matches[0];
        $attrs = $matches[1];

        $has_width  = (bool)preg_match('/\bwidth\s*=\s*["\']?[^"\'>\s]+["\']?/i', $attrs);
        $has_height = (bool)preg_match('/\bheight\s*=\s*["\']?[^"\'>\s]+["\']?/i', $attrs);

        if ($has_width && $has_height) {
            return $img_tag;
        }

        $src = '';
        if (preg_match('/\bsrc\s*=\s*["\']([^"\']+)["\']/i', $attrs, $sm)) {
            $src = $sm[1];
        } elseif (preg_match('/\bdata-src\s*=\s*["\']([^"\']+)["\']/i', $attrs, $sm)) {
            $src = $sm[1];
        }

        $width = null;
        $height = null;

        if (!empty($src) && !empty($basedir)) {
            $file_path = '';
            if (!empty($baseurl) && strpos($src, $baseurl) !== false) {
                $file_path = str_replace($baseurl, $basedir, $src);
            } elseif (strpos($src, '/wp-content/uploads/') !== false) {
                $rel = substr($src, strpos($src, '/wp-content/uploads/'));
                if (defined('WP_CONTENT_DIR')) {
                    $file_path = WP_CONTENT_DIR . str_replace('/wp-content/', '/', $rel);
                }
            }

            if (!empty($file_path) && file_exists($file_path)) {
                $size = @getimagesize($file_path);
                if (is_array($size) && !empty($size[0]) && !empty($size[1])) {
                    $width = $size[0];
                    $height = $size[1];
                }
            }
        }

        if (!$width || !$height) {
            if (!$has_width && !$has_height) {
                $width = 600;
                $height = 400;
            }
        }

        $add_attrs = '';
        if (!$has_width && $width) {
            $add_attrs .= ' width="' . esc_attr($width) . '"';
        }
        if (!$has_height && $height) {
            $add_attrs .= ' height="' . esc_attr($height) . '"';
        }

        if (stripos($attrs, 'loading=') === false && stripos($attrs, 'no-lazy') === false && stripos($attrs, 'rev-slide') === false) {
            $add_attrs .= ' loading="lazy"';
        }
        if (stripos($attrs, 'decoding=') === false) {
            $add_attrs .= ' decoding="async"';
        }

        return '<img' . $attrs . $add_attrs . '>';
    }, $html);

    // 2. Xử lý thẻ <iframe> thiếu width / height
    $html = preg_replace_callback('/<iframe([^>]+)>/i', function($matches) {
        $tag = $matches[0];
        $attrs = $matches[1];

        $has_width  = (bool)preg_match('/\bwidth\s*=\s*["\']?[^"\'>\s]+["\']?/i', $attrs);
        $has_height = (bool)preg_match('/\bheight\s*=\s*["\']?[^"\'>\s]+["\']?/i', $attrs);

        if ($has_width && $has_height) return $tag;

        $add = '';
        if (!$has_width) $add .= ' width="100%"';
        if (!$has_height) $add .= ' height="600"';

        return '<iframe' . $attrs . $add . '>';
    }, $html);

    return $html;
}
