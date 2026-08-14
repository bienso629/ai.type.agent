<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

if (defined('AITYPE_LICENSE_INVALID')) {
    echo '<div class="wrap"><h1>🛑 Tính năng bị khóa</h1><p style="font-size: 16px;">Vui lòng nhập mã bản quyền hợp lệ tại trang cấu hình chính để sử dụng chức năng này.</p></div>';
    return;
}

if (isset($_POST['submit_cdn'])) {
    update_option('clbntb_cdn_url', sanitize_text_field($_POST['clbntb_cdn_url']));
    // Bỏ update_option cdn_domain để khách không tự đổi được
    update_option('clbntb_cdn_api_key', sanitize_text_field($_POST['clbntb_cdn_api_key']));
    echo '<div class="updated notice is-dismissible"><p>Đã lưu cấu hình CDN.</p></div>';
}

if (isset($_POST['submit_optimization'])) {
    if (isset($_POST['clbntb_disable_optimization'])) {
        update_option('clbntb_disable_optimization', '1');
    } else {
        delete_option('clbntb_disable_optimization');
    }
    
    if (isset($_POST['clbntb_delay_js'])) {
        update_option('clbntb_delay_js', '1');
    } else {
        update_option('clbntb_delay_js', '0');
    }
    
    if (isset($_POST['clbntb_enable_user_cache'])) {
        update_option('clbntb_enable_user_cache', '1');
    } else {
        delete_option('clbntb_enable_user_cache');
    }
    
    if (isset($_POST['clbntb_rewrite_webp'])) {
        update_option('clbntb_rewrite_webp', '1');
    } else {
        delete_option('clbntb_rewrite_webp');
    }
    
    if (isset($_POST['clbntb_anti_cls'])) {
        update_option('clbntb_anti_cls', '1');
    } else {
        delete_option('clbntb_anti_cls');
    }
    
    echo '<div class="updated notice is-dismissible"><p>Đã lưu cấu hình tối ưu hóa.</p></div>';
}

