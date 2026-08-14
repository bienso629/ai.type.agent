<?php
if (defined('AITYPE_LICENSE_INVALID')) {
    echo '<div class="wrap"><h1>🛑 Tính năng bị khóa</h1><p style="font-size: 16px;">Vui lòng nhập mã bản quyền hợp lệ tại trang cấu hình chính để sử dụng chức năng này.</p></div>';
    return;
}
?>
<div class="wrap">
    <h1>Cài đặt</h1>
    <h2 class="nav-tab-wrapper">
        <a href="?page=connect_type" class="nav-tab ">Danh sách nút</a>
        <a href="?page=connect_type_chatbot" class="nav-tab ">Chatbot</a>
        <a href="?page=connect_type_cdn" class="nav-tab ">CDN và Cache</a>
        <a href="?page=connect_type_status" class="nav-tab ">Trạng thái</a>
        <a href="?page=simpleSEOAdminOptions" class="nav-tab ">SEO</a>
        <a href="?page=connect_type_setting" class="nav-tab nav-tab-active">Cài đặt</a>
    </h2>
    <form method="post" action="options.php">
        <?php settings_fields( 'clbntb-settings-group-setting' ); ?>
        <?php do_settings_sections( 'clbntb-settings-group-setting' ); ?>
        <table class="form-table">
            
            <tr valign="top">
            <th scope="row">Kích thước nút</th>
            <td>
                <select name="setting_size">
                  <option value="1" <?php if ( get_option('setting_size') == 1 ) echo 'selected="selected"'; ?>>Bình thường</option>
                  <option value="2" <?php if ( get_option('setting_size') == 2 ) echo 'selected="selected"'; ?>>Lớn</option>
                  <option value="3" <?php if ( get_option('setting_size') == 3 ) echo 'selected="selected"'; ?>>Nhỏ</option>
                </select>
                <p>Nên chọn kích thước <strong>nhỏ</strong> đối với điện thoại di động.</p>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Vị trí</th>
            <td>
                <select name="clbntb_location">
                  <option value="1" <?php if ( get_option('clbntb_location', 2) == 1 ) echo 'selected="selected"'; ?>>Góc trái</option>
                  <option value="2" <?php if ( get_option('clbntb_location', 2) == 2 ) echo 'selected="selected"'; ?>>Góc phải</option>
                </select>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Cách lề dưới</th>
            <td><input type="text" name="clbntb_location_bottom" value="<?php echo esc_attr( get_option('clbntb_location_bottom') ); ?>" />
            <p>Sử dụng khi bạn muốn thay đổi khoảng cách đối với lề dưới của nút (đơn vị: <strong>px</strong>) VD: 10</p>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Ẩn trên Mobile</th>
            <td><input type="checkbox" name="clbntb_hide_mobile" value="1" <?php checked(1, get_option('clbntb_hide_mobile'), true); ?> /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Ẩn trên Máy tính (PC/Laptop)</th>
            <td><input type="checkbox" name="clbntb_hide_desktop" value="1" <?php checked(1, get_option('clbntb_hide_desktop'), true); ?> /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Kiểu layout</th>
            <td>
                <select name="clbntb_layout_type">
                  <option value="vertical" <?php if ( get_option('clbntb_layout_type', 'vertical') == 'vertical' ) echo 'selected="selected"'; ?>>Dọc (Mặc định)</option>
                  <option value="horizontal" <?php if ( get_option('clbntb_layout_type') == 'horizontal' ) echo 'selected="selected"'; ?>>Ngang</option>
                  <option value="collapse" <?php if ( get_option('clbntb_layout_type') == 'collapse' ) echo 'selected="selected"'; ?>>Thu gọn (Chỉ hiển thị 1 icon Chatbot)</option>
                </select>
            </td>
            </tr>

            <tr valign="top">
            <th scope="row">Màu nền nút Thu gọn</th>
            <td>
                <input type="text" name="clbntb_toggle_bg_color" value="<?php echo esc_attr( get_option('clbntb_toggle_bg_color', '') ); ?>" class="my-color-field" data-default-color="transparent" />
                <p class="description">Màu nền cho icon chính. <b>Để làm nền trong suốt, hãy bấm nút Xóa (Clear) ở bảng màu.</b></p>
            </td>
            </tr>

            <tr valign="top">
            <th scope="row">Kiểu hiệu ứng</th>
            <td>
                <select name="clbntb_effect_type">
                  <option value="default" <?php if ( get_option('clbntb_effect_type', 'default') == 'default' ) echo 'selected="selected"'; ?>>Mặc định (Tỏa sáng & Lắc)</option>
                  <option value="zoom_only" <?php if ( get_option('clbntb_effect_type') == 'zoom_only' ) echo 'selected="selected"'; ?>>Chỉ tỏa sáng</option>
                  <option value="heartbeat" <?php if ( get_option('clbntb_effect_type') == 'heartbeat' ) echo 'selected="selected"'; ?>>Nhịp tim (Heartbeat)</option>
                  <option value="spin" <?php if ( get_option('clbntb_effect_type') == 'spin' ) echo 'selected="selected"'; ?>>Xoay tròn (Spinning)</option>
                  <option value="bounce" <?php if ( get_option('clbntb_effect_type') == 'bounce' ) echo 'selected="selected"'; ?>>Nhún nhảy (Bouncing)</option>
                  <option value="fade_glow" <?php if ( get_option('clbntb_effect_type') == 'fade_glow' ) echo 'selected="selected"'; ?>>Sáng mờ dần (Fade Glow)</option>
                  <option value="ring" <?php if ( get_option('clbntb_effect_type') == 'ring' ) echo 'selected="selected"'; ?>>Rung chuông (Ringing)</option>
                  <option value="wobble" <?php if ( get_option('clbntb_effect_type') == 'wobble' ) echo 'selected="selected"'; ?>>Lắc lư (Wobble)</option>
                  <option value="tada" <?php if ( get_option('clbntb_effect_type') == 'tada' ) echo 'selected="selected"'; ?>>Nhấn mạnh (Tada)</option>
                </select>
            </td>
            </tr>

            <tr valign="top">
            <th scope="row">Custom CSS</th>
            <td>
                <textarea name="clbntb_custom_css" rows="5" class="large-text code"><?php echo esc_textarea( get_option('clbntb_custom_css') ); ?></textarea>
                <p>Nhập mã CSS tùy chỉnh của bạn vào đây (không cần thẻ &lt;style&gt;).</p>
            </td>
            </tr>
             
        
            <tr valign="top">
            <th scope="row">Ẩn thông báo Admin (Notices)</th>
            <td>
                <label for="clbntb_disable_admin_notices">
                    <input type="checkbox" id="clbntb_disable_admin_notices" name="clbntb_disable_admin_notices" value="1" <?php checked(1, get_option('clbntb_disable_admin_notices'), true); ?> /> 
                    Tắt toàn bộ các banner quảng cáo, thông báo nhắc nhở từ các plugin khác để trang quản trị gọn gàng hơn.
                </label>
            </td>
            </tr>
        </table>
        
        <?php submit_button(); ?>

    </form>
</div>