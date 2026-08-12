<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// Convert HTML to Markdown (Basic)
function clbntb_html_to_markdown($html) {
    // Remove scripts and styles
    $html = preg_replace('/<script\b[^>]*>(.*?)<\/script>/is', "", $html);
    $html = preg_replace('/<style\b[^>]*>(.*?)<\/style>/is', "", $html);

    // Headings
    $html = preg_replace_callback('/<h([1-6])[^>]*>(.*?)<\/h\1>/is', function($matches) {
        return "\n\n" . str_repeat('#', $matches[1]) . ' ' . trim(strip_tags($matches[2])) . "\n\n";
    }, $html);
    
    // Bold / Strong
    $html = preg_replace('/<(b|strong)[^>]*>(.*?)<\/\1>/is', '**$2**', $html);
    
    // Italics / Em
    $html = preg_replace('/<(i|em)[^>]*>(.*?)<\/\1>/is', '*$2*', $html);
    
    // Links
    $html = preg_replace_callback('/<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>/is', function($matches) {
        return '[' . trim(strip_tags($matches[2])) . '](' . $matches[1] . ')';
    }, $html);
    
    // Images
    $html = preg_replace_callback('/<img[^>]+src="([^"]+)"(?:[^>]*alt="([^"]*)")?[^>]*>/is', function($matches) {
        $alt = isset($matches[2]) ? $matches[2] : '';
        return '![' . $alt . '](' . $matches[1] . ')';
    }, $html);
    
    // Lists
    $html = preg_replace('/<ul[^>]*>(.*?)<\/ul>/is', "$1", $html);
    $html = preg_replace('/<ol[^>]*>(.*?)<\/ol>/is', "$1", $html);
    $html = preg_replace('/<li[^>]*>(.*?)<\/li>/is', "- $1\n", $html);
    
    // Paragraphs
    $html = preg_replace('/<p[^>]*>(.*?)<\/p>/is', "$1\n\n", $html);
    
    // Tables -> Markdown Tables
    $html = preg_replace_callback('/<table[^>]*>(.*?)<\/table>/is', function($matches) {
        $tableContent = $matches[1];
        preg_match_all('/<tr[^>]*>(.*?)<\/tr>/is', $tableContent, $rows);
        if (empty($rows[0])) return '';
        
        $mdTable = "\n\n";
        $isFirstRow = true;
        foreach ($rows[1] as $rowContent) {
            preg_match_all('/<(td|th)[^>]*>(.*?)<\/\1>/is', $rowContent, $cells);
            if (empty($cells[0])) continue;
            
            $mdRow = "|";
            foreach ($cells[2] as $cellText) {
                // Remove line breaks inside cell
                $cleanCell = trim(preg_replace('/\s+/', ' ', strip_tags($cellText)));
                $mdRow .= " " . $cleanCell . " |";
            }
            $mdTable .= $mdRow . "\n";
            
            if ($isFirstRow) {
                $mdTable .= "|";
                for ($i = 0; $i < count($cells[2]); $i++) {
                    $mdTable .= "---|";
                }
                $mdTable .= "\n";
                $isFirstRow = false;
            }
        }
        return $mdTable . "\n\n";
    }, $html);

    // Line breaks
    $html = preg_replace('/<br\s*\/?>/i', "\n", $html);
    
    // Strip other tags
    $html = strip_tags($html);
    
    // Fix spacing
    $html = preg_replace('/[ \t]+/', ' ', $html);
    $html = preg_replace('/\n{3,}/', "\n\n", $html);
    
    return trim($html);
}

