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
    
    // Quét cả metadata sizes nếu có
    if (!empty($metadata['sizes']) && is_array($metadata['sizes'])) {
        foreach ($metadata['sizes'] as $sz => $sinfo) {
            if (!empty($sinfo['file'])) {
                $sf_path = $base_dir . '/' . $sinfo['file'];
                if (file_exists($sf_path) && !in_array($sf_path, $files_to_process)) {
                    $files_to_process[] = $sf_path;
                }
            }
        }
    }

    // Quét trực tiếp thư mục thay vì chỉ dựa vào metadata (Để bắt được các ảnh crop động từ Page Builder)
    if (is_dir($base_dir)) {
        $dir_files = scandir($base_dir);
        if (is_array($dir_files)) {
            $pattern = '/^' . preg_quote($base_name, '/') . '(-\d+x\d+)?\.(jpg|jpeg|png|webp)$/i';
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
    $actions['recrop_cdn'] = '<a href="#" class="clbntb-recrop-single-cdn" data-id="' . $post->ID . '" style="color: #0073aa;">Tạo lại Thumbnail & Sync CDN</a>';
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

        $('.wp-list-table').on('click', '.clbntb-recrop-single-cdn', function(e) {
            e.preventDefault();
            var btn = $(this);
            var id = btn.data('id');
            var originalText = btn.text();
            
            btn.text('Đang crop & đẩy CDN...').css('pointer-events', 'none');
            
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: {
                    action: 'clbntb_regenerate_thumbnails',
                    mode: 'single_attachment',
                    id: id
                },
                success: function(res) {
                    if (res.success) {
                        btn.text('Thành công!').css('color', 'green');
                        setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 2000);
                    } else {
                        btn.text('Lỗi').css('color', 'red');
                        alert(res.data || 'Lỗi tạo thumbnail');
                        setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 3000);
                    }
                },
                error: function() {
                    btn.text('Lỗi mạng').css('color', 'red');
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
// ==========================================
// REGENERATE THUMBNAILS & SYNC CDN ENGINE
// ==========================================

// Hàm lấy động 100% tất cả kích thước crop ảnh được đăng ký bởi WordPress, Theme và Plugins
function clbntb_get_all_registered_crop_sizes() {
    $sizes_map = array();

    // 1. Quét tất cả kích thước ảnh đăng ký trong WordPress
    if (function_exists('wp_get_registered_image_subsizes')) {
        $subsizes = wp_get_registered_image_subsizes();
        if (!empty($subsizes) && is_array($subsizes)) {
            foreach ($subsizes as $sdata) {
                $w = intval(isset($sdata['width']) ? $sdata['width'] : 0);
                $h = intval(isset($sdata['height']) ? $sdata['height'] : 0);
                $c = !empty($sdata['crop']);
                if ($w > 0 && $h > 0) {
                    $sizes_map[$w . 'x' . $h] = array('w' => $w, 'h' => $h, 'crop' => $c);
                }
            }
        }
    }

    // 2. Quét $_wp_additional_image_sizes (Theme Newspaper, Page Builder, WooCommerce...)
    global $_wp_additional_image_sizes;
    $wp_sizes = get_intermediate_image_sizes();
    if (!empty($wp_sizes) && is_array($wp_sizes)) {
        foreach ($wp_sizes as $s) {
            if (isset($_wp_additional_image_sizes[$s])) {
                $w = intval(isset($_wp_additional_image_sizes[$s]['width']) ? $_wp_additional_image_sizes[$s]['width'] : 0);
                $h = intval(isset($_wp_additional_image_sizes[$s]['height']) ? $_wp_additional_image_sizes[$s]['height'] : 0);
                $c = !empty($_wp_additional_image_sizes[$s]['crop']);
                if ($w > 0 && $h > 0) {
                    $sizes_map[$w . 'x' . $h] = array('w' => $w, 'h' => $h, 'crop' => $c);
                }
            }
        }
    }

    // 3. Nếu chưa tìm thấy kích thước nào, bổ sung các kích thước phổ biến
    if (empty($sizes_map)) {
        $defaults = array(
            array('w' => 696, 'h' => 464, 'crop' => true),
            array('w' => 696, 'h' => 442, 'crop' => true),
            array('w' => 324, 'h' => 400, 'crop' => true),
            array('w' => 150, 'h' => 150, 'crop' => true),
            array('w' => 300, 'h' => 200, 'crop' => true)
        );
        foreach ($defaults as $d) {
            $sizes_map[$d['w'] . 'x' . $d['h']] = $d;
        }
    }

    return array_values($sizes_map);
}

// Hàm bắt buộc tạo đầy đủ tất cả kích thước crop ảnh động theo Theme/WordPress
function clbntb_force_generate_all_crops($att_id) {
    $file_path = get_attached_file($att_id);
    if (!$file_path || !file_exists($file_path)) return false;

    $img_info = @getimagesize($file_path);
    if (!$img_info) return false;

    $ext = strtolower(pathinfo($file_path, PATHINFO_EXTENSION));
    $dir = dirname($file_path);
    $filename = pathinfo($file_path, PATHINFO_FILENAME);

    $target_sizes = clbntb_get_all_registered_crop_sizes();

    $src_img = false;
    if (in_array($ext, ['jpg', 'jpeg'])) {
        $src_img = @imagecreatefromjpeg($file_path);
    } elseif ($ext === 'png') {
        $src_img = @imagecreatefrompng($file_path);
    } elseif ($ext === 'webp' && function_exists('imagecreatefromwebp')) {
        $src_img = @imagecreatefromwebp($file_path);
    }

    if (!$src_img) return false;

    $orig_w = imagesx($src_img);
    $orig_h = imagesy($src_img);

    foreach ($target_sizes as $sz) {
        $tw = $sz['w'];
        $th = $sz['h'];
        if ($tw <= 0 || $th <= 0) continue;

        $crop_filename_orig = $filename . '-' . $tw . 'x' . $th . '.' . $ext;
        $crop_filename_webp = $filename . '-' . $tw . 'x' . $th . '.webp';

        $crop_path_orig = $dir . '/' . $crop_filename_orig;
        $crop_path_webp = $dir . '/' . $crop_filename_webp;

        if ($sz['crop']) {
            $aspect_orig = $orig_w / $orig_h;
            $aspect_target = $tw / $th;
            if ($aspect_orig > $aspect_target) {
                $ch = $orig_h;
                $cw = intval($orig_h * $aspect_target);
                $cx = intval(($orig_w - $cw) / 2);
                $cy = 0;
            } else {
                $cw = $orig_w;
                $ch = intval($orig_w / $aspect_target);
                $cx = 0;
                $cy = intval(($orig_h - $ch) / 2);
            }
        } else {
            $ratio = min($tw / $orig_w, $th / $orig_h);
            $tw = intval($orig_w * $ratio);
            $th = intval($orig_h * $ratio);
            $cx = 0;
            $cy = 0;
            $cw = $orig_w;
            $ch = $orig_h;
        }

        if ($tw <= 0 || $th <= 0) continue;

        $dst_img = imagecreatetruecolor($tw, $th);
        if ($ext === 'png' || $ext === 'webp') {
            imagealphablending($dst_img, false);
            imagesavealpha($dst_img, true);
        }

        imagecopyresampled($dst_img, $src_img, 0, 0, $cx, $cy, $tw, $th, $cw, $ch);

        if ($ext === 'png') {
            imagepng($dst_img, $crop_path_orig, 8);
        } elseif (in_array($ext, ['jpg', 'jpeg'])) {
            imagejpeg($dst_img, $crop_path_orig, 85);
        }

        if (function_exists('imagewebp')) {
            imagewebp($dst_img, $crop_path_webp, 82);
        }

        imagedestroy($dst_img);
    }

    imagedestroy($src_img);
    return true;
}

function clbntb_regenerate_attachment_thumbnails_and_sync($att_id) {
    if (!$att_id || get_post_type($att_id) !== 'attachment') {
        return false;
    }

    require_once( ABSPATH . 'wp-admin/includes/image.php' );
    
    $file_path = get_attached_file($att_id);
    
    $need_download = (!$file_path || !file_exists($file_path));
    if (!$need_download && file_exists($file_path)) {
        $info = @getimagesize($file_path);
        if (!$info) {
            @unlink($file_path);
            $need_download = true;
        }
    }

    if ($need_download) {
        $cdn_url = get_option('clbntb_cdn_url');
        $domain = clbntb_get_cdn_domain();
        if (!empty($cdn_url)) {
            $guid = get_the_guid($att_id);
            if (!empty($guid)) {
                $parsed = parse_url($guid);
                $path = isset($parsed['path']) ? $parsed['path'] : '';
                $path = str_replace(
                    array('/wp-content/themes/', '/wp-content/plugins/', '/wp-content/uploads/', '/wp-includes/'),
                    array('/themes/', '/plugins/', '/media/', '/includes/'),
                    $path
                );
                
                $base_cdn = rtrim($cdn_url, '/') . '/' . trim($domain, '/') . $path;
                $candidates = array(
                    $base_cdn,
                    preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $base_cdn),
                    preg_replace('/\.(webp|png)$/i', '.jpg', $base_cdn),
                    preg_replace('/\.(webp|jpg|jpeg)$/i', '.png', $base_cdn)
                );

                foreach ($candidates as $cand_url) {
                    $response = wp_remote_get($cand_url, array('timeout' => 30, 'sslverify' => false));
                    if (!is_wp_error($response) && wp_remote_retrieve_response_code($response) === 200) {
                        $body = wp_remote_retrieve_body($response);
                        if (!empty($body) && strpos($body, '<!doctype') === false && strpos($body, '<html') === false) {
                            wp_mkdir_p(dirname($file_path));
                            file_put_contents($file_path, $body);
                            break;
                        }
                    }
                }
            }
        }
    }

    if (!$file_path || !file_exists($file_path) || !@getimagesize($file_path)) {
        return false;
    }

    // Xóa các file thumbnail cũ trên đĩa cục bộ
    $metadata = wp_get_attachment_metadata($att_id);
    if (!empty($metadata['sizes']) && is_array($metadata['sizes'])) {
        $base_dir = dirname($file_path);
        foreach ($metadata['sizes'] as $size => $size_info) {
            if (!empty($size_info['file'])) {
                $thumb_file = $base_dir . '/' . $size_info['file'];
                if (file_exists($thumb_file)) {
                    @unlink($thumb_file);
                }
                $webp_thumb = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $thumb_file);
                if (file_exists($webp_thumb)) {
                    @unlink($webp_thumb);
                }
            }
        }
    }

    // 1. Tạo lại metadata & crop ảnh theo WordPress
    $new_metadata = wp_generate_attachment_metadata($att_id, $file_path);
    if (empty($new_metadata)) {
        $new_metadata = array();
    }
    wp_update_attachment_metadata($att_id, $new_metadata);

    // 2. Ép buộc cắt tất cả kích thước chuẩn (bao gồm 696x464, 324x400...) bằng GD Engine trực tiếp
    clbntb_force_generate_all_crops($att_id);

    // 3. Đẩy toàn bộ ảnh gốc & các file crop vừa tạo lên CDN
    clbntb_auto_convert_and_sync_cdn($new_metadata, $att_id);

    return true;
}

// Hàm lấy phiên bản Cache buster động tự động cập nhật mỗi khi crop/sync CDN
function clbntb_get_cache_version() {
    $ver = get_option('clbntb_cache_ver');
    if (empty($ver)) {
        $ver = time();
        update_option('clbntb_cache_ver', $ver);
    }
    return $ver;
}

// Cập nhật lại đường dẫn ảnh trong CSDL bài viết sang CDN & WebP mới
function clbntb_update_post_image_urls_to_cdn($post_id) {
    $cdn_url = get_option('clbntb_cdn_url');
    if (empty($cdn_url)) return;

    $domain = clbntb_get_cdn_domain();
    $cdn_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
    $target_media = $cdn_base . '/media/';
    $c_ver = clbntb_get_cache_version();

    $post = get_post($post_id);
    if (!$post) return;

    $content = $post->post_content;
    $updated = false;

    // 1. Thay thế tất cả đường dẫn /wp-content/uploads/ từ bất kỳ domain nào sang CDN /media/
    $pattern_upload = '#https?://[^/"\'\)\s]+/wp-content/uploads/#i';
    if (preg_match($pattern_upload, $content)) {
        $content = preg_replace($pattern_upload, $target_media, $content);
        $updated = true;
    }

    // 2. Thay thế các đường dẫn CDN wp-content/uploads/ thành /media/
    $pattern_cdn_upload = '#' . preg_quote(rtrim($cdn_url, '/'), '#') . '/[^/"\'\)\s]+/wp-content/uploads/#i';
    if (preg_match($pattern_cdn_upload, $content)) {
        $content = preg_replace($pattern_cdn_upload, $target_media, $content);
        $updated = true;
    }

    // 3. Chuyển đổi định dạng .jpg, .jpeg, .png thành .webp trong CDN media nếu bật rewrite_webp
    $pattern_ext = '#' . preg_quote($target_media, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png)(?:\?[^"\'\)\s]*)?#i';
    if (preg_match($pattern_ext, $content)) {
        $content = preg_replace($pattern_ext, $target_media . '$1webp?v=' . $c_ver, $content);
        $updated = true;
    }

    if ($updated) {
        wp_update_post(array(
            'ID' => $post_id,
            'post_content' => $content
        ));
    }

    // 4. Cập nhật postmeta của bài viết (cho Theme Newspaper, Elementor, Page Builder metadata)
    global $wpdb;
    $metas = $wpdb->get_results($wpdb->prepare(
        "SELECT meta_id, meta_key, meta_value FROM $wpdb->postmeta WHERE post_id = %d AND (meta_value LIKE %s OR meta_value LIKE %s OR meta_value LIKE %s)",
        $post_id, '%/wp-content/uploads/%', '%.jpg%', '%.png%'
    ));

    if (!empty($metas)) {
        foreach ($metas as $m) {
            $val = $m->meta_value;
            $new_val = preg_replace('#https?://[^/"\'\)\s]+/wp-content/uploads/#i', $target_media, $val);
            $new_val = preg_replace('#' . preg_quote(rtrim($cdn_url, '/'), '#') . '/[^/"\'\)\s]+/wp-content/uploads/#i', $target_media, $new_val);
            $new_val = preg_replace('#' . preg_quote($target_media, '#') . '([^"\'\)\s]*\.)(jpg|jpeg|png)(?:\?[^"\'\)\s]*)?#i', $target_media . '$1webp?v=' . $c_ver, $new_val);
            if ($new_val !== $val) {
                update_post_meta($post_id, $m->meta_key, maybe_unserialize($new_val));
            }
        }
    }
}

// Hàm crop & sync trực tiếp cho các file ảnh độc lập (Không có Attachment ID trong WordPress)
function clbntb_crop_and_sync_standalone_file($img_url_or_path) {
    $cdn_url = get_option('clbntb_cdn_url');
    $api_key = get_option('clbntb_cdn_api_key', '');
    $domain = clbntb_get_cdn_domain();
    if (empty($cdn_url)) return false;

    $parsed = parse_url($img_url_or_path);
    $path = isset($parsed['path']) ? $parsed['path'] : $img_url_or_path;
    
    $rel_path = preg_replace('#^.*?/(?:wp-content/uploads|media)/#i', '', $path);
    if (empty($rel_path)) return false;

    $upload_dir = wp_upload_dir();
    $base_dir = $upload_dir['basedir'];
    
    $orig_rel_path = preg_replace('/-\d+x\d+(?=\.(?:jpg|jpeg|png|webp))/i', '', $rel_path);
    $local_orig_file = $base_dir . '/' . ltrim($orig_rel_path, '/');

    if (!file_exists($local_orig_file) || !@getimagesize($local_orig_file)) {
        $cdn_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
        $cdn_media_url = $cdn_base . '/media/' . ltrim($orig_rel_path, '/');
        
        $candidates = array(
            $cdn_media_url,
            preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $cdn_media_url),
            preg_replace('/\.(webp|png)$/i', '.jpg', $cdn_media_url),
            preg_replace('/\.(webp|jpg|jpeg)$/i', '.png', $cdn_media_url)
        );

        foreach ($candidates as $cand) {
            $resp = wp_remote_get($cand, array('timeout' => 30, 'sslverify' => false));
            if (!is_wp_error($resp) && wp_remote_retrieve_response_code($resp) === 200) {
                $body = wp_remote_retrieve_body($resp);
                if (!empty($body) && strpos($body, '<!doctype') === false && strpos($body, '<html') === false) {
                    wp_mkdir_p(dirname($local_orig_file));
                    file_put_contents($local_orig_file, $body);
                    break;
                }
            }
        }
    }

    if (!file_exists($local_orig_file) || !@getimagesize($local_orig_file)) {
        return false;
    }

    $ext = strtolower(pathinfo($local_orig_file, PATHINFO_EXTENSION));
    $dir = dirname($local_orig_file);
    $filename = pathinfo($local_orig_file, PATHINFO_FILENAME);

    $target_sizes = clbntb_get_all_registered_crop_sizes();

    $src_img = false;
    if (in_array($ext, ['jpg', 'jpeg'])) {
        $src_img = @imagecreatefromjpeg($local_orig_file);
    } elseif ($ext === 'png') {
        $src_img = @imagecreatefrompng($local_orig_file);
    } elseif ($ext === 'webp' && function_exists('imagecreatefromwebp')) {
        $src_img = @imagecreatefromwebp($local_orig_file);
    }

    if (!$src_img) return false;

    $orig_w = imagesx($src_img);
    $orig_h = imagesy($src_img);

    $cdn_api_url = rtrim($cdn_url, '/') . '/upload';
    $target_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');

    // Upload ảnh gốc lên CDN
    $orig_source_url = 'https://' . $domain . '/wp-content/uploads/' . ltrim($orig_rel_path, '/');
    $orig_target_url = $target_base . '/media/' . ltrim($orig_rel_path, '/');
    $orig_content = @file_get_contents($local_orig_file);
    if (!empty($orig_content)) {
        wp_remote_post($cdn_api_url, array(
            'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
            'body'    => json_encode(array('path' => $orig_source_url, 'target' => $orig_target_url, 'file_base64' => base64_encode($orig_content))),
            'timeout' => 45, 'sslverify' => false
        ));
    }

    foreach ($target_sizes as $sz) {
        $tw = $sz['w'];
        $th = $sz['h'];
        if ($tw <= 0 || $th <= 0) continue;

        $crop_filename_orig = $filename . '-' . $tw . 'x' . $th . '.' . $ext;
        $crop_filename_webp = $filename . '-' . $tw . 'x' . $th . '.webp';

        $crop_path_orig = $dir . '/' . $crop_filename_orig;
        $crop_path_webp = $dir . '/' . $crop_filename_webp;

        if ($sz['crop']) {
            $aspect_orig = $orig_w / $orig_h;
            $aspect_target = $tw / $th;
            if ($aspect_orig > $aspect_target) {
                $ch = $orig_h;
                $cw = intval($orig_h * $aspect_target);
                $cx = intval(($orig_w - $cw) / 2);
                $cy = 0;
            } else {
                $cw = $orig_w;
                $ch = intval($orig_w / $aspect_target);
                $cx = 0;
                $cy = intval(($orig_h - $ch) / 2);
            }
        } else {
            $ratio = min($tw / $orig_w, $th / $orig_h);
            $tw = intval($orig_w * $ratio);
            $th = intval($orig_h * $ratio);
            $cx = 0;
            $cy = 0;
            $cw = $orig_w;
            $ch = $orig_h;
        }

        if ($tw <= 0 || $th <= 0) continue;

        $dst_img = imagecreatetruecolor($tw, $th);
        if ($ext === 'png' || $ext === 'webp') {
            imagealphablending($dst_img, false);
            imagesavealpha($dst_img, true);
        }

        imagecopyresampled($dst_img, $src_img, 0, 0, $cx, $cy, $tw, $th, $cw, $ch);

        if ($ext === 'png') {
            imagepng($dst_img, $crop_path_orig, 8);
        } elseif (in_array($ext, ['jpg', 'jpeg'])) {
            imagejpeg($dst_img, $crop_path_orig, 85);
        }

        if (function_exists('imagewebp')) {
            imagewebp($dst_img, $crop_path_webp, 82);
        }

        imagedestroy($dst_img);

        // Upload crop WebP file lên CDN
        if (file_exists($crop_path_webp)) {
            $crop_rel_webp = ltrim(dirname($orig_rel_path), '/') . '/' . $crop_filename_webp;
            $crop_source_url = 'https://' . $domain . '/wp-content/uploads/' . ltrim($crop_rel_webp, '/');
            $crop_target_url = $target_base . '/media/' . ltrim($crop_rel_webp, '/');
            $crop_data = @file_get_contents($crop_path_webp);
            if (!empty($crop_data)) {
                wp_remote_post($cdn_api_url, array(
                    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
                    'body'    => json_encode(array('path' => $crop_source_url, 'target' => $crop_target_url, 'file_base64' => base64_encode($crop_data))),
                    'timeout' => 45, 'sslverify' => false
                ));
            }
        }
    }

    imagedestroy($src_img);
    return true;
}

function clbntb_regenerate_post_thumbnails_and_sync($post_id) {
    $processed = 0;
    $attachment_ids = array();
    $standalone_urls = array();

    // 1. Featured Image
    $thumb_id = get_post_thumbnail_id($post_id);
    if ($thumb_id) {
        $attachment_ids[] = intval($thumb_id);
    }

    // 2. Attachments attached to this post
    $attachments = get_posts(array(
        'post_parent' => $post_id,
        'post_type' => 'attachment',
        'posts_per_page' => -1,
        'fields' => 'ids'
    ));
    if (!empty($attachments)) {
        foreach ($attachments as $aid) {
            if (!in_array($aid, $attachment_ids)) {
                $attachment_ids[] = intval($aid);
            }
        }
    }

    // 3. Scan post content & postmeta for image URLs
    $post = get_post($post_id);
    if ($post) {
        $content_to_scan = $post->post_content;
        
        global $wpdb;
        $metas = $wpdb->get_col($wpdb->prepare(
            "SELECT meta_value FROM $wpdb->postmeta WHERE post_id = %d AND (meta_value LIKE %s OR meta_value LIKE %s)",
            $post_id, '%/uploads/%', '%/media/%'
        ));
        if (!empty($metas)) {
            $content_to_scan .= ' ' . implode(' ', $metas);
        }

        if (preg_match_all('/wp-image-(\d+)/i', $content_to_scan, $matches)) {
            if (!empty($matches[1])) {
                foreach ($matches[1] as $img_id) {
                    $img_id = intval($img_id);
                    if ($img_id > 0 && !in_array($img_id, $attachment_ids)) {
                        $attachment_ids[] = $img_id;
                    }
                }
            }
        }

        if (preg_match_all('#https?://[^/"\'\)\s]+/(?:wp-content/uploads|media)/[^"\']+\.(?:jpg|jpeg|png|webp)#i', $content_to_scan, $url_matches)) {
            if (!empty($url_matches[0])) {
                foreach ($url_matches[0] as $img_url) {
                    $fname = pathinfo(parse_url($img_url, PHP_URL_PATH), PATHINFO_FILENAME);
                    if (!empty($fname)) {
                        $fname_clean = preg_replace('/-\d+x\d+$/i', '', $fname);
                        $found_id = $wpdb->get_var($wpdb->prepare(
                            "SELECT post_id FROM $wpdb->postmeta WHERE meta_key = '_wp_attached_file' AND meta_value LIKE %s LIMIT 1",
                            '%' . $wpdb->esc_like($fname_clean) . '%'
                        ));
                        if ($found_id && !in_array(intval($found_id), $attachment_ids)) {
                            $attachment_ids[] = intval($found_id);
                        } else {
                            if (!in_array($img_url, $standalone_urls)) {
                                $standalone_urls[] = $img_url;
                            }
                        }
                    }
                }
            }
        }
    }

    // Processing attachments
    foreach ($attachment_ids as $att_id) {
        if (clbntb_regenerate_attachment_thumbnails_and_sync($att_id)) {
            $processed++;
        }
    }

    // Processing standalone files without attachment IDs
    foreach ($standalone_urls as $s_url) {
        if (clbntb_crop_and_sync_standalone_file($s_url)) {
            $processed++;
        }
    }

    // Cập nhật lại đường dẫn ảnh trong CSDL bài viết sang CDN/WebP mới
    clbntb_update_post_image_urls_to_cdn($post_id);

    $permalink = get_permalink($post_id);
    if (!empty($permalink)) {
        clbntb_clear_url_cache($permalink);
    }

    // Xóa cache của các Danh mục (Category) liên quan
    $categories = get_the_category($post_id);
    if (!empty($categories) && is_array($categories)) {
        foreach ($categories as $cat) {
            $cat_link = get_category_link($cat->term_id);
            if (!empty($cat_link)) {
                clbntb_clear_url_cache($cat_link);
            }
        }
    }

    // Xóa cache của Trang chủ (Home)
    clbntb_clear_url_cache(home_url('/'));

    return array(
        'post_id' => $post_id,
        'attachments_found' => count($attachment_ids) + count($standalone_urls),
        'regenerated' => $processed
    );
}

// AJAX Handler for Regenerating Thumbnails
add_action('wp_ajax_clbntb_regenerate_thumbnails', 'clbntb_regenerate_thumbnails_callback');
function clbntb_regenerate_thumbnails_callback() {
    if (!current_user_can('upload_files')) {
        wp_send_json_error('Bạn không có quyền thực hiện.');
    }

    // Tự động nâng phiên bản cache buster timestamp để Cloudflare Edge xả cache cũ lập tức
    update_option('clbntb_cache_ver', time());

    $mode = isset($_POST['mode']) ? sanitize_text_field($_POST['mode']) : '';
    $id = isset($_POST['id']) ? intval($_POST['id']) : 0;

    if ($mode === 'single_attachment') {
        if (!$id) wp_send_json_error('ID Ảnh không hợp lệ');
        $res = clbntb_regenerate_attachment_thumbnails_and_sync($id);
        if ($res) {
            $parent_id = wp_get_post_parent_id($id);
            if ($parent_id > 0) {
                clbntb_update_post_image_urls_to_cdn($parent_id);
            }
            clbntb_clear_all_html_cache();
            wp_send_json_success('Đã tạo lại thumbnail, đồng bộ CDN và cập nhật CSDL thành công cho Ảnh ID: ' . $id);
        } else {
            wp_send_json_error('Không thể tạo lại thumbnail cho Ảnh ID: ' . $id);
        }
    } elseif ($mode === 'single_post') {
        if (!$id) wp_send_json_error('ID Bài viết không hợp lệ');
        $res = clbntb_regenerate_post_thumbnails_and_sync($id);
        clbntb_clear_all_html_cache();
        wp_send_json_success('Bài viết ID ' . $id . ': Tìm thấy ' . $res['attachments_found'] . ' ảnh, đã tạo lại thumbnail, đẩy CDN & cập nhật CSDL thành công ' . $res['regenerated'] . ' ảnh.');
    } elseif ($mode === 'batch_posts') {
        if (isset($_POST['is_first']) && $_POST['is_first'] == 1) {
            $posts = get_posts(array(
                'post_type' => array('post', 'page'),
                'post_status' => 'publish',
                'posts_per_page' => -1,
                'fields' => 'ids'
            ));
            update_option('_clbntb_recrop_queue', $posts, false);
        }

        $queue = get_option('_clbntb_recrop_queue', array());
        if (empty($queue)) {
            clbntb_clear_all_html_cache();
            wp_send_json_success(array('done' => true, 'message' => 'Đã hoàn tất tạo lại thumbnail và đồng bộ CDN cho TẤT CẢ bài viết! (Đã tự động làm mới toàn bộ Full Page Cache)'));
        }

        $batch_size = 3;
        $batch = array_splice($queue, 0, $batch_size);
        update_option('_clbntb_recrop_queue', $queue, false);

        $total_regenerated = 0;
        foreach ($batch as $pid) {
            $res = clbntb_regenerate_post_thumbnails_and_sync($pid);
            $total_regenerated += $res['regenerated'];
        }

        wp_send_json_success(array('done' => false, 'processed_posts' => count($batch), 'regenerated_images' => $total_regenerated, 'remaining' => count($queue)));
    } else {
        wp_send_json_error('Chế độ không hợp lệ');
    }
}

// Thêm nút "Tạo lại Thumbnail & Sync CDN" vào Danh sách Bài Viết (Posts List)
add_filter('post_row_actions', 'clbntb_add_post_recrop_action', 10, 2);
add_filter('page_row_actions', 'clbntb_add_post_recrop_action', 10, 2);
function clbntb_add_post_recrop_action($actions, $post) {
    if (get_option('clbntb_cdn_url') == '') return $actions;
    $actions['recrop_cdn'] = '<a href="#" class="clbntb-recrop-post-cdn" data-id="' . $post->ID . '" style="color: #0073aa;">Tạo lại Thumbnail & Sync CDN</a>';
    return $actions;
}

add_action('admin_footer-edit.php', 'clbntb_post_recrop_js');
function clbntb_post_recrop_js() {
    ?>
    <script>
    jQuery(document).ready(function($) {
        $('.wp-list-table').on('click', '.clbntb-recrop-post-cdn', function(e) {
            e.preventDefault();
            var btn = $(this);
            var id = btn.data('id');
            var originalText = btn.text();
            
            btn.text('Đang crop & đẩy CDN...').css('pointer-events', 'none');
            
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: {
                    action: 'clbntb_regenerate_thumbnails',
                    mode: 'single_post',
                    id: id
                },
                success: function(res) {
                    if (res.success) {
                        btn.text('Hoàn tất!').css('color', 'green');
                        alert(res.data);
                        setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 2000);
                    } else {
                        btn.text('Lỗi').css('color', 'red');
                        alert(res.data || 'Unknown Error');
                        setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 3000);
                    }
                },
                error: function() {
                    btn.text('Lỗi mạng').css('color', 'red');
                    setTimeout(function() { btn.text(originalText).css('pointer-events', 'auto'); }, 3000);
                }
            });
        });
    });
    </script>
    <?php
}