$cdn_url = get_option('clbntb_cdn_url', '');
?>
<div class="wrap">
    <h1>CDN và Cache</h1>
    <h2 class="nav-tab-wrapper">
        <a href="?page=connect_type" class="nav-tab ">Danh sách nút</a>
        <a href="?page=connect_type_chatbot" class="nav-tab ">Chatbot</a>
        <a href="?page=connect_type_cdn" class="nav-tab nav-tab-active">CDN và Cache</a>
        <a href="?page=connect_type_status" class="nav-tab ">Trạng thái</a>
        <a href="?page=simpleSEOAdminOptions" class="nav-tab ">SEO</a>
        <a href="?page=connect_type_setting" class="nav-tab ">Cài đặt</a>
    </h2>

    <br>

    <h2>1. Cấu hình CDN</h2>
    <p>Nhập đường dẫn CDN của bạn. Các đường dẫn ảnh/file tĩnh trong wp-content/uploads sẽ được tự động đổi sang đường dẫn CDN này khi hiển thị.</p>
    <form method="post" action="">
        <table class="form-table">
            <tr valign="top">
                <th scope="row"><label for="clbntb_cdn_url">Đường dẫn CDN</label></th>
                <td>
                    <input type="text" name="clbntb_cdn_url" id="clbntb_cdn_url" value="<?php echo esc_attr($cdn_url); ?>" class="regular-text" style="width: 400px;">
                    <p class="description">Ví dụ: <code>https://cdn.yourdomain.com</code></p>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row"><label for="clbntb_cdn_api_key">CDN API Key (Bảo mật)</label></th>
                <td>
                    <input type="password" name="clbntb_cdn_api_key" id="clbntb_cdn_api_key" value="<?php echo esc_attr(get_option('clbntb_cdn_api_key', '')); ?>" class="regular-text" style="width: 400px;">
                    <p class="description">API Key bắt buộc phải khớp với <code>SECRET_API_KEY</code> khai báo trên server CDN để được phép tải ảnh lên.</p>
                </td>
            </tr>
        </table>
        <p class="submit">
            <input type="submit" name="submit_cdn" class="button button-primary" value="Lưu cấu hình CDN">
        </p>
    </form>

    <hr>

    <h2>2. ⚡ Quản lý Cache Siêu Tốc (Full Page Cache Ultra < 5ms)</h2>
    <p>Hệ thống nén tĩnh HTML & GZIP tự động trả về trang web trong <strong>&lt; 5ms</strong> (bỏ qua kết nối MySQL và toàn bộ tiến trình nạp WordPress Core). Bấm <strong>"Làm Ấm Tất Cả Cache (Pre-warm)"</strong> để tự động tạo sẵn cache cho 100% bài viết và chuyên mục trên website.</p>
    
    <button class="button button-primary" id="btn-prewarm-cache">🔥 Làm Ấm Tất Cả Cache (Pre-warm Site)</button>
    <button class="button" id="btn-clear-html-cache" style="border-color: #d63638; color: #d63638;">Xóa Full Page Cache (Làm Mới Web)</button>
    <div style="margin-top: 15px;"><span id="cache-spinner" class="spinner"></span></div>
    <p id="cache-result" style="color: green; font-weight: bold;"></p>



    <hr>

    <h2>4. Đồng bộ CSS và JS lên CDN</h2>
    <p>Chức năng này sẽ quét CSS và JS đang dùng trên trang chủ và chủ động đẩy lên máy chủ CDN. Điều này giúp Web của bạn tải cực nhanh mà không bị nghẽn (DDoS nội bộ) do CDN phải tự kéo file nữa.</p>
    
    <div style="display:flex; gap:16px; align-items:center; margin-bottom:12px;">
        <button class="button button-primary" id="clbntb-scan-assets">Quét CSS/JS</button>
        <button class="button" id="clbntb-upload-all-assets">Tải lên tất cả</button>
        <button class="button" id="clbntb-clear-assets-map">Xóa Map (Bỏ CDN CSS/JS)</button>
    </div>

    <table class="widefat fixed striped" id="clbntb-assets-table">
        <thead>
            <tr>
                <th style="width:45%">Đường dẫn Gốc (Site URL)</th>
                <th style="width:45%">Đường dẫn CDN</th>
                <th>Trạng thái</th>
            </tr>
        </thead>
        <tbody>
            <?php
            $assets = get_option('clbntb_cdn_assets', array());
            $map = get_option('clbntb_cdn_map', array());
            if (empty($assets)) {
                echo '<tr><td colspan="3">Chưa có dữ liệu. Hãy bấm "Quét CSS/JS".</td></tr>';
            } else {
                foreach ($assets as $item) {
                    $site = esc_url($item['src']);
                    $cdn  = esc_url($item['cdn']);
                    // Cần format lại key map giống trong code backend (host+path)
                    $parsed = parse_url($item['src']);
                    $key = strtolower(isset($parsed['host']) ? $parsed['host'] : '') . (isset($parsed['path']) ? $parsed['path'] : '');
                    
                    $uploaded = !empty($map[$key]);
                    echo '<tr data-site-url="' . $site . '" data-cdn-url="' . $cdn . '">';
                    echo '<td><a href="' . $site . '" target="_blank">' . $site . '</a></td>';
                    echo '<td><a href="' . $cdn . '" target="_blank">' . $cdn . '</a></td>';
                    echo '<td>';
                    if ($uploaded) {
                        echo '<span class="dashicons dashicons-yes" style="color:#46b450"></span> Đã đẩy lên CDN';
                    } else {
                        echo '<button class="button clbntb-upload-single">Đẩy lên CDN</button>';
                        echo '<span class="clbntb-status" style="margin-left:8px;"></span>';
                    }
                    echo '</td></tr>';
                }
            }
            ?>
        </tbody>
    </table>
    <style>
        #clbntb-assets-table td:nth-child(1), #clbntb-assets-table td:nth-child(2){ word-break: break-all; }
    </style>
    
    <hr>

    <h2>5. Tối ưu hóa tĩnh (HTML/CSS/JS)</h2>
    <p>Hệ thống tự động thực hiện các tối ưu hóa như: Xóa Query String (?ver=) của CSS/JS và nhúng trực tiếp (Inline) CSS của Theme chính vào HTML Cache. Nếu trang web của bạn bị vỡ giao diện hoặc xung đột với plugin Cache khác, hãy đánh dấu vào ô dưới đây để tắt tính năng này.</p>
    <form method="post" action="">
        <table class="form-table">
            <tr valign="top">
                <th scope="row">Tắt Tối Ưu Hóa HTML/CSS/JS</th>
                <td>
                    <label>
                        <input type="checkbox" name="clbntb_disable_optimization" value="1" <?php checked(get_option('clbntb_disable_optimization'), '1'); ?>>
                        Tắt tính năng tối ưu hóa CSS/JS nội tuyến và giữ nguyên Query String (Khuyên dùng nếu web bị lỗi giao diện).
                    </label>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Bật User-Specific Cache</th>
                <td>
                    <label>
                        <input type="checkbox" name="clbntb_enable_user_cache" value="1" <?php checked(get_option('clbntb_enable_user_cache'), '1'); ?>>
                        <strong style="color: #d63638;">[Cảnh báo]</strong> Bật bộ nhớ đệm riêng biệt cho từng tài khoản đăng nhập. Tốc độ web cho Admin/Thành viên sẽ siêu nhanh, nhưng sẽ tiêu tốn nhiều dung lượng ổ cứng hơn và có thể gây lỗi các liên kết Admin Bar (Nonces) do thời gian sống của Cache dài.
                    </label>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Sử dụng WebP</th>
                <td>
                    <label>
                        <input type="checkbox" name="clbntb_rewrite_webp" value="1" <?php checked(get_option('clbntb_rewrite_webp'), '1'); ?>>
                        Tự động thay thế đuôi ảnh <code>.png</code>, <code>.jpg</code> sang <code>.webp</code> trên giao diện sau khi bạn đã click <strong>Chuyển đổi toàn bộ sang WebP</strong> thành công ở mục dưới.
                    </label>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Trì hoãn thực thi JS (Delay JS Execution)</th>
                <td>
                    <label>
                        <input type="checkbox" name="clbntb_delay_js" value="1" <?php checked(get_option('clbntb_delay_js', '1'), '1'); ?>>
                        Trì hoãn các script bên thứ 3 (Google Tag Manager, Facebook Pixel, Chatbot, RevSlider, Tracking) cho tới khi người dùng cuộn trang hoặc di chuột. <strong>(Tối ưu cực lớn cho chỉ số TBT & LCP trên PageSpeed)</strong>.
                    </label>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Bật Anti-CLS (Chống giật khung hình)</th>
                <td>
                    <label>
                        <input type="checkbox" name="clbntb_anti_cls" value="1" <?php checked(get_option('clbntb_anti_cls'), '1'); ?>>
                        Tự động vô hiệu hoá các hiệu ứng chuyển động (Animations) của Theme và Page Builder (Elementor, Divi, tagDiv, Flatsome...) để chống rớt điểm Cumulative Layout Shift trên Google PageSpeed.
                    </label>
                </td>
            </tr>
        </table>
        <p class="submit">
            <input type="submit" name="submit_optimization" class="button button-primary" value="Lưu Cấu Hình Tối Ưu">
        </p>
    </form>

    <hr>
    <h2>6. Chuyển đổi ảnh Media sang WebP</h2>
    <p>Chức năng này sẽ quét tất cả ảnh trong thư viện (Media Library) và chuyển đổi các định dạng <code>.png</code>, <code>.jpg</code> sang chuẩn nén cao cấp <code>.webp</code> để website load nhanh hơn. (Sẽ tự động đẩy lên CDN và xóa file cục bộ để tiết kiệm ổ cứng).</p>
    <div style="display:flex; gap:16px; align-items:center; margin-bottom:12px;">
        <button class="button button-primary" id="btn-convert-webp">Chuyển đổi toàn bộ sang WebP</button>
        <button class="button" id="btn-clean-webp" style="border-color: #d63638; color: #d63638;">Xóa toàn bộ ảnh WebP cục bộ (Dọn ổ cứng)</button>
        <label style="margin-left: 10px;"><input type="checkbox" id="force-webp-overwrite" value="1"> Ép ghi đè CDN (Sửa lỗi ảnh ma)</label>
    </div>
    <span id="webp-spinner" class="spinner"></span>
    <p id="webp-result" style="color: green; font-weight: bold;"></p>

    <hr>
    <h2>7. 🖼️ Tạo lại Thumbnail Bài Viết & Đồng bộ CDN (Regenerate Thumbnails)</h2>
    <p>Giải quyết vấn đề ảnh thumbnail/crop bị thiếu hoặc không hiển thị trên CDN. Chức năng sẽ đọc lại ảnh gốc, cắt lại đúng kích thước theo Theme/Plugin hiện tại, tự động chuyển WebP và đẩy tất cả kích thước mới lên CDN.</p>
    
    <div style="background: #f8f9fa; border: 1px solid #ccd0d4; padding: 15px; border-radius: 4px; margin-bottom: 15px;">
        <h4 style="margin-top:0;">Tạo lại theo ID Bài Viết hoặc ID Ảnh:</h4>
        <div style="display:flex; gap:10px; align-items:center;">
            <select id="recrop-type" style="padding: 4px 8px;">
                <option value="single_post">ID Bài viết (Post ID)</option>
                <option value="single_attachment">ID Ảnh (Attachment ID)</option>
            </select>
            <input type="number" id="recrop-target-id" placeholder="Nhập ID..." style="width: 150px;">
            <button class="button button-primary" id="btn-recrop-single">🚀 Tạo lại Thumbnail & Sync CDN</button>
        </div>
        <p id="recrop-single-result" style="margin-top: 8px; font-weight: bold;"></p>
    </div>

    <div style="margin-bottom: 20px;">
        <button class="button button-secondary" id="btn-recrop-all-posts" style="background: #2271b1; color: #fff; border-color: #2271b1;">🔄 Tạo lại Thumbnail cho TẤT CẢ Bài Viết</button>
        <span id="recrop-spinner" class="spinner"></span>
        <p id="recrop-batch-result" style="color: green; font-weight: bold; margin-top: 8px;"></p>
    </div>