// Build Cache AJAX
add_action('wp_ajax_clbntb_build_cache', 'clbntb_build_cache_callback');
function clbntb_build_cache_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Bạn không có quyền thực hiện việc này.');
    }

    $upload_dir = wp_upload_dir();
    $cache_dir = $upload_dir['basedir'] . '/ai-type-cache/md';
    if (!file_exists($cache_dir)) {
        wp_mkdir_p($cache_dir);
    }

    $args = array(
        'post_type' => array('post', 'page'),
        'post_status' => 'publish',
        'posts_per_page' => -1,
    );
    $posts = get_posts($args);

    $count = 0;
    foreach ($posts as $p) {
        $md = clbntb_html_to_markdown($p->post_content);
        file_put_contents($cache_dir . '/post-' . $p->ID . '.md', $md);
        $count++;
    }

    wp_send_json_success('Đã tạo cache Markdown cho ' . $count . ' bài viết thành công!');
}

// Clear HTML Cache AJAX
add_action('wp_ajax_clbntb_clear_html_cache', 'clbntb_clear_html_cache_callback');
function clbntb_clear_html_cache_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Bạn không có quyền thực hiện việc này.');
    }

    clbntb_clear_all_html_cache();
    wp_send_json_success('Đã xóa toàn bộ HTML Full Page Cache thành công!');
}

// Convert images to WebP
add_action('wp_ajax_clbntb_convert_webp', 'clbntb_convert_webp_callback');
function clbntb_convert_webp_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Bạn không có quyền thực hiện việc này.');
    }

    if (!function_exists('imagewebp')) {
        wp_send_json_error('Máy chủ của bạn không hỗ trợ hàm imagewebp (PHP GD). Vui lòng liên hệ hosting để bật tiện ích này.');
    }

    $upload_dir = wp_upload_dir();
    $base_dir = $upload_dir['basedir'];
    $base_url = $upload_dir['baseurl'];
    
    if (isset($_POST['is_first']) && $_POST['is_first'] == 1) {
        $all_files = [];
        try {
            $directory = new RecursiveDirectoryIterator($base_dir, RecursiveDirectoryIterator::SKIP_DOTS);
            $iterator = new RecursiveIteratorIterator($directory);
            foreach ($iterator as $file) {
                if ($file->isFile()) {
                    $ext = strtolower($file->getExtension());
                    if (in_array($ext, ['jpg', 'jpeg', 'png'])) {
                        $all_files[] = $file->getPathname();
                    }
                }
            }
        } catch (Exception $e) {}
        
        update_option('_clbntb_webp_scan_queue', $all_files, false);
    }
    
    $queue = get_option('_clbntb_webp_scan_queue', []);
    
    if (empty($queue)) {
        wp_send_json_success(['done' => true, 'message' => 'Hoàn thành quét thư mục.']);
    }

    $cdn_url = get_option('clbntb_cdn_url');
    $api_key = get_option('clbntb_cdn_api_key', '');
    $domain = clbntb_get_cdn_domain();
    $cdn_api_url = rtrim($cdn_url, '/') . '/upload';
    $target_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
    $push_to_cdn = !empty($cdn_url);
    
    $batch_size = 20;
    $files_to_process = array_splice($queue, 0, $batch_size);
    update_option('_clbntb_webp_scan_queue', $queue, false);
    
    $processed_count = 0;
    
    foreach ($files_to_process as $path) {
        if (!file_exists($path)) continue;
        
        $webp_path = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $path);
        
        $source_url = str_replace($base_dir, $base_url, $path);
        $parsed = parse_url($source_url);
        $url_path = isset($parsed['path']) ? $parsed['path'] : '';
        $url_path = str_replace(
            array('/wp-content/themes/', '/wp-content/plugins/', '/wp-content/uploads/', '/wp-includes/'),
            array('/themes/', '/plugins/', '/media/', '/includes/'),
            $url_path
        );
        $target_url = $target_base . $url_path;
        $webp_target_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $target_url);

        $orig_exists_cdn = false;
        $webp_exists_cdn = false;

        if ($push_to_cdn) {
            $force_overwrite = isset($_POST['force']) && $_POST['force'] == 1;
            if (!$force_overwrite) {
                // Sử dụng GET với Range thay vì HEAD để đọc 15 byte đầu tiên, nhằm phát hiện lỗi "ảnh bị lưu nhầm thành trang HTML 404"
                $head_webp = wp_remote_get($webp_target_url, array('timeout' => 5, 'sslverify' => false, 'headers' => array('Range' => 'bytes=0-14')));
                if (!is_wp_error($head_webp) && (wp_remote_retrieve_response_code($head_webp) == 200 || wp_remote_retrieve_response_code($head_webp) == 206)) {
                    $body = strtolower(wp_remote_retrieve_body($head_webp));
                    if (strpos($body, '<!doctype') === false && strpos($body, '<html') === false) {
                        $webp_exists_cdn = true; // Là file ảnh thật sự (hoặc không phải HTML), bỏ qua upload
                    }
                }
            }
            
            $head_orig = wp_remote_head($target_url, array('timeout' => 5, 'sslverify' => false));
            if (!is_wp_error($head_orig) && wp_remote_retrieve_response_code($head_orig) == 200) {
                $orig_exists_cdn = true;
            }
        }
        
        if (!$orig_exists_cdn && $push_to_cdn) {
            wp_remote_post($cdn_api_url, array(
                'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
                'body'    => json_encode(array('path' => $source_url, 'target' => $target_url, 'file_base64' => base64_encode(file_get_contents($path)))),
                'timeout' => 45, 'sslverify' => false
            ));
        }

        if (!$webp_exists_cdn) {
            if (!file_exists($webp_path)) {
                $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
                $img = null;
                if ($ext === 'png') {
                    $img = @imagecreatefrompng($path);
                    if ($img) {
                        imagepalettetotruecolor($img);
                        imagealphablending($img, true);
                        imagesavealpha($img, true);
                    }
                } else {
                    $img = @imagecreatefromjpeg($path);
                }
                
                if ($img !== false && $img !== null) {
                    @imagewebp($img, $webp_path, 80);
                    imagedestroy($img);
                }
            }
            
            if (file_exists($webp_path) && $push_to_cdn) {
                $webp_source_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $source_url);
                $res_webp = wp_remote_post($cdn_api_url, array(
                    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
                    'body'    => json_encode(array('path' => $webp_source_url, 'target' => $webp_target_url, 'file_base64' => base64_encode(file_get_contents($webp_path)))),
                    'timeout' => 45, 'sslverify' => false
                ));
                if (!is_wp_error($res_webp)) {
                    $result_webp = json_decode(wp_remote_retrieve_body($res_webp), true);
                    if (!isset($result_webp['error'])) {
                        @unlink($webp_path); // Xóa bản WebP cục bộ để tiết kiệm dung lượng
                    }
                }
            }
        } else {
            // Đã có trên CDN -> Xóa WebP cục bộ nếu tồn tại
            if (file_exists($webp_path)) {
                @unlink($webp_path);
            }
        }
        $processed_count++;
    }

    wp_send_json_success(['done' => false, 'processed' => $processed_count]);
}



// Xóa toàn bộ ảnh WebP cục bộ
add_action('wp_ajax_clbntb_clean_webp', 'clbntb_clean_webp_callback');
function clbntb_clean_webp_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Bạn không có quyền thực hiện việc này.');
    }

    $upload_dir = wp_upload_dir();
    $base_dir = $upload_dir['basedir'];
    
    if (!file_exists($base_dir)) {
        wp_send_json_error('Không tìm thấy thư mục uploads.');
    }
    
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($base_dir));
    $count = 0;
    
    foreach ($it as $file) {
        if ($file->isFile() && strtolower($file->getExtension()) === 'webp') {
            $path = $file->getRealPath();
            @unlink($path);
            $count++;
        }
    }
    
    wp_send_json_success("Đã dọn dẹp thành công $count ảnh WebP khỏi server!");
}

// Hàm Xóa toàn bộ HTML Cache dùng chung (Redis + File)
function clbntb_clear_all_html_cache() {
    // Xóa Redis cache
    if (class_exists('CLBNTB_Redis')) {
        $redis = CLBNTB_Redis::instance();
        if ($redis->is_available()) {
            $redis->flush_all();
        }
    }
    
    // Xóa file cache
    $upload_dir = wp_upload_dir();
    $html_cache_dir = $upload_dir['basedir'] . '/ai-type-cache/html';
    if (file_exists($html_cache_dir)) {
        $files = glob($html_cache_dir . '/*');
        if (is_array($files)) {
            foreach ($files as $file) {
                if (is_file($file)) {
                    unlink($file);
                }
            }
        }
    }
}

// Hàm xóa Cache theo mục tiêu (Targeted Invalidation) - Redis + File
function clbntb_clear_url_cache($url) {
    if (empty($url)) return;
    $parsed_url = parse_url($url);
    if (!isset($parsed_url['host']) || !isset($parsed_url['path'])) return;
    
    $path = $parsed_url['path'];
    if (isset($parsed_url['query'])) {
        $path .= '?' . $parsed_url['query'];
    }
    
    $base_key = md5($parsed_url['host'] . $path);
    
    // Xóa Redis cache theo pattern (bao gồm bản khách + user + gzip)
    if (class_exists('CLBNTB_Redis')) {
        $redis = CLBNTB_Redis::instance();
        if ($redis->is_available()) {
            $redis->delete_pattern($base_key . '*');
        }
    }
    
    // Xóa file cache
    $upload_dir = wp_upload_dir();
    $html_cache_dir = $upload_dir['basedir'] . '/ai-type-cache/html';
    
    if (file_exists($html_cache_dir)) {
        $files = glob($html_cache_dir . '/' . $base_key . '*');
        if (is_array($files)) {
            foreach ($files as $file) {
                if (is_file($file)) {
                    unlink($file);
                }
            }
        }
    }
}

// Thêm nút Xóa Cache vào thanh Admin Bar
add_action('admin_bar_menu', 'clbntb_add_admin_bar_clear_cache', 100);
function clbntb_add_admin_bar_clear_cache($admin_bar) {
    if (!current_user_can('manage_options')) return;
    
    $admin_bar->add_menu(array(
        'id'    => 'clbntb-clear-cache',
        'title' => '⚡ Xóa AI Cache',
        'href'  => wp_nonce_url(admin_url('admin-post.php?action=clbntb_clear_all_cache'), 'clbntb_clear_cache'),
        'meta'  => array(
            'title' => 'Xóa toàn bộ bộ nhớ đệm Full Page Cache',
        ),
    ));
}

// Xử lý sự kiện click Xóa Cache từ Admin Bar
add_action('admin_post_clbntb_clear_all_cache', 'clbntb_handle_admin_bar_clear_cache');
function clbntb_handle_admin_bar_clear_cache() {
    if (isset($_GET['_wpnonce']) && wp_verify_nonce($_GET['_wpnonce'], 'clbntb_clear_cache') && current_user_can('manage_options')) {
        clbntb_clear_all_html_cache();
    }
    wp_redirect(wp_get_referer() ? wp_get_referer() : home_url());
    exit;
}

// Tự động Xóa Cache khi thay đổi Menu, Chuyên mục, Giao diện
add_action('wp_update_nav_menu', 'clbntb_clear_all_html_cache');
add_action('edit_term', 'clbntb_clear_all_html_cache');
add_action('create_term', 'clbntb_clear_all_html_cache');
add_action('delete_term', 'clbntb_clear_all_html_cache');
add_action('switch_theme', 'clbntb_clear_all_html_cache');

// Xóa cache theo URL khi có bình luận
add_action('comment_post', 'clbntb_clear_comment_post_cache', 10, 3);
add_action('transition_comment_status', 'clbntb_clear_comment_status_cache', 10, 3);

function clbntb_clear_comment_post_cache($comment_ID, $comment_approved, $commentdata) {
    if (isset($commentdata['comment_post_ID'])) {
        clbntb_clear_url_cache(get_permalink($commentdata['comment_post_ID']));
    }
}
function clbntb_clear_comment_status_cache($new_status, $old_status, $comment) {
    if (isset($comment->comment_post_ID)) {
        clbntb_clear_url_cache(get_permalink($comment->comment_post_ID));
    }
}

// Hook to save post
add_action('save_post', 'clbntb_update_post_cache', 10, 3);
function clbntb_update_post_cache($post_id, $post, $update) {
    if (wp_is_post_revision($post_id) || !in_array($post->post_type, array('post', 'page')) || $post->post_status !== 'publish') {
        return;
    }
    
    $upload_dir = wp_upload_dir();
    $cache_dir = $upload_dir['basedir'] . '/ai-type-cache/md';
    if (!file_exists($cache_dir)) {
        wp_mkdir_p($cache_dir);
    }
    
    $md = clbntb_html_to_markdown($post->post_content);
    file_put_contents($cache_dir . '/post-' . $post_id . '.md', $md);

    // Bắn tỉa: Xóa cache của bài viết hiện tại và trang chủ
    clbntb_clear_url_cache(get_permalink($post_id));
    clbntb_clear_url_cache(home_url('/'));
}

// Sync Media to CDN


add_action('wp_ajax_clbntb_reset_webp_sync', 'clbntb_reset_webp_sync_callback');
function clbntb_reset_webp_sync_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Không có quyền!');
    }

    global $wpdb;
    $wpdb->query("DELETE FROM $wpdb->postmeta WHERE meta_key = '_clbntb_webp_converted'");

    wp_send_json_success('Đã reset bộ nhớ. Hệ thống sẽ tự động quét lại từ đầu ngay bây giờ...');
}
// Tự động convert WebP và đẩy lên CDN khi upload ảnh mới
add_filter('wp_generate_attachment_metadata', 'clbntb_auto_convert_and_sync_cdn', 10, 2);
function clbntb_auto_convert_and_sync_cdn($metadata, $attachment_id) {
    $file_path = get_attached_file($attachment_id);
    if (!$file_path || !file_exists($file_path)) return $metadata;
    
    $files_to_process = [$file_path];
    $base_dir = dirname($file_path);
    $base_name = pathinfo($file_path, PATHINFO_FILENAME);
    
    // Quét trực tiếp thư mục thay vì chỉ dựa vào metadata (Để bắt được các ảnh crop động từ Page Builder)
    if (is_dir($base_dir)) {
        $dir_files = scandir($base_dir);
        if (is_array($dir_files)) {
            $pattern = '/^' . preg_quote($base_name, '/') . '(-\d+x\d+)?\.(jpg|jpeg|png)$/i';
            foreach ($dir_files as $f) {
                if (preg_match($pattern, $f)) {
                    $f_path = $base_dir . '/' . $f;
                    if (!in_array($f_path, $files_to_process)) {
                        $files_to_process[] = $f_path;
                    }
                }
            }
        }
    }
    
    $cdn_url = get_option('clbntb_cdn_url');
    $api_key = get_option('clbntb_cdn_api_key', '');
    $domain = clbntb_get_cdn_domain();
    $cdn_api_url = rtrim($cdn_url, '/') . '/upload';
    $target_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
    $push_to_cdn = !empty($cdn_url);
    
    $upload_dir = wp_upload_dir();
    $base_url = $upload_dir['baseurl'];
    $base_dir_path = $upload_dir['basedir'];

    foreach ($files_to_process as $fp) {
        if (!file_exists($fp)) continue;
        
        $ext = strtolower(pathinfo($fp, PATHINFO_EXTENSION));
        $webp_path = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $fp);
        
        // 1. Convert to WebP
        if (in_array($ext, ['jpg', 'jpeg', 'png']) && function_exists('imagewebp') && !file_exists($webp_path)) {
            if ($ext === 'png') {
                $img = @imagecreatefrompng($fp);
                if ($img) {
                    imagepalettetotruecolor($img);
                    imagealphablending($img, true);
                    imagesavealpha($img, true);
                }
            } else {
                $img = @imagecreatefromjpeg($fp);
            }
            if (isset($img) && $img !== false) {
                imagewebp($img, $webp_path, 80);
                imagedestroy($img);
            }
        }
        
        // 2. Push to CDN
        if ($push_to_cdn) {
            // Source URL
            $source_url = str_replace($base_dir_path, $base_url, $fp);
            
            $parsed = parse_url($source_url);
            $path = $parsed['path'] ?? '';
            $path = str_replace(
                array('/wp-content/themes/', '/wp-content/plugins/', '/wp-content/uploads/', '/wp-includes/'),
                array('/themes/', '/plugins/', '/media/', '/includes/'),
                $path
            );
            $target_url = $target_base . $path;
            
            // Upload Original
            wp_remote_post($cdn_api_url, array(
                'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
                'body'    => json_encode(array('path' => $source_url, 'target' => $target_url, 'file_base64' => base64_encode(file_get_contents($fp)))),
                'timeout' => 45, 'sslverify' => false
            ));
            
            // Upload WebP
            if (file_exists($webp_path) && $webp_path !== $fp) {
                $webp_source_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $source_url);
                $webp_target_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $target_url);
                $res_webp = wp_remote_post($cdn_api_url, array(
                    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
                    'body'    => json_encode(array('path' => $webp_source_url, 'target' => $webp_target_url, 'file_base64' => base64_encode(file_get_contents($webp_path)))),
                    'timeout' => 45, 'sslverify' => false
                ));
                if (!is_wp_error($res_webp)) {
                    $result_webp = json_decode(wp_remote_retrieve_body($res_webp), true);
                    if (!isset($result_webp['error'])) {
                        @unlink($webp_path); // Xóa WebP cục bộ
                    }
                }
            }
        }
    }
    
    if ($push_to_cdn) {
        update_post_meta($attachment_id, '_clbntb_cdn_synced', '1');
        update_post_meta($attachment_id, '_clbntb_webp_converted', '1');
    }
    
    return $metadata;
}

// Thêm nút Upload lên CDN vào Media Library
add_filter('media_row_actions', 'clbntb_add_cdn_upload_action', 10, 2);
function clbntb_add_cdn_upload_action($actions, $post) {
    if (get_option('clbntb_cdn_url') == '') return $actions;

    $synced = get_post_meta($post->ID, '_clbntb_webp_converted', true);
    if (!$synced) {
        $actions['upload_cdn'] = '<a href="#" class="clbntb-upload-cdn" data-id="' . $post->ID . '" style="color: #d63638; font-weight: bold;">Upload lên CDN</a>';
    } else {
        $actions['upload_cdn'] = '<a href="#" class="clbntb-upload-cdn" data-id="' . $post->ID . '" style="color: #2271b1;">Upload lại lên CDN</a>';
    }
    return $actions;
}

add_action('admin_footer-upload.php', 'clbntb_cdn_upload_js');
function clbntb_cdn_upload_js() {
    ?>
    <script>
    jQuery(document).ready(function($) {
        $('.wp-list-table').on('click', '.clbntb-upload-cdn', function(e) {
            e.preventDefault();
            var btn = $(this);
            var id = btn.data('id');
            var originalText = btn.text();
            
            btn.text('Đang tải lên...').css('pointer-events', 'none');
            
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: {
                    action: 'clbntb_manual_cdn_upload',
                    attachment_id: id,
                    _ajax_nonce: '<?php echo wp_create_nonce("clbntb_manual_cdn"); ?>'
                },
                success: function(res) {
                    if (res.success) {
                        btn.text('Thành công!').css('color', 'green');
                        setTimeout(function() { btn.text('Upload lại lên CDN').css('color', '#2271b1').css('pointer-events', 'auto'); }, 2000);
                    } else {
                        btn.text('Lỗi: ' + (res.data || 'Unknown')).css('color', 'red');
                        setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 3000);
                    }
                },
                error: function() {
                    btn.text('Lỗi mạng!').css('color', 'red');
                    setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 3000);
                }
            });
        });
    });
    </script>
    <?php
}

add_action('wp_ajax_clbntb_manual_cdn_upload', 'clbntb_manual_cdn_upload_callback');
function clbntb_manual_cdn_upload_callback() {
    check_ajax_referer('clbntb_manual_cdn');
    if (!current_user_can('upload_files')) {
        wp_send_json_error('Không có quyền');
    }
    
    $att_id = intval($_POST['attachment_id']);
    if (!$att_id) wp_send_json_error('ID không hợp lệ');
    
    $metadata = wp_get_attachment_metadata($att_id);
    clbntb_auto_convert_and_sync_cdn($metadata, $att_id);
    
    wp_send_json_success('Upload thành công');
}

// Pre-Warm HTML Cache AJAX Engine
add_action('wp_ajax_clbntb_prewarm_cache', 'clbntb_prewarm_cache_callback');
function clbntb_prewarm_cache_callback() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error('Bạn không có quyền thực hiện việc này.');
    }

    if (isset($_POST['is_first']) && $_POST['is_first'] == 1) {
        $urls = array(home_url('/'));
        
        $posts = get_posts(array(
            'post_type' => array('post', 'page'),
            'post_status' => 'publish',
            'posts_per_page' => -1,
            'fields' => 'ids'
        ));
        
        foreach ($posts as $id) {
            $link = get_permalink($id);
            if (!empty($link) && !in_array($link, $urls)) {
                $urls[] = $link;
            }
        }

        $cats = get_categories(array('hide_empty' => false));
        foreach ($cats as $cat) {
            $link = get_category_link($cat->term_id);
            if (!empty($link) && !in_array($link, $urls)) {
                $urls[] = $link;
            }
        }

        update_option('_clbntb_prewarm_queue', $urls, false);
    }

    $queue = get_option('_clbntb_prewarm_queue', array());
    if (empty($queue)) {
        wp_send_json_success(array('done' => true, 'message' => 'Hoàn tất làm ấm toàn bộ bộ nhớ đệm Siêu Tốc cho website!'));
    }

    $batch_size = 5;
    $urls_to_process = array_splice($queue, 0, $batch_size);
    update_option('_clbntb_prewarm_queue', $queue, false);

    $success_count = 0;
    foreach ($urls_to_process as $url) {
        $resp = wp_remote_get($url, array(
            'timeout' => 10,
            'sslverify' => false,
            'headers' => array('User-Agent' => 'AITypePrewarmer/1.0')
        ));
        if (!is_wp_error($resp)) {
            $success_count++;
        }
    }

    wp_send_json_success(array('done' => false, 'processed' => $success_count, 'remaining' => count($queue)));
}

// Tự động kiểm tra và duy trì advanced-cache.php
function clbntb_deploy_advanced_cache() {
    $src = CLBNTB_PATH . 'inc/advanced-cache.php';
    $dst = WP_CONTENT_DIR . '/advanced-cache.php';
    if (file_exists($src) && (!file_exists($dst) || md5_file($src) !== md5_file($dst))) {
        @copy($src, $dst);
    }
    
    $wp_config = ABSPATH . 'wp-config.php';
    if (file_exists($wp_config) && is_writable($wp_config)) {
        $content = file_get_contents($wp_config);
        if (strpos($content, "'WP_CACHE'") === false && strpos($content, '"WP_CACHE"') === false) {
            $content = preg_replace('/(<\?php)/i', "$1\ndefine('WP_CACHE', true);", $content, 1);
            @file_put_contents($wp_config, $content);
        }
    }
}
add_action('admin_init', 'clbntb_deploy_advanced_cache');

