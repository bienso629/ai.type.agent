<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

if (defined('AITYPE_LICENSE_INVALID')) {
    echo '<div class="wrap"><h1>🛑 Tính năng bị khóa</h1><p style="font-size: 16px;">Vui lòng nhập mã bản quyền hợp lệ tại trang cấu hình chính để sử dụng chức năng này.</p></div>';
    return;
}
?>
<div class="wrap">
    <h1>Trạng Thái Hệ Thống</h1>
    <h2 class="nav-tab-wrapper">
        <a href="?page=connect_type" class="nav-tab ">Danh sách nút</a>
        <a href="?page=connect_type_chatbot" class="nav-tab ">Chatbot</a>
        <a href="?page=connect_type_cdn" class="nav-tab ">CDN và Cache</a>
        <a href="?page=connect_type_status" class="nav-tab nav-tab-active">Trạng thái</a>
        <a href="?page=simpleSEOAdminOptions" class="nav-tab ">SEO</a>
        <a href="?page=connect_type_setting" class="nav-tab ">Cài đặt</a>
    </h2>

    <br>

    <p>Tổng quan các tính năng tối ưu hiệu suất đang hoạt động trên website của bạn.</p>
    <?php
    // === Thu thập trạng thái ===
    
    // 1. Redis
    $redis_status = 'off';
    $redis_info_text = 'Chưa cấu hình';
    $redis_configured = defined('AITYPE_REDIS_HOST');
    $redis_ext = class_exists('Redis');
    
    if (class_exists('CLBNTB_Redis')) {
        $redis = CLBNTB_Redis::instance();
        if ($redis->is_available()) {
            $redis_status = 'on';
            $info = $redis->info();
            if (is_array($info) && !empty($info['connected'])) {
                $redis_info_text = 'v' . ($info['version'] ?? '?') . ' | RAM: ' . ($info['used_memory_human'] ?? '?') . ' | FPC keys: ' . ($info['fpc_keys'] ?? 0) . ' | Hit rate: ' . ($info['hit_rate'] ?? 'N/A');
            } else {
                $redis_info_text = 'Đã kết nối';
            }
        } else {
            // Class load được nhưng kết nối thất bại
            $r_host = defined('AITYPE_REDIS_HOST') ? AITYPE_REDIS_HOST : '127.0.0.1';
            $r_port = defined('AITYPE_REDIS_PORT') ? AITYPE_REDIS_PORT : 6379;
            
            if (!$redis_ext) {
                $redis_status = 'error';
                $redis_info_text = 'Extension php-redis chưa cài đặt (sudo apt install php-redis)';
            } else {
                // Thử kết nối trực tiếp để lấy lỗi cụ thể
                $redis_status = 'error';
                try {
                    $test = new Redis();
                    $test_result = @$test->connect($r_host, $r_port, 2);
                    if ($test_result) {
                        $r_pass = defined('AITYPE_REDIS_PASSWORD') ? AITYPE_REDIS_PASSWORD : '';
                        if (!empty($r_pass)) {
                            $auth_result = @$test->auth($r_pass);
                            if (!$auth_result) {
                                $redis_info_text = 'Kết nối OK nhưng xác thực thất bại — kiểm tra AITYPE_REDIS_PASSWORD';
                            } else {
                                $redis_status = 'on';
                                $redis_info_text = 'Đã kết nối tới ' . $r_host . ':' . $r_port;
                            }
                        } else {
                            $redis_status = 'on';
                            $redis_info_text = 'Đã kết nối tới ' . $r_host . ':' . $r_port;
                        }
                        $test->close();
                    } else {
                        $redis_info_text = 'Không kết nối được tới ' . $r_host . ':' . $r_port . ' — Redis server có đang chạy không?';
                    }
                } catch (Exception $e) {
                    $redis_info_text = 'Lỗi kết nối ' . $r_host . ':' . $r_port . ' — ' . $e->getMessage();
                }
            }
        }
    } else {
        // Class chưa load — plugin chưa kích hoạt đúng
        if (!$redis_ext) {
            $redis_info_text = 'Extension php-redis chưa cài đặt';
        } elseif ($redis_configured) {
            $redis_status = 'error';
            $redis_info_text = 'Đã cấu hình trong wp-config.php nhưng class CLBNTB_Redis chưa load — thử tắt/bật plugin';
        } else {
            $redis_info_text = 'Extension OK, thêm AITYPE_REDIS_HOST vào wp-config.php để kích hoạt';
        }
    }
    
    // 2. GZIP
    $gzip_status = 'off';
    $gzip_info = '';
    if (ini_get('zlib.output_compression')) {
        $gzip_status = 'on';
        $gzip_info = 'zlib.output_compression = On (Level ' . (ini_get('zlib.output_compression_level') ?: 'default') . ')';
    } elseif (function_exists('apache_get_modules') && in_array('mod_deflate', apache_get_modules())) {
        $gzip_status = 'on';
        $gzip_info = 'Apache mod_deflate đang bật';
    } elseif (isset($_SERVER['SERVER_SOFTWARE']) && stripos($_SERVER['SERVER_SOFTWARE'], 'nginx') !== false) {
        $gzip_status = 'warn';
        $gzip_info = 'Nginx detected — kiểm tra "gzip on;" trong nginx.conf';
    } else {
        if (function_exists('gzencode')) {
            $gzip_status = 'on';
            $gzip_info = 'Plugin tự bật qua PHP zlib';
        } else {
            $gzip_info = 'PHP gzencode() không khả dụng';
        }
    }
    
    // 3. Full Page Cache
    $fpc_status = 'on';
    $cache_dir = (defined('WP_CONTENT_DIR') ? WP_CONTENT_DIR : ABSPATH . 'wp-content') . '/uploads/ai-type-cache/html';
    $fpc_files = 0;
    $fpc_size = 0;
    if (file_exists($cache_dir)) {
        $files = glob($cache_dir . '/*');
        if (is_array($files)) {
            $fpc_files = count($files);
            foreach ($files as $f) {
                if (is_file($f)) $fpc_size += filesize($f);
            }
        }
    }
    $fpc_info = $fpc_files . ' trang đã cache | ' . size_format($fpc_size);
    
    // 4. WP_CACHE constant
    $wp_cache_status = defined('WP_CACHE') && WP_CACHE ? 'on' : 'off';
    $wp_cache_info = $wp_cache_status === 'on' ? 'WP_CACHE = true (advanced-cache.php hoạt động)' : 'Chưa bật. Chạy "Làm Ấm Cache" để tự động kích hoạt.';
    
    // 5. Advanced Cache drop-in
    $adv_cache_status = file_exists(WP_CONTENT_DIR . '/advanced-cache.php') ? 'on' : 'off';
    $adv_cache_info = $adv_cache_status === 'on' ? 'wp-content/advanced-cache.php đã cài đặt' : 'Chưa cài đặt drop-in';
    
    // 6. Delay JS
    $delay_js_status = get_option('clbntb_delay_js', '1') !== '0' ? 'on' : 'off';
    $delay_js_info = $delay_js_status === 'on' ? 'GTM, FB Pixel, Chatbot bị trì hoãn tới khi user tương tác' : 'Đã tắt';
    
    // 7. Safe Optimization
    $safe_opt_status = get_option('clbntb_disable_optimization') !== '1' ? 'on' : 'off';
    $safe_opt_info = $safe_opt_status === 'on' ? 'Defer CSS/JS, preload LCP, minify HTML, font-display swap' : 'Đã tắt bởi người dùng';
    
    // 8. WebP Rewrite
    $webp_status = get_option('clbntb_rewrite_webp') == '1' ? 'on' : 'off';
    $webp_info = $webp_status === 'on' ? 'Tự động thay .jpg/.png → .webp trên giao diện' : 'Chưa bật';
    $webp_support = function_exists('imagewebp') ? 'on' : 'error';
    $webp_support_info = $webp_support === 'on' ? 'PHP GD imagewebp() sẵn sàng' : 'PHP GD chưa hỗ trợ WebP';
    
    // 9. CDN
    $cdn_url = get_option('clbntb_cdn_url', '');
    $cdn_status = !empty($cdn_url) ? 'on' : 'off';
    $cdn_info = !empty($cdn_url) ? $cdn_url : 'Chưa cấu hình';
    
    // 10. User-Specific Cache
    $user_cache_status = get_option('clbntb_enable_user_cache') === '1' ? 'on' : 'off';
    $user_cache_info = $user_cache_status === 'on' ? 'Cache riêng cho từng user đăng nhập' : 'Chỉ cache cho khách (mặc định)';
    
    // 11. Anti-CLS
    $anti_cls_status = get_option('clbntb_anti_cls') === '1' ? 'on' : 'off';
    $anti_cls_info = $anti_cls_status === 'on' ? 'Vô hiệu hoá animations gây giật layout' : 'Chưa bật';
    
    // 12. PageSpeed Optimizer
    $pso_status = class_exists('CLBNTB_PageSpeed_Optimizer') ? 'on' : 'off';
    $pso_info = $pso_status === 'on' ? 'Defer JS, lazy-load iframe, preconnect, font-display' : 'Module chưa load';
    
    // 13. PHP Version
    $php_ver = phpversion();
    $php_status = version_compare($php_ver, '7.4', '>=') ? 'on' : 'warn';
    $php_info = 'PHP ' . $php_ver . ' | ' . php_sapi_name();
    
    // Render bảng
    $cdn_page = admin_url('admin.php?page=connect_type_cdn');
    
    $status_items = [
        ['group' => 'Cache Engine', 'items' => [
            ['name' => 'Full Page Cache (File)', 'status' => $fpc_status, 'info' => $fpc_info, 'icon' => '📄',
             'guide' => $fpc_status === 'on' ? null : "Tự động bật khi plugin hoạt động."],
            ['name' => 'Redis Full Page Cache', 'status' => $redis_status, 'info' => $redis_info_text, 'icon' => '🔴',
             'guide' => $redis_status === 'on' ? null : (!class_exists('Redis') 
                ? "# Bước 1: Cài Redis Server + PHP Extension\n# Ubuntu / Debian:\nsudo apt install redis-server php-redis\nsudo systemctl enable redis-server\nsudo systemctl restart apache2\n\n# CentOS / AlmaLinux:\nsudo yum install redis php-pecl-redis\nsudo systemctl enable redis\nsudo systemctl restart php-fpm\n\n# Bước 2: Thêm vào wp-config.php\ndefine('AITYPE_REDIS_HOST', '127.0.0.1');\ndefine('AITYPE_REDIS_PORT', 6379);"
                : "# Thêm vào wp-config.php (trước dòng \"That's all, stop editing!\")\ndefine('AITYPE_REDIS_HOST', '127.0.0.1');\ndefine('AITYPE_REDIS_PORT', 6379);\n// define('AITYPE_REDIS_PASSWORD', 'mật-khẩu'); // Nếu có\n// define('AITYPE_REDIS_DB', 0);")],
            ['name' => 'WP_CACHE Constant', 'status' => $wp_cache_status, 'info' => $wp_cache_info, 'icon' => '⚡',
             'guide' => $wp_cache_status === 'on' ? null : "# Thêm vào wp-config.php (trước dòng \"That's all, stop editing!\")\ndefine('WP_CACHE', true);"],
            ['name' => 'Advanced Cache Drop-in', 'status' => $adv_cache_status, 'info' => $adv_cache_info, 'icon' => '🚀',
             'guide' => $adv_cache_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → bấm "🔥 Làm Ấm Tất Cả Cache" để tự động tạo file này.'],
            ['name' => 'User-Specific Cache', 'status' => $user_cache_status, 'info' => $user_cache_info, 'icon' => '👤',
             'guide' => $user_cache_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → mục "Tối ưu hóa" → tick "Bật User-Specific Cache".'],
        ]],
        ['group' => 'Tối Ưu Hiệu Suất', 'items' => [
            ['name' => 'GZIP Compression', 'status' => $gzip_status, 'info' => $gzip_info, 'icon' => '📦',
             'guide' => ($gzip_status === 'on') ? null : "# Apache — thêm vào .htaccess:\n<IfModule mod_deflate.c>\n  AddOutputFilterByType DEFLATE text/html text/css text/javascript\n  AddOutputFilterByType DEFLATE application/javascript application/json\n  AddOutputFilterByType DEFLATE image/svg+xml\n</IfModule>\n\n# Nginx — thêm vào nginx.conf:\ngzip on;\ngzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;\ngzip_comp_level 6;"],
            ['name' => 'Safe Optimization (HTML/CSS/JS)', 'status' => $safe_opt_status, 'info' => $safe_opt_info, 'icon' => '🛡️',
             'guide' => $safe_opt_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → bỏ tick "Tắt Tối Ưu Hóa HTML/CSS/JS" → Lưu.'],
            ['name' => 'Delay JS Execution', 'status' => $delay_js_status, 'info' => $delay_js_info, 'icon' => '⏱️',
             'guide' => $delay_js_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → tick "Trì hoãn thực thi JS" → Lưu.'],
            ['name' => 'PageSpeed Optimizer', 'status' => $pso_status, 'info' => $pso_info, 'icon' => '🏎️',
             'guide' => $pso_status === 'on' ? null : 'Module tự động bật khi plugin hoạt động. Thử tắt rồi bật lại plugin.'],
            ['name' => 'Anti-CLS (Chống giật)', 'status' => $anti_cls_status, 'info' => $anti_cls_info, 'icon' => '📐',
             'guide' => $anti_cls_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → tick "Bật Anti-CLS" → Lưu.'],
        ]],
        ['group' => 'Media & CDN', 'items' => [
            ['name' => 'CDN Rewrite', 'status' => $cdn_status, 'info' => $cdn_info, 'icon' => '🌐',
             'guide' => $cdn_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → nhập đường dẫn CDN (VD: https://cdn.domain.com) → Lưu.'],
            ['name' => 'WebP Rewrite', 'status' => $webp_status, 'info' => $webp_info, 'icon' => '🖼️',
             'guide' => $webp_status === 'on' ? null : 'link:' . $cdn_page . '|Vào CDN và Cache → tick "Sử dụng WebP" → Lưu. (Cần chuyển đổi ảnh WebP trước)'],
            ['name' => 'WebP Engine (PHP GD)', 'status' => $webp_support, 'info' => $webp_support_info, 'icon' => '🔧',
             'guide' => $webp_support === 'on' ? null : "# Ubuntu / Debian:\nsudo apt install php-gd\nsudo systemctl restart apache2\n\n# CentOS:\nsudo yum install php-gd\nsudo systemctl restart php-fpm"],
        ]],
        ['group' => 'Server', 'items' => [
            ['name' => 'PHP Runtime', 'status' => $php_status, 'info' => $php_info, 'icon' => '🐘',
             'guide' => $php_status === 'on' ? null : "Liên hệ nhà cung cấp hosting để nâng cấp PHP lên 8.1+.\nHoặc thay đổi trong cPanel → Select PHP Version."],
            ['name' => 'Redis Extension', 'status' => class_exists('Redis') ? 'on' : 'off', 'info' => class_exists('Redis') ? 'php-redis đã cài' : 'Chưa cài — cần cài để bật Redis Cache', 'icon' => '🧩',
             'guide' => class_exists('Redis') ? null : "# Ubuntu / Debian:\nsudo apt install php-redis\nsudo systemctl restart apache2\n\n# CentOS / AlmaLinux:\nsudo yum install php-pecl-redis\nsudo systemctl restart php-fpm\n\n# Xác nhận:\nphp -m | grep redis"],
        ]],
    ];
    
    $guide_counter = 0;
    ?>
    <style>
        .ait-status-table { border-collapse: collapse; width: 100%; margin-bottom: 20px; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
        .ait-status-table th, .ait-status-table td { padding: 10px 14px; text-align: left; border-bottom: 1px solid #f0f0f1; vertical-align: top; }
        .ait-status-table th { background: #f6f7f7; font-weight: 600; }
        .ait-status-group { background: #2271b1 !important; color: #fff; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; }
        .ait-status-group td { padding: 8px 14px !important; font-weight: 600; }
        .ait-badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; line-height: 20px; }
        .ait-badge-on { background: #edfcf0; color: #00a32a; border: 1px solid #00a32a; }
        .ait-badge-off { background: #f6f7f7; color: #787c82; border: 1px solid #c3c4c7; }
        .ait-badge-error { background: #fcf0f1; color: #d63638; border: 1px solid #d63638; }
        .ait-badge-warn { background: #fef8ee; color: #996800; border: 1px solid #dba617; }
        .ait-status-info { color: #646970; font-size: 12px; }
        .ait-status-icon { font-size: 16px; margin-right: 4px; }
        .ait-guide-btn { background: #f0f6fc; border: 1px solid #2271b1; color: #2271b1; padding: 3px 10px; border-radius: 3px; cursor: pointer; font-size: 11px; font-weight: 600; white-space: nowrap; }
        .ait-guide-btn:hover { background: #2271b1; color: #fff; }
        .ait-guide-code { background: #1d2327; color: #50fa7b; padding: 10px 14px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.5; overflow-x: auto; white-space: pre-wrap; margin-top: 8px; display: none; }
        .ait-guide-link { display: inline-block; margin-top: 4px; font-size: 12px; }
        .ait-guide-text { display: block; margin-top: 4px; font-size: 12px; color: #50575e; }
        .ait-guide-ok { color: #00a32a; font-size: 12px; }
    </style>
    <table class="ait-status-table">
        <thead>
            <tr>
                <th style="width: 24%">Tính năng</th>
                <th style="width: 9%">Trạng thái</th>
                <th style="width: 37%">Chi tiết</th>
                <th style="width: 30%">Hướng dẫn cấu hình</th>
            </tr>
        </thead>
        <tbody>
        <?php foreach ($status_items as $group): ?>
            <tr class="ait-status-group"><td colspan="4"><?php echo esc_html($group['group']); ?></td></tr>
            <?php foreach ($group['items'] as $item):
                $badge_class = 'ait-badge-off';
                $badge_text = 'TẮT';
                if ($item['status'] === 'on') { $badge_class = 'ait-badge-on'; $badge_text = 'BẬT'; }
                elseif ($item['status'] === 'error') { $badge_class = 'ait-badge-error'; $badge_text = 'LỖI'; }
                elseif ($item['status'] === 'warn') { $badge_class = 'ait-badge-warn'; $badge_text = 'CẢNH BÁO'; }
                $guide_counter++;
            ?>
            <tr>
                <td><span class="ait-status-icon"><?php echo $item['icon']; ?></span> <?php echo esc_html($item['name']); ?></td>
                <td><span class="ait-badge <?php echo $badge_class; ?>"><?php echo $badge_text; ?></span></td>
                <td class="ait-status-info"><?php echo esc_html($item['info']); ?></td>
                <td>
                    <?php if (empty($item['guide'])): ?>
                        <span class="ait-guide-ok">✅ Đã cấu hình</span>
                    <?php elseif (strpos($item['guide'], 'link:') === 0):
                        // Format: link:URL|Mô tả
                        $parts = explode('|', substr($item['guide'], 5), 2);
                        $link_url = $parts[0];
                        $link_desc = isset($parts[1]) ? $parts[1] : 'Cấu hình';
                    ?>
                        <a href="<?php echo esc_url($link_url); ?>" class="ait-guide-link">👉 <?php echo esc_html($link_desc); ?></a>
                    <?php elseif (strpos($item['guide'], '#') === 0 || strpos($item['guide'], 'sudo') !== false || strpos($item['guide'], 'define(') !== false || strpos($item['guide'], '<IfModule') !== false):
                        // Code block
                    ?>
                        <button class="ait-guide-btn" onclick="var c=document.getElementById('guide-<?php echo $guide_counter; ?>');if(c.style.display==='none'){c.style.display='block';this.textContent='Ẩn'}else{c.style.display='none';this.textContent='📋 Xem cách cấu hình'}">📋 Xem cách cấu hình</button>
                        <pre class="ait-guide-code" id="guide-<?php echo $guide_counter; ?>"><?php echo esc_html($item['guide']); ?></pre>
                    <?php else: ?>
                        <span class="ait-guide-text"><?php echo esc_html($item['guide']); ?></span>
                    <?php endif; ?>
                </td>
            </tr>
            <?php endforeach; ?>
        <?php endforeach; ?>
        </tbody>
    </table>

    <!-- GỢI Ý TỐI ƯU -->
    <?php
    $recommendations = [];

    if ($redis_status !== 'on') {
        if (!class_exists('Redis')) {
            $recommendations[] = ['level' => 'critical', 'title' => 'Cài đặt Redis để đạt tốc độ < 1ms', 'desc' => 'Redis giúp Full Page Cache phản hồi dưới 1ms thay vì phải đọc file từ ổ cứng (5-10ms). Đây là bước nâng cấp hiệu suất lớn nhất bạn có thể làm.', 'impact' => 'Giảm TTFB từ ~50ms xuống < 1ms', 'code' => "# Ubuntu / Debian:\nsudo apt install redis-server php-redis\nsudo systemctl enable redis-server\nsudo systemctl restart apache2\n\n# CentOS / AlmaLinux:\nsudo yum install redis php-pecl-redis\nsudo systemctl enable redis\nsudo systemctl restart php-fpm"];
        } else {
            $recommendations[] = ['level' => 'critical', 'title' => 'Kích hoạt Redis Cache trong wp-config.php', 'desc' => 'Extension php-redis đã cài nhưng chưa cấu hình. Thêm cấu hình Redis vào wp-config.php để kích hoạt Full Page Cache qua Redis.', 'impact' => 'Giảm TTFB từ ~50ms xuống < 1ms', 'code' => "// Thêm vào wp-config.php (trước dòng \"That's all, stop editing!\")\ndefine('AITYPE_REDIS_HOST', '127.0.0.1');\ndefine('AITYPE_REDIS_PORT', 6379);\n// define('AITYPE_REDIS_PASSWORD', 'your-password'); // Nếu Redis có mật khẩu\n// define('AITYPE_REDIS_DB', 0);"];
        }
    }

    if ($wp_cache_status !== 'on') {
        $recommendations[] = ['level' => 'critical', 'title' => 'Bật WP_CACHE để kích hoạt Advanced Cache', 'desc' => 'WP_CACHE chưa được định nghĩa trong wp-config.php. Khi bật, advanced-cache.php sẽ chạy trước cả WordPress core, phục vụ cache trong < 5ms.', 'impact' => 'Tăng tốc 10-50x cho mọi page view', 'code' => "// Thêm vào wp-config.php (trước dòng \"That's all, stop editing!\")\ndefine('WP_CACHE', true);"];
    }
    
    if ($adv_cache_status !== 'on') {
        $recommendations[] = ['level' => 'critical', 'title' => 'Cài đặt Advanced Cache Drop-in', 'desc' => 'File wp-content/advanced-cache.php chưa tồn tại. Bấm "Làm Ấm Tất Cả Cache" ở tab CDN và Cache — plugin sẽ tự động tạo file này.', 'impact' => 'Cache phục vụ trước khi WordPress load', 'code' => null];
    }

    if ($safe_opt_status !== 'on') {
        $recommendations[] = ['level' => 'warning', 'title' => 'Bật lại Safe Optimization (HTML/CSS/JS)', 'desc' => 'Bạn đang tắt tối ưu hóa HTML/CSS/JS. Chức năng này giúp defer CSS render-blocking, preload ảnh LCP, minify HTML, thêm font-display swap. Nếu không bị lỗi giao diện, nên bật lại.', 'impact' => 'Cải thiện 15-30 điểm PageSpeed (LCP, FCP, CLS)', 'code' => null];
    }

    if ($delay_js_status !== 'on') {
        $recommendations[] = ['level' => 'warning', 'title' => 'Bật Delay JS Execution', 'desc' => 'Trì hoãn thực thi JavaScript bên thứ 3 (GTM, Facebook Pixel, Chatbot) giúp giảm đáng kể TBT và tăng điểm PageSpeed. Script chỉ chạy khi user cuộn/click.', 'impact' => 'Giảm TBT 500-2000ms, tăng 10-20 điểm PageSpeed', 'code' => null];
    }

    if ($webp_status !== 'on' && $webp_support === 'on') {
        $recommendations[] = ['level' => 'warning', 'title' => 'Bật WebP Rewrite để giảm dung lượng ảnh', 'desc' => 'Server đã hỗ trợ WebP nhưng chưa bật rewrite. WebP giảm 25-50% kích thước ảnh so với JPEG/PNG, giúp tải trang nhanh hơn đáng kể.', 'impact' => 'Giảm 30-50% dung lượng ảnh, cải thiện LCP', 'code' => null];
    }
    
    if ($webp_support !== 'on') {
        $recommendations[] = ['level' => 'warning', 'title' => 'Cài GD Library hỗ trợ WebP', 'desc' => 'PHP GD chưa hỗ trợ hàm imagewebp(). Cần cài thêm thư viện để chuyển đổi ảnh sang WebP.', 'impact' => 'Mở khóa tính năng WebP auto-convert', 'code' => "# Ubuntu / Debian:\nsudo apt install php-gd\nsudo systemctl restart apache2\n\n# CentOS:\nsudo yum install php-gd\nsudo systemctl restart php-fpm"];
    }

    if ($cdn_status !== 'on') {
        $recommendations[] = ['level' => 'warning', 'title' => 'Cấu hình CDN để phân phối file tĩnh', 'desc' => 'CDN giúp phân phối ảnh, CSS, JS từ server gần người dùng nhất, giảm latency và giảm tải cho server gốc. Bạn có thể dùng Cloudflare (miễn phí) hoặc BunnyCDN.', 'impact' => 'Giảm 50-80% thời gian tải file tĩnh', 'code' => null];
    }

    if ($fpc_files < 10) {
        $recommendations[] = ['level' => 'tip', 'title' => 'Chạy Pre-warm Cache cho toàn bộ website', 'desc' => 'Hiện chỉ có ' . $fpc_files . ' trang được cache. Vào tab "CDN và Cache" bấm "Làm Ấm Tất Cả Cache" để tạo sẵn cache cho mọi bài viết và chuyên mục.', 'impact' => '100% page view đều nhanh từ lần đầu', 'code' => null];
    }

    if ($gzip_status === 'warn' || $gzip_status === 'off') {
        $recommendations[] = ['level' => 'tip', 'title' => 'Bật GZIP Compression ở mức server', 'desc' => 'Plugin đang tự bật GZIP qua PHP, nhưng bật ở mức server (Apache/Nginx) sẽ hiệu quả hơn vì không cần khởi tạo PHP.', 'impact' => 'Giảm 60-80% kích thước HTML/CSS/JS truyền tải', 'code' => "# Apache — thêm vào .htaccess:\n<IfModule mod_deflate.c>\n  AddOutputFilterByType DEFLATE text/html text/css text/javascript\n  AddOutputFilterByType DEFLATE application/javascript application/json\n  AddOutputFilterByType DEFLATE application/xml text/xml\n  AddOutputFilterByType DEFLATE image/svg+xml\n</IfModule>\n\n# Nginx — thêm vào nginx.conf:\ngzip on;\ngzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;\ngzip_min_length 1000;\ngzip_comp_level 6;"];
    }
    
    if ($php_status === 'warn') {
        $recommendations[] = ['level' => 'tip', 'title' => 'Nâng cấp PHP lên 8.1+', 'desc' => 'PHP ' . $php_ver . ' đã cũ và chậm hơn đáng kể so với PHP 8.1+. Nâng cấp PHP là cách miễn phí để tăng 20-40% tốc độ xử lý.', 'impact' => 'Tăng 20-40% tốc độ PHP, bảo mật tốt hơn', 'code' => null];
    }

    if ($redis_status === 'on' && $wp_cache_status === 'on' && $safe_opt_status === 'on' && $delay_js_status === 'on') {
        $recommendations[] = ['level' => 'info', 'title' => '🎉 Website đã được tối ưu rất tốt!', 'desc' => 'Redis Cache, WP_CACHE, Safe Optimization và Delay JS đều đã bật. Website của bạn đang chạy ở hiệu suất gần tối đa.', 'impact' => null, 'code' => null];
    }

    $level_order = ['critical' => 0, 'warning' => 1, 'tip' => 2, 'info' => 3];
    usort($recommendations, function($a, $b) use ($level_order) {
        return ($level_order[$a['level']] ?? 9) - ($level_order[$b['level']] ?? 9);
    });
    
    $level_config = [
        'critical' => ['icon' => '🔴', 'label' => 'CẦN LÀM NGAY', 'border' => '#d63638', 'bg' => '#fcf0f1'],
        'warning'  => ['icon' => '🟡', 'label' => 'NÊN BẬT', 'border' => '#dba617', 'bg' => '#fef8ee'],
        'tip'      => ['icon' => '💡', 'label' => 'GỢI Ý', 'border' => '#2271b1', 'bg' => '#f0f6fc'],
        'info'     => ['icon' => '✅', 'label' => 'TUYỆT VỜI', 'border' => '#00a32a', 'bg' => '#edfcf0'],
    ];
    ?>

    <?php if (!empty($recommendations)): ?>
    <h3 style="margin-top: 5px;">💬 Gợi Ý Tối Ưu (<?php echo count($recommendations); ?> mục)</h3>
    <style>
        .ait-rec { border-left: 4px solid #ccc; padding: 14px 18px; margin-bottom: 12px; border-radius: 0 4px 4px 0; }
        .ait-rec-header { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
        .ait-rec-label { font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 3px; text-transform: uppercase; letter-spacing: 0.3px; }
        .ait-rec-title { font-size: 14px; font-weight: 600; color: #1d2327; }
        .ait-rec-desc { font-size: 13px; color: #50575e; margin-bottom: 6px; line-height: 1.5; }
        .ait-rec-impact { font-size: 12px; color: #2271b1; font-weight: 500; margin-bottom: 8px; }
        .ait-rec-code { background: #1d2327; color: #50fa7b; padding: 12px 16px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; overflow-x: auto; white-space: pre-wrap; position: relative; display: none; margin-top: 8px; }
        .ait-rec-toggle { background: none; border: 1px solid #c3c4c7; color: #2271b1; padding: 2px 10px; border-radius: 3px; cursor: pointer; font-size: 12px; }
        .ait-rec-toggle:hover { background: #f0f6fc; }
    </style>

    <?php foreach ($recommendations as $idx => $rec):
        $cfg = $level_config[$rec['level']] ?? $level_config['tip'];
    ?>
    <div class="ait-rec" style="border-left-color: <?php echo $cfg['border']; ?>; background: <?php echo $cfg['bg']; ?>;">
        <div class="ait-rec-header">
            <span><?php echo $cfg['icon']; ?></span>
            <span class="ait-rec-label" style="background: <?php echo $cfg['border']; ?>; color: #fff;"><?php echo $cfg['label']; ?></span>
            <span class="ait-rec-title"><?php echo esc_html($rec['title']); ?></span>
        </div>
        <div class="ait-rec-desc"><?php echo esc_html($rec['desc']); ?></div>
        <?php if (!empty($rec['impact'])): ?>
            <div class="ait-rec-impact">📈 Tác động: <?php echo esc_html($rec['impact']); ?></div>
        <?php endif; ?>
        <?php if (!empty($rec['code'])): ?>
            <button class="ait-rec-toggle" onclick="var c=document.getElementById('ait-code-<?php echo $idx; ?>');c.style.display=c.style.display==='none'?'block':'none';this.textContent=c.style.display==='none'?'📋 Xem hướng dẫn':'Ẩn'">📋 Xem hướng dẫn</button>
            <pre class="ait-rec-code" id="ait-code-<?php echo $idx; ?>"><?php echo esc_html($rec['code']); ?></pre>
        <?php endif; ?>
    </div>
    <?php endforeach; ?>
    <?php endif; ?>

</div>