</div>

<script>
jQuery(document).ready(function($) {
    // Pre-warm Full Page Cache
    $('#btn-prewarm-cache').on('click', function(e) {
        e.preventDefault();
        $('#cache-spinner').addClass('is-active');
        $('#cache-result').css('color', 'black').text('Đang bắt đầu quét và làm ấm bộ nhớ đệm...');
        $('#btn-prewarm-cache').prop('disabled', true);

        let is_first = 1;
        let total_processed = 0;

        function runPrewarm() {
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: { action: 'clbntb_prewarm_cache', is_first: is_first },
                success: function(res) {
                    is_first = 0;
                    if (res.success) {
                        if (res.data.done) {
                            $('#cache-spinner').removeClass('is-active');
                            $('#btn-prewarm-cache').prop('disabled', false);
                            $('#cache-result').css('color', 'green').text(res.data.message + ' (Đã làm ấm tổng cộng: ' + total_processed + ' trang)');
                        } else {
                            total_processed += res.data.processed || 0;
                            $('#cache-result').css('color', 'black').text('🔥 Đang làm ấm cache... Đã xử lý ' + total_processed + ' trang (Còn lại: ' + res.data.remaining + ' trang)');
                            runPrewarm();
                        }
                    } else {
                        $('#cache-spinner').removeClass('is-active');
                        $('#btn-prewarm-cache').prop('disabled', false);
                        $('#cache-result').css('color', 'red').text('Lỗi: ' + res.data);
                    }
                },
                error: function() {
                    $('#cache-result').css('color', 'red').text('Kết nối gián đoạn. Tự động thử lại sau 3s...');
                    setTimeout(runPrewarm, 3000);
                }
            });
        }
        runPrewarm();
    });

    // Clear HTML Cache
    $('#btn-clear-html-cache').on('click', function(e) {
        e.preventDefault();
        if (!confirm('Bạn có chắc chắn muốn xóa toàn bộ Full Page Cache HTML không?')) return;
        
        $('#cache-spinner').addClass('is-active');
        $('#cache-result').text('Đang xóa cache HTML...');
        $('#btn-clear-html-cache').prop('disabled', true);

        $.ajax({
            url: ajaxurl,
            type: 'POST',
            data: {
                action: 'clbntb_clear_html_cache'
            },
            success: function(response) {
                $('#cache-spinner').removeClass('is-active');
                $('#btn-clear-html-cache').prop('disabled', false);
                if (response.success) {
                    $('#cache-result').css('color', 'green').text(response.data);
                } else {
                    $('#cache-result').css('color', 'red').text('Lỗi: ' + response.data);
                }
            },
            error: function() {
                $('#cache-spinner').removeClass('is-active');
                $('#btn-clear-html-cache').prop('disabled', false);
                $('#cache-result').css('color', 'red').text('Lỗi kết nối server.');
            }
        });
    });

    // Convert to WebP
    $('#btn-convert-webp').on('click', function(e) {
        e.preventDefault();
        if (!confirm('Hệ thống sẽ chuyển đổi tất cả ảnh .png, .jpg trong thư viện sang .webp. Việc này có thể mất vài phút. Bắt đầu?')) return;
        
        $('#webp-spinner').addClass('is-active');
        $('#webp-result').css('color', 'black').text('Đang bắt đầu quét từ đầu...');
        $('#btn-convert-webp').prop('disabled', true);

        let is_first = 1;
        let total_processed = 0;
        
        function processBatch() {
            let force_overwrite = $('#force-webp-overwrite').is(':checked') ? 1 : 0;
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: { action: 'clbntb_convert_webp', is_first: is_first, force: force_overwrite },
                success: function(response) {
                    is_first = 0;
                    if (response.success) {
                        if (response.data.done) {
                            $('#webp-spinner').removeClass('is-active');
                            $('#btn-convert-webp').prop('disabled', false);
                            $('#webp-result').css('color', 'green').text('Hoàn tất! ' + response.data.message + ' (Tổng cộng: ' + total_processed + ' file)');
                        } else {
                            total_processed += response.data.processed || 0;
                            $('#webp-result').css('color', 'black').text('Đang quét... Đã xử lý ' + total_processed + ' file ảnh (Đang xử lý tiếp...)');
                            processBatch();
                        }
                    } else {
                        $('#webp-spinner').removeClass('is-active');
                        $('#btn-convert-webp').prop('disabled', false);
                        $('#webp-result').css('color', 'red').text('Lỗi: ' + response.data);
                    }
                },
                error: function() {
                    $('#webp-result').css('color', 'red').text('Lỗi kết nối server. Đang tự động thử lại sau 3 giây... (Đã quét: ' + total_processed + ' file)');
                    setTimeout(function() {
                        processBatch();
                    }, 3000);
                }
            });
        }
        processBatch();
    });

    // Clean WebP
    $('#btn-clean-webp').on('click', function(e) {
        e.preventDefault();
        if (!confirm('Bạn có chắc chắn muốn xóa toàn bộ các file .webp đang lưu trên ổ cứng của server không? Việc này giúp giải phóng dung lượng cho các máy chủ bị đầy ổ cứng.')) return;
        
        $('#webp-spinner').addClass('is-active');
        $('#webp-result').text('Đang quét và xóa...');
        $('#btn-clean-webp').prop('disabled', true);

        $.ajax({
            url: ajaxurl,
            type: 'POST',
            data: { action: 'clbntb_clean_webp' },
            success: function(response) {
                $('#webp-spinner').removeClass('is-active');
                $('#btn-clean-webp').prop('disabled', false);
                if (response.success) {
                    $('#webp-result').css('color', 'green').text(response.data);
                } else {
                    $('#webp-result').css('color', 'red').text('Lỗi: ' + response.data);
                }
            },
            error: function() {
                $('#webp-spinner').removeClass('is-active');
                $('#btn-clean-webp').prop('disabled', false);
                $('#webp-result').css('color', 'red').text('Lỗi kết nối server.');
            }
        });
    });



    // --- CSS/JS Pusher Logic ---
    function postAjax(action, data) {
        return $.post(ajaxurl, $.extend({ action: action }, data));
    }

    $('#clbntb-scan-assets').on('click', function(e) {
        e.preventDefault();
        var $btn = $(this).prop('disabled', true).text('Đang quét...');
        postAjax('clbntb_scan_assets', {})
        .done(function(res) { location.reload(); })
        .fail(function() { alert('Quét lỗi'); })
        .always(function() { $btn.prop('disabled', false).text('Quét CSS/JS'); });
    });

    $('#clbntb-clear-assets-map').on('click', function(e) {
        e.preventDefault();
        if (!confirm('Bạn có chắc chắn xóa toàn bộ map? Trang web sẽ dùng lại CSS/JS từ máy chủ gốc.')) return;
        var $btn = $(this).prop('disabled', true).text('Đang xóa...');
        postAjax('clbntb_clear_map', {})
        .done(function() { location.reload(); })
        .fail(function() { alert('Không xóa được'); })
        .always(function() { $btn.prop('disabled', false).text('Xóa Map'); });
    });

    $('#clbntb-assets-table').on('click', '.clbntb-upload-single', function(e) {
        e.preventDefault();
        var $row = $(this).closest('tr');
        var site = $row.data('site-url');
        var cdn  = $row.data('cdn-url');
        var $btn = $(this).prop('disabled', true).text('Đang đẩy...');
        var $status = $row.find('.clbntb-status').text('');

        postAjax('clbntb_upload_asset', { site_url: site, cdn_url: cdn })
        .done(function(res) {
            if (res && res.success) {
                $btn.replaceWith('<span class="dashicons dashicons-yes" style="color:#46b450"></span> Đã đẩy lên CDN');
            } else {
                $status.css('color', 'red').text(res.data ? res.data : 'Tải lên thất bại');
                $btn.prop('disabled', false).text('Đẩy lên CDN');
            }
        })
        .fail(function() {
            $status.css('color', 'red').text('Lỗi kết nối API');
            $btn.prop('disabled', false).text('Đẩy lên CDN');
        });
    });

    $('#clbntb-upload-all-assets').on('click', function(e) {
        e.preventDefault();
        var $rows = $('#clbntb-assets-table tbody tr');
        var i = 0;
        function nextUpload() {
            if (i >= $rows.length) return;
            var $row = $rows.eq(i++);
            var $btn = $row.find('.clbntb-upload-single');
            if ($btn.length) {
                $btn.trigger('click');
                setTimeout(nextUpload, 500); // Đẩy từ từ từng file một, chống ngập lụt
            } else {
                nextUpload();
            }
        }
        nextUpload();
    });

    // Single Recrop
    $('#btn-recrop-single').on('click', function(e) {
        e.preventDefault();
        let mode = $('#recrop-type').val();
        let id = $('#recrop-target-id').val();
        if (!id) {
            alert('Vui lòng nhập ID!');
            return;
        }

        let btn = $(this);
        btn.prop('disabled', true).text('Đang tạo lại & Sync CDN...');
        $('#recrop-single-result').css('color', 'black').text('Đang xử lý...');

        $.ajax({
            url: ajaxurl,
            type: 'POST',
            data: {
                action: 'clbntb_regenerate_thumbnails',
                mode: mode,
                id: id
            },
            success: function(res) {
                btn.prop('disabled', false).text('🚀 Tạo lại Thumbnail & Sync CDN');
                if (res.success) {
                    $('#recrop-single-result').css('color', 'green').text(res.data);
                } else {
                    $('#recrop-single-result').css('color', 'red').text('Lỗi: ' + res.data);
                }
            },
            error: function() {
                btn.prop('disabled', false).text('🚀 Tạo lại Thumbnail & Sync CDN');
                $('#recrop-single-result').css('color', 'red').text('Lỗi kết nối server.');
            }
        });
    });

    // Batch Recrop All Posts
    $('#btn-recrop-all-posts').on('click', function(e) {
        e.preventDefault();
        if (!confirm('Bạn có chắc muốn quét và tạo lại Thumbnail cho TẤT CẢ bài viết trên website?')) return;

        $('#recrop-spinner').addClass('is-active');
        $('#recrop-batch-result').css('color', 'black').text('Đang khởi tạo danh sách bài viết...');
        $('#btn-recrop-all-posts').prop('disabled', true);

        let is_first = 1;
        let total_posts = 0;
        let total_imgs = 0;

        function runBatchRecrop() {
            $.ajax({
                url: ajaxurl,
                type: 'POST',
                data: {
                    action: 'clbntb_regenerate_thumbnails',
                    mode: 'batch_posts',
                    is_first: is_first
                },
                success: function(res) {
                    is_first = 0;
                    if (res.success) {
                        if (res.data.done) {
                            $('#recrop-spinner').removeClass('is-active');
                            $('#btn-recrop-all-posts').prop('disabled', false);
                            $('#recrop-batch-result').css('color', 'green').text(res.data.message + ' (Đã xử lý tổng cộng: ' + total_posts + ' bài viết, ' + total_imgs + ' ảnh)');
                        } else {
                            total_posts += res.data.processed_posts || 0;
                            total_imgs += res.data.regenerated_images || 0;
                            $('#recrop-batch-result').css('color', 'black').text('🔄 Đang tạo lại thumbnail... Đã xử lý ' + total_posts + ' bài viết (' + total_imgs + ' ảnh mới), Còn lại: ' + res.data.remaining + ' bài');
                            runBatchRecrop();
                        }
                    } else {
                        $('#recrop-spinner').removeClass('is-active');
                        $('#btn-recrop-all-posts').prop('disabled', false);
                        $('#recrop-batch-result').css('color', 'red').text('Lỗi: ' + res.data);
                    }
                },
                error: function() {
                    $('#recrop-batch-result').css('color', 'red').text('Kết nối gián đoạn. Tự động thử lại sau 3s...');
                    setTimeout(runBatchRecrop, 3000);
                }
            });
        }
        runBatchRecrop();
    });
});
</script>
