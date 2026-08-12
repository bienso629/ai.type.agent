<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

if (defined('AITYPE_LICENSE_INVALID')) {
    echo '<div class="wrap"><h1>🛑 Tính năng bị khóa</h1><p style="font-size: 16px;">Vui lòng nhập mã bản quyền hợp lệ tại trang cấu hình chính để sử dụng chức năng này.</p></div>';
    return;
}

// 1. Xử lý lưu dữ liệu
if (isset($_POST['submit'])) {
    update_option('google_api_key', sanitize_text_field($_POST['google_api_key']));
    update_option('llm_model', sanitize_text_field($_POST['llm_model']));

    update_option('simple_chatbot_logo', sanitize_text_field($_POST['simple_chatbot_logo']));
    update_option('simple_chatbot_image', sanitize_text_field($_POST['simple_chatbot_image']));

    update_option('simple_chatbot_app_token', sanitize_text_field($_POST['simple_chatbot_app_token']));
    update_option('simple_chatbot_username', sanitize_text_field($_POST['simple_chatbot_username']));
    
    // Nếu muốn cho phép sửa API endpoint thì đổi type hidden thành text ở dưới, hiện tại vẫn lưu nếu post lên
    update_option('simple_chatbot_api', sanitize_text_field($_POST['simple_chatbot_api']));
    
    update_option('simple_chatbot_data_source', sanitize_text_field($_POST['simple_chatbot_data_source']));

    echo '<div class="updated notice is-dismissible"><p>Cấu hình đã được lưu thành công.</p></div>';
}

