<?php
/**
 * Plugin Name: Công cụ AI Type
 * Plugin URI: https://type.vn/
 * Description: Plugin này cung cấp các nút kết nối tùy chỉnh cho nhiều nền tảng như Điện thoại, Zalo, Facebook, Tiktok,... giúp người dùng dễ dàng liên lạc qua kênh giao tiếp ưa thích. Đặc biệt, plugin Tích hợp AI tạo nội dung chuẩn SEO, Spinner bài viết, Chatbot tự động tư vấn, Tối ưu điểm Google PageSpeed, WebP và CDN
 * Version: 1.0.70
 * Author: type.vn
 * Author URI: https://profiles.wordpress.org/buctuong2000
 * License: Miễn phí (Free)
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// --- BẮT ĐẦU CƠ CHẾ FULL PAGE CACHE SIÊU TỐC (REDIS + FILE FALLBACK) ---
$clbntb_bypass_cache = false;
$clbntb_logged_in_user = '';

foreach ($_COOKIE as $key => $value) {
    if (strpos($key, 'wp_woocommerce_session_') === 0 || strpos($key, 'comment_author_') === 0) {
        $clbntb_bypass_cache = true;
        break;
    }
    if (strpos($key, 'wordpress_logged_in_') === 0) {
        $parts = explode('|', $value);
        if (isset($parts[0])) {
            $clbntb_logged_in_user = $parts[0];
        }
    }
}

if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone']) || strpos($_SERVER['REQUEST_URI'], '/wp-json/') !== false || strpos($_SERVER['REQUEST_URI'], '/llms.txt') !== false) {
    $clbntb_bypass_cache = true;
}

// Chạy ngay khi plugin vừa được gọi, bỏ qua 100% core WordPress nếu có cache
if (!$clbntb_bypass_cache && $_SERVER['REQUEST_METHOD'] === 'GET' && strpos($_SERVER['REQUEST_URI'], '/wp-admin/') === false && strpos($_SERVER['REQUEST_URI'], '/wp-json/') === false) {
    $host = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'localhost';
    $base_key = md5($host . $_SERVER['REQUEST_URI']);
    if (!empty($clbntb_logged_in_user)) {
        $branch_key = md5('user:' . $clbntb_logged_in_user);
        $clbntb_cache_key = $base_key . '_' . $branch_key;
    } else {
        $clbntb_cache_key = $base_key;
    }
    
    $client_accepts_gzip = isset($_SERVER['HTTP_ACCEPT_ENCODING']) && strpos($_SERVER['HTTP_ACCEPT_ENCODING'], 'gzip') !== false;
    $max_age = !empty($clbntb_logged_in_user) ? 43200 : 86400; // User: 12h, Khách: 24h

    // === ƯU TIÊN 1: Redis Cache (nhanh nhất, < 1ms) ===
    $clbntb_redis_hit = false;
    require_once __DIR__ . '/inc/redis-driver.php';
    $clbntb_redis = CLBNTB_Redis::instance();
    
    if ($clbntb_redis->is_available()) {
        // Thử lấy bản GZIP từ Redis trước
        if ($client_accepts_gzip) {
            $cached_gz = $clbntb_redis->get($clbntb_cache_key . ':gz');
            if ($cached_gz !== false) {
                header('Content-Type: text/html; charset=UTF-8');
                header('Content-Encoding: gzip');
                header('X-AI-Type-Cache: HIT-REDIS-GZIP');
                if (!empty($clbntb_logged_in_user)) header('X-AI-Type-User: ' . $clbntb_logged_in_user);
                echo $cached_gz;
                exit;
            }
        }
        // Fallback: bản HTML thường từ Redis
        $cached_html = $clbntb_redis->get($clbntb_cache_key);
        if ($cached_html !== false) {
            header('Content-Type: text/html; charset=UTF-8');
            header('X-AI-Type-Cache: HIT-REDIS');
            if (!empty($clbntb_logged_in_user)) header('X-AI-Type-User: ' . $clbntb_logged_in_user);
            echo $cached_html;
            exit;
        }
    }

    // === ƯU TIÊN 2: File Cache (fallback nếu Redis miss hoặc unavailable) ===
    $clbntb_cache_dir = (defined('WP_CONTENT_DIR') ? WP_CONTENT_DIR : ABSPATH . 'wp-content') . '/uploads/ai-type-cache/html';
    $clbntb_cache_file = $clbntb_cache_dir . '/' . $clbntb_cache_key . '.html';
    $clbntb_gz_file = $clbntb_cache_file . '.gz';
    
    if ($client_accepts_gzip && file_exists($clbntb_gz_file)) {
        if (time() - filemtime($clbntb_gz_file) < $max_age) {
            header('Content-Encoding: gzip');
            header('X-AI-Type-Cache: HIT-GZIP');
            if (!empty($clbntb_logged_in_user)) header('X-AI-Type-User: ' . $clbntb_logged_in_user);
            header('Content-Type: text/html; charset=UTF-8');
            readfile($clbntb_gz_file);
            exit;
        }
    } 
    elseif (file_exists($clbntb_cache_file)) {
        if (time() - filemtime($clbntb_cache_file) < $max_age) {
            header('X-AI-Type-Cache: HIT');
            if (!empty($clbntb_logged_in_user)) header('X-AI-Type-User: ' . $clbntb_logged_in_user);
            readfile($clbntb_cache_file);
            exit;
        }
    }
}
// --- KẾT THÚC CƠ CHẾ FULL PAGE CACHE ---

// --- TỰ ĐỘNG BẬT GZIP NÉN NẾU SERVER CHƯA BẬT ---
// Kiểm tra: nếu server (Apache mod_deflate / Nginx gzip) chưa bật nén,
// plugin tự bật bằng PHP zlib để đảm bảo mọi response đều được nén.
if (!is_admin() && isset($_SERVER['HTTP_ACCEPT_ENCODING']) && strpos($_SERVER['HTTP_ACCEPT_ENCODING'], 'gzip') !== false) {
    // Chỉ bật nếu chưa có nén nào đang chạy
    if (!ini_get('zlib.output_compression') && !ini_get('output_handler')) {
        // Ưu tiên zlib (tương thích tốt nhất, không xung đột output buffer)
        if (function_exists('gzencode')) {
            @ini_set('zlib.output_compression', 'On');
            @ini_set('zlib.output_compression_level', '6'); // Level 6: cân bằng tốc độ/nén
        }
    }
}
// --- KẾT THÚC TỰ ĐỘNG BẬT GZIP ---

define( 'CLBNTB_FILE', __FILE__ );
define( 'CLBNTB_NAME', basename( CLBNTB_FILE ) );
define( 'CLBNTB_BASE_NAME', plugin_basename( CLBNTB_FILE ) );
define( 'CLBNTB_PATH', plugin_dir_path( CLBNTB_FILE ) );

// Load Redis driver globally (cả admin + frontend) để status page detect được
if (!class_exists('CLBNTB_Redis')) {
    require_once __DIR__ . '/inc/redis-driver.php';
}

// --- BẢO MẬT TRANG QUẢN TRỊ ---
add_action('init', 'clbntb_hide_admin_login', 1);
function clbntb_hide_admin_login() {
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    $is_logged_in = false;
    foreach ($_COOKIE as $key => $value) {
        if (strpos($key, 'wordpress_logged_in_') === 0) {
            $is_logged_in = true;
            break;
        }
    }

    // 1. Chặn wp-admin nếu chưa đăng nhập (Ngoại trừ ajax)
    if (!$is_logged_in && strpos($path, '/wp-admin') === 0) {
        if (strpos($path, 'admin-ajax.php') === false && strpos($path, 'admin-post.php') === false) {
            wp_redirect(home_url('/'));
            exit;
        }
    }

    // 2. Chặn truy cập trực tiếp wp-login.php để chống hacker quét web
    if (!$is_logged_in && strpos($path, 'wp-login.php') !== false && $_SERVER['REQUEST_METHOD'] === 'GET' && !isset($_GET['quan-ly'])) {
        wp_redirect(home_url('/'));
        exit;
    }

    // 3. Mở cổng đăng nhập bí mật
    if ($path === '/quan-ly' || $path === '/quan-ly/') {
        wp_redirect(site_url('wp-login.php?quan-ly=1'));
        exit;
    }
}
define( 'CLBNTB_URL', plugin_dir_url( CLBNTB_FILE ) ); 

function clbntb_register_mysettings() {
    register_setting( 'clbntb-settings-group', 'ai_type_license_key', 'sanitize_text_field' );
    $settings = [
        'clbntb-settings-group' => [
            'clbntb_phone', 'clbntb_phone2', 'clbntb_phone3',
            'clbntb_color_clbntb_phone', 'clbntb_color_clbntb_phone2', 'clbntb_color_clbntb_phone3',
            'clbntb_linkfanpage', 'clbntb_linkmessenger', 'clbntb_whatsapp', 'clbntb_zalo', 'clbntb_zalo_oa_id',
            'clbntb_telegram', 'clbntb_instagram', 'clbntb_youtube', 'clbntb_tiktok', 'clbntb_viber',
            'clbntb_contact_link', 'clbntb_color_clbntb_contact', 'clbntb_linkggmap', 'clbntb_color_linkggmap',
            'clbntb_id_fanpage', 'clbntb_color_fb', 'logged_in_greeting'
        ],
        'clbntb-settings-group-chatbot' => [
            'google_api_key', 'llm_model', 'simple_chatbot_app_token', 'simple_chatbot_username', 
            'simple_chatbot_api', 'simple_chatbot_data_source'
        ],
        'clbntb-settings-group-setting' => [
            'setting_size', 'clbntb_location', 'clbntb_location_bottom', 
            'clbntb_hide_mobile', 'clbntb_hide_desktop', 'clbntb_effect_type', 'clbntb_custom_css', 'clbntb_layout_type', 'clbntb_toggle_bg_color', 'clbntb_disable_admin_notices'
        ]
    ];
    foreach ($settings as $group => $fields) {
        foreach ($fields as $field) {
            $callback = in_array($field, ['clbntb_linkfanpage', 'clbntb_linkmessenger', 'clbntb_linkggmap']) ? 'esc_url_raw' : 'clbntb_sanitize_text_field_with_limit';
            if (strpos($field, 'color') !== false) {
                $callback = 'clbntb_sanitize_hex_color_with_limit';
            }
            if ($field === 'clbntb_custom_css') {
                $callback = 'sanitize_textarea_field';
            }
            register_setting($group, $field, ['sanitize_callback' => $callback]);
        }
    }
}
function clbntb_sanitize_text_field_with_limit( $value ) {
    $value = wp_strip_all_tags( $value );
    return substr( $value, 0, 255 );
}
function clbntb_sanitize_hex_color_with_limit( $value ) {
    $value = sanitize_hex_color( $value );
    return substr( $value, 0, 7 );
}

function clbntb_create_menu() {
    add_menu_page('AI Type', 'AI Type', 'administrator', 'connect_type', 'clbntb_settings_page',plugins_url('/img/icon1.svg', __FILE__), 10);
    
    if (defined('AITYPE_LICENSE_INVALID')) {
        // Chỉ hiện tab nhập bản quyền
        add_submenu_page( 'connect_type', 'Kích hoạt Bản quyền', 'Kích hoạt Bản quyền', 'administrator', 'connect_type', 'clbntb_settings_page', 1 );
    } else {
        // Explicitly rename the first submenu item to match the first tab
        add_submenu_page( 'connect_type', 'Danh sách nút', 'Danh sách nút', 'administrator', 'connect_type', 'clbntb_settings_page', 1 );
        
        add_submenu_page( 'connect_type', 'Chatbot', 'Chatbot', 'administrator', 'connect_type_chatbot', 'clbntb_settings_page_chatbot', 40 );
        add_submenu_page( 'connect_type', 'CDN và Cache', 'CDN và Cache', 'administrator', 'connect_type_cdn', 'clbntb_settings_page_cdn', 50 );
        add_submenu_page( 'connect_type', 'Trạng thái', 'Trạng thái', 'administrator', 'connect_type_status', 'clbntb_settings_page_status', 52 );
        
        global $SimpleSEO;
        if (isset($SimpleSEO) && isset($SimpleSEO->Admin)) {
            add_submenu_page( 'connect_type', 'SEO', 'SEO', 'administrator', 'simpleSEOAdminOptions', [$SimpleSEO->Admin, 'simpleSEOAdminOptions'], 55 );
        }

        add_submenu_page( 'connect_type', 'Cài đặt', 'Cài đặt', 'administrator', 'connect_type_setting', 'clbntb_settings_page_setting', 60 );
    }
    
    add_action( 'admin_init', 'clbntb_register_mysettings' );
}
add_action('admin_menu', 'clbntb_create_menu'); 
add_filter( 'plugin_action_links_' . plugin_basename(__FILE__), 'clbntb_add_action_links' );
function clbntb_add_action_links ( $actions ) {
   $mylinks = array(
      '<a href="' . admin_url( 'admin.php?page=connect_type' ) . '">Cài đặt</a>',
   );
   $actions = array_merge( $actions, $mylinks );
   return $actions;
}

function clbntb_custom_admin_css($hook) {
    wp_register_style( 'custom-admin', plugins_url( 'css/style-admin.css', __FILE__ ), array(), filemtime(plugin_dir_path(__FILE__) . 'css/style-admin.css') );
    wp_enqueue_style( 'custom-admin' );
    
    if (isset($_GET['page']) && $_GET['page'] === 'connect_type_chatbot') {
        wp_enqueue_media();
    }
}
add_action( 'admin_enqueue_scripts', 'clbntb_custom_admin_css' );


function clbntb_settings_page() {
    include CLBNTB_PATH. '/inc/admin.php';
}
function clbntb_settings_page_setting() {
    include CLBNTB_PATH. '/inc/setting.php';
}
function clbntb_settings_page_chatbot() {
    include CLBNTB_PATH. '/inc/chatbot.php';
}
function clbntb_settings_page_help() {
    include CLBNTB_PATH. '/inc/help.php';
}
function clbntb_settings_page_cdn() {
    include CLBNTB_PATH. '/inc/cdn-cache.php';
}
function clbntb_settings_page_status() {
    include CLBNTB_PATH. '/inc/status.php';
}

// --- TỰ ĐỘNG MÃ HÓA & GIẢI MÃ API KEY ---
function ai_type_encrypt_option($value) {
    if (empty($value)) return $value;
    if (strpos($value, 'AITYPE_ENC:') === 0) return $value;
    $key = defined('SECURE_AUTH_KEY') ? SECURE_AUTH_KEY : 'ai-type-fallback-key';
    $iv = openssl_random_pseudo_bytes(openssl_cipher_iv_length('aes-256-cbc'));
    $encrypted = openssl_encrypt($value, 'aes-256-cbc', $key, 0, $iv);
    return 'AITYPE_ENC:' . base64_encode($encrypted . '::' . $iv);
}

function ai_type_decrypt_option($value) {
    if (empty($value)) return $value;
    if (strpos($value, 'AITYPE_ENC:') !== 0) return $value;
    $data = base64_decode(substr($value, 11));
    if (strpos($data, '::') === false) return $value;
    list($encrypted_data, $iv) = explode('::', $data, 2);
    $key = defined('SECURE_AUTH_KEY') ? SECURE_AUTH_KEY : 'ai-type-fallback-key';
    $decrypted = openssl_decrypt($encrypted_data, 'aes-256-cbc', $key, 0, $iv);
    return $decrypted !== false ? $decrypted : $value;
}

$secure_options = ['google_api_key', 'simple_chatbot_app_token', 'clbntb_cdn_api_key'];
foreach ($secure_options as $opt) {
    add_filter("pre_update_option_{$opt}", 'ai_type_encrypt_option', 10, 1);
    add_filter("option_{$opt}", 'ai_type_decrypt_option', 10, 1);
}
// --- KẾT THÚC MÃ HÓA ---


// --- BẢO MẬT 100%: ƯU TIÊN ĐỌC API KEY TỪ CONSTANT (TRÁNH LƯU VÀO DATABASE) ---
$secure_constants = [
    'google_api_key' => 'AITYPE_GOOGLE_API_KEY',
    'simple_chatbot_app_token' => 'AITYPE_CHATBOT_TOKEN',
    'clbntb_cdn_api_key' => 'AITYPE_CDN_API_KEY'
];

foreach ($secure_constants as $opt => $const_name) {
    add_filter("pre_option_{$opt}", function($default_val) use ($const_name) {
        if (defined($const_name)) {
            return constant($const_name);
        }
        return false; // Bỏ qua, tiếp tục đọc từ Database (rồi tự động giải mã)
    });
}
// --- KẾT THÚC ƯU TIÊN CONSTANT ---


// --- TÍNH NĂNG ẨN THÔNG BÁO ADMIN ---
if (get_option('clbntb_disable_admin_notices')) {
    add_action('admin_head', function() {
        remove_all_actions('admin_notices');
        remove_all_actions('all_admin_notices');
    }, 1);
    add_action('admin_enqueue_scripts', function() {
        wp_add_inline_style('common', 'div.notice, div.updated, div.error, .update-nag, .notice-warning, .notice-info, .notice-success { display: none !important; }');
    }, 999);
}

// YÊU CẦU BẢN QUYỀN TRƯỚC KHI KHỞI TẠO TÍNH NĂNG (TIGHT COUPLING)
if (get_option('clbntb_anti_cls') === '1') {
    require_once CLBNTB_PATH . '/inc/anti-cls.php';
}
require_once CLBNTB_PATH . '/inc/core-license.php';
require_once CLBNTB_PATH . '/inc/button-contact.php';
require_once CLBNTB_PATH . '/inc/chatbot-frontend.php';
require_once CLBNTB_PATH . '/inc/cache-builder.php';
require_once CLBNTB_PATH . '/inc/pagespeed-optimizer.php';


// Tối ưu hóa: Xóa bỏ Emoji mặc định của WordPress để tăng tốc web
function clbntb_disable_emojis() {
    remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
    remove_action( 'admin_print_scripts', 'print_emoji_detection_script' );
    remove_action( 'wp_print_styles', 'print_emoji_styles' );
    remove_action( 'admin_print_styles', 'print_emoji_styles' ); 
    remove_filter( 'the_content_feed', 'wp_staticize_emoji' );
    remove_filter( 'comment_text_rss', 'wp_staticize_emoji' ); 
    remove_filter( 'wp_mail', 'wp_staticize_emoji_for_email' );
    add_filter( 'tiny_mce_plugins', 'clbntb_disable_emojis_tinymce' );
    add_filter( 'wp_resource_hints', 'clbntb_disable_emojis_remove_dns_prefetch', 10, 2 );
}
add_action( 'init', 'clbntb_disable_emojis' );

function clbntb_disable_emojis_tinymce( $plugins ) {
    if ( is_array( $plugins ) ) {
        return array_diff( $plugins, array( 'wpemoji' ) );
    } else {
        return array();
    }
}

function clbntb_disable_emojis_remove_dns_prefetch( $urls, $relation_type ) {
    if ( 'dns-prefetch' == $relation_type ) {
        /** This filter is documented in wp-includes/formatting.php */
        $emoji_svg_url = apply_filters( 'emoji_svg_url', 'https://s.w.org/images/core/emoji/2/svg/' );
        $urls = array_diff( $urls, array( $emoji_svg_url ) );
    }
    return $urls;
}

// Helper function to get CDN domain
function clbntb_get_cdn_domain() {
    // 1. Kiểm tra hằng số override trong wp-config.php (Dành cho test local)
    if (defined('CLBNTB_CDN_DOMAIN_OVERRIDE') && !empty(CLBNTB_CDN_DOMAIN_OVERRIDE)) {
        return CLBNTB_CDN_DOMAIN_OVERRIDE;
    }
    // 2. Kiểm tra option cũ (nếu khách chưa xóa DB cũ)
    $domain = get_option('clbntb_cdn_domain', '');
    if (!empty($domain)) {
        return $domain;
    }
    // 3. Mặc định tự động lấy domain thật của website
    if (!empty($_SERVER['HTTP_HOST'])) {
        return $_SERVER['HTTP_HOST'];
    }
    $parsed = parse_url(site_url(), PHP_URL_HOST);
    
    return $parsed;
}

function clbntb_fix_wp_admin_slash() {
    echo '<script>if(window.location.pathname === "/wp-admin"){window.location.replace("/wp-admin/");}</script>';
}
add_action('admin_head', 'clbntb_fix_wp_admin_slash');

// --- VIỆT HÓA SIMPLE SEO ---
add_filter('gettext', 'ai_type_seo_translate', 10, 3);
function ai_type_seo_translate($translated_text, $text, $domain) {
    if ($domain === 'ai-type-seo') {
        $translations = [
            'AI Type SEO Options' => 'Cấu hình SEO',
            'Default Meta Title' => 'Tiêu đề Meta mặc định',
            'Default Meta Description' => 'Mô tả Meta mặc định',
            'Default Meta Keywords' => 'Từ khóa Meta mặc định',
            'This is the default information used for meta title (&lt;title&gt;&lt;&#47;title&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.' => 'Thông tin này được dùng cho thẻ tiêu đề (title) mặc định. Nếu trang chủ đã được thiết lập nội dung SEO riêng, thẻ này sẽ bị bỏ qua.',
            'This is the default information used for meta description (&lt;meta name="description" content=""&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.' => 'Thông tin này được dùng cho thẻ mô tả (description) mặc định. Nếu trang chủ có thiết lập riêng, thẻ này sẽ bị bỏ qua.',
            'This is the default information used for meta keywords (&lt;meta name="keywords" content=""&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.<br/><em>A comma separated list of your most important keywords for this will be written as the meta keywords.</em>' => 'Các từ khóa mặc định phân cách bằng dấu phẩy. Được sử dụng cho thẻ keywords nếu trang chủ không thiết lập riêng.',
            'Search Engine Site Verification' => 'Xác minh Website (Google, Bing...)',
            'Google Webmaster Tools' => 'Mã xác minh Google Search Console',
            'Yandex Webmaster Tools' => 'Mã xác minh Yandex',
            'Bing Webmaster Tools' => 'Mã xác minh Bing Webmaster',
            'Analytics' => 'Công cụ phân tích (Analytics)',
            'Google Analytics 4' => 'Mã theo dõi Google Analytics 4 (GA4)',
            'Facebook Pixel' => 'Mã Facebook Pixel',
            'Twitter Pixel' => 'Mã Twitter Pixel',
            'Advanced' => 'Cài đặt Nâng cao',
            'Disable SEO completely' => 'Tắt hoàn toàn module SEO',
            'Save Changes' => 'Lưu Cài Đặt',
            'SEO Options' => 'SEO',
            'AI Type SEO' => 'SEO',
            'Search Engine Optimiztion' => 'Tối ưu hóa công cụ tìm kiếm',
            'Sitemap XML' => 'Sơ đồ trang web (Sitemap XML)',
            'Turn on Sitemap XML' => 'Bật Sitemap XML',
            'The sitemap is located at' => 'Sitemap của bạn nằm tại',
            'This information will be placed inside of the %s tag of every page' => 'Thông tin này sẽ được nhúng vào bên trong thẻ %s của mọi trang.'
        ];
        if (isset($translations[$text])) {
            return $translations[$text];
        }
    }
    return $translated_text;
}