// 2. Lấy dữ liệu hiện tại
$google_api_key = get_option('google_api_key', '');
$llm_model = get_option('llm_model', 'gemini-3.5-flash');
$simple_chatbot_data_source = get_option('simple_chatbot_data_source', 'website');
$simple_chatbot_api = get_option('simple_chatbot_api', 'https://bot.type.vn');
?>
<style>
    /* Form styling cơ bản */
    .form-table th { width: 220px; font-weight: 600; }
    input[type="text"].wide-input { width: 100%; max-width: 500px; }
    .preview-image { 
        margin-top: 10px; max-width: 120px; border: 1px solid #ddd; padding: 3px; border-radius: 4px; 
        display: block;
    }
    .upgrade-link {
        float: right; text-decoration: none; color: #d63638; border: 1px solid #d63638; 
        padding: 5px 10px; border-radius: 4px; font-weight: 500;
    }
    .upgrade-link:hover { background: #d63638; color: #fff; }
    
    .chatbot-section-title {
        margin-top: 30px;
        margin-bottom: 5px;
        font-size: 1.2em;
        border-bottom: 1px solid #ccc;
        padding-bottom: 5px;
    }
</style>

<div class="wrap simple-chatbot-settings">
    <h1>
        Cấu hình Simple Chatbot
    </h1>

    <h2 class="nav-tab-wrapper">
        <a href="?page=connect_type" class="nav-tab ">Danh sách nút</a>
        <a href="?page=connect_type_chatbot" class="nav-tab nav-tab-active">Chatbot</a>
        <a href="?page=connect_type_cdn" class="nav-tab ">CDN và Cache</a>
        
        <a href="?page=simpleSEOAdminOptions" class="nav-tab ">SEO</a>
        <a href="?page=connect_type_setting" class="nav-tab ">Cài đặt</a>
    </h2>
    <br>

    <form method="post" action="">
        
        <h3 class="chatbot-section-title">1. Cấu hình Gemini/AI</h3>
        <p class="description">Cấu hình kết nối tới Google Gemini/AI.</p>
        <table class="form-table">
            <tr>
                <th scope="row"><label for="google_api_key">Google API Key</label></th>
                <td>
                    <input type="password" name="google_api_key" id="google_api_key" value="<?php echo esc_attr($google_api_key); ?>" class="regular-text wide-input">
                    <p class="description">Nhập API Key từ Google AI Studio.</p>
                </td>
            </tr>
            <tr>
                <th scope="row"><label for="llm_model">Model ID</label></th>
                <td>
                    <input type="text" name="llm_model" id="llm_model" value="<?php echo esc_attr($llm_model); ?>" class="regular-text">
                    <p class="description">Ví dụ: <code>gemini-2.0-flash</code>, <code>gemini-1.5-pro</code></p>
                </td>
            </tr>
        </table>

        <h3 class="chatbot-section-title">2. Giao diện Chatbot</h3>
        <p class="description">Tùy chỉnh hình ảnh hiển thị của Chatbot.</p>
        <table class="form-table">
            <tr valign="top">
                <th scope="row">Logo Chatbot</th>
                <td>
                    <input type="text" id="simple_chatbot_logo" name="simple_chatbot_logo" value="<?php echo esc_attr(get_option('simple_chatbot_logo')); ?>" class="regular-text" />
                    <input type="button" class="button" value="Chọn ảnh" id="upload_logo_button" />
                    <?php if(get_option('simple_chatbot_logo')): ?>
                        <img id="logo_preview" src="<?php echo esc_attr(get_option('simple_chatbot_logo')); ?>" class="preview-image" />
                    <?php else: ?>
                        <img id="logo_preview" src="" class="preview-image" style="display:none;" />
                    <?php endif; ?>
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Ảnh phụ (Banner/Icon)</th>
                <td>
                    <input type="text" id="simple_chatbot_image" name="simple_chatbot_image" value="<?php echo esc_attr(get_option('simple_chatbot_image')); ?>" class="regular-text" />
                    <input type="button" class="button" value="Chọn ảnh" id="upload_image_button" />
                    <?php if(get_option('simple_chatbot_image')): ?>
                        <img id="image_preview" src="<?php echo esc_attr(get_option('simple_chatbot_image')); ?>" class="preview-image" />
                    <?php else: ?>
                        <img id="image_preview" src="" class="preview-image" style="display:none;" />
                    <?php endif; ?>
                </td>
            </tr>
        </table>

        <h3 class="chatbot-section-title">3. Tài khoản ứng dụng</h3>
        <p class="description">Thông tin kết nối tài khoản ứng dụng.</p>
        <table class="form-table">
            <tr valign="top">
                <th scope="row">App Token</th>
                <td>
                    <input type="password" name="simple_chatbot_app_token" value="<?php echo esc_attr(get_option('simple_chatbot_app_token')); ?>" class="regular-text wide-input" />
                </td>
            </tr>
            <tr valign="top">
                <th scope="row">Tên đăng nhập (Type Forum)</th>
                <td>
                    <input type="text" name="simple_chatbot_username" value="<?php echo esc_attr(get_option('simple_chatbot_username')); ?>" class="regular-text" />
                </td>
            </tr>
            <tr valign="top" style="display:none;"> 
                <th scope="row">API Endpoint</th>
                <td>
                    <input type="text" name="simple_chatbot_api" value="<?php echo esc_attr($simple_chatbot_api); ?>" class="regular-text wide-input" />
                </td>
            </tr>
        </table>

        <h3 class="chatbot-section-title">4. Nguồn dữ liệu</h3>
        <p class="description">Chọn phương thức bot học dữ liệu.</p>
        <table class="form-table">
            <tr>
                <th scope="row">Nguồn dữ liệu</th>
                <td>
                    <fieldset>
                        <label style="margin-bottom: 8px; display: block;">
                            <input type="radio" name="simple_chatbot_data_source" value="documents" <?php checked($simple_chatbot_data_source, 'documents'); ?> />
                            <strong>Sử dụng tài liệu (Filebase)</strong> <br>
                            <span class="description" style="margin-left: 25px;">Bot sẽ trả lời dựa trên file PDF, DOC mà bạn cung cấp.</span>
                        </label>
                        <label style="display: block;">
                            <input type="radio" name="simple_chatbot_data_source" value="website" <?php checked($simple_chatbot_data_source, 'website'); ?> />
                            <strong>Sử dụng nội dung Website</strong> <br>
                            <span class="description" style="margin-left: 25px;">Bot sẽ cào dữ liệu (crawl) từ nội dung bài viết trên web này.</span>
                        </label>
                    </fieldset>
                </td>
            </tr>
        </table>

        <br>
        <p class="submit">
            <input type="submit" name="submit" id="submit" class="button button-primary" value="Lưu cấu hình Chatbot">
        </p>
    </form>
</div>

<script>
jQuery(document).ready(function($){
    // XỬ LÝ UPLOAD ẢNH (WP MEDIA)
    if (typeof wp === 'undefined' || typeof wp.media === 'undefined') {
        return;
    }

    function bindUploader(buttonId, inputId, previewId) {
        let mediaUploader;
        $(`#${buttonId}`).click(function(e) {
            e.preventDefault();
            if (mediaUploader) {
                mediaUploader.open();
                return;
            }
            mediaUploader = wp.media({
                title: 'Chọn ảnh cho Chatbot',
                button: { text: 'Sử dụng ảnh này' },
                multiple: false
            });
            mediaUploader.on('select', function() {
                const attachment = mediaUploader.state().get('selection').first().toJSON();
                $(`#${inputId}`).val(attachment.url);
                $(`#${previewId}`).attr('src', attachment.url).show();
            });
            mediaUploader.open();
        });
    }

    bindUploader('upload_logo_button', 'simple_chatbot_logo', 'logo_preview');
    bindUploader('upload_image_button', 'simple_chatbot_image', 'image_preview');
});
</script>