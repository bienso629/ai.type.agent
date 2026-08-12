<?php
?>
<div class="wrap">
    <h1>AI Type</h1>

    <?php if(!defined('AITYPE_LICENSE_INVALID')): ?>
    <h2 class="nav-tab-wrapper">
        <a href="?page=connect_type" class="nav-tab nav-tab-active">Danh sách nút</a>
        <a href="?page=connect_type_chatbot" class="nav-tab ">Chatbot</a>
        <a href="?page=connect_type_cdn" class="nav-tab ">CDN và Cache</a>
        
        <a href="?page=simpleSEOAdminOptions" class="nav-tab ">SEO</a>
        <a href="?page=connect_type_setting" class="nav-tab ">Cài đặt</a>
    </h2>
    <?php endif; ?>
    <form method="post" action="options.php">
        <?php settings_fields( 'clbntb-settings-group' ); ?>
        <?php do_settings_sections( 'clbntb-settings-group' ); ?>
        
        <!-- KHU VỰC BẢN QUYỀN -->
        <?php if(defined('AITYPE_LICENSE_INVALID')): ?>
        <div style="background: #fff3cd; border: 1px solid #ffeeba; border-left: 4px solid #ffc107; padding: 15px; margin-bottom: 20px; border-radius: 4px;">
            <h3 style="margin-top: 0; color: #856404;">🔑 Kích hoạt Bản Quyền Plugin</h3>
            <p style="color: #856404;">Vui lòng nhập Mã bản quyền (License Key) được cấp phép để sử dụng trọn bộ tính năng SEO, Chatbot và Nút Liên hệ.</p>
            <input type="text" name="ai_type_license_key" autocomplete="off" value="<?php echo esc_attr( get_option('ai_type_license_key') ); ?>" placeholder="Nhập mã kích hoạt của bạn vào đây..." style="width: 100%; max-width: 400px; padding: 8px; font-weight: bold; color: #721c24;" />
            <span style="color: #721c24; font-weight: bold; margin-left: 10px;">❌ Chưa kích hoạt</span>
        </div>
        <?php else: ?>
            <input type="hidden" name="ai_type_license_key" value="<?php echo esc_attr( get_option('ai_type_license_key') ); ?>" />
        <?php endif; ?>

        <?php if(!defined('AITYPE_LICENSE_INVALID')): ?>
        <table class="form-table">
            <p><strong>Lưu ý: Bỏ trống nếu không dùng</strong></p>
            <tr valign="top">
            <th scope="row">Số điện thoại 1</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_phone" value="<?php echo esc_attr( get_option('clbntb_phone') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_clbntb_phone" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_clbntb_phone') ); ?>" /></div>
                </div>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Số điện thoại 2</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_phone2" value="<?php echo esc_attr( get_option('clbntb_phone2') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_clbntb_phone2" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_clbntb_phone2') ); ?>" /></div>
                </div>
            </td>
            </tr>
             
            <tr valign="top">
            <th scope="row">Số điện thoại 3</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_phone3" value="<?php echo esc_attr( get_option('clbntb_phone3') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_clbntb_phone3" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_clbntb_phone3') ); ?>" /></div>
                </div>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Zalo</th>
            <td><input type="text" name="clbntb_zalo" value="<?php echo esc_attr( get_option('clbntb_zalo') ); ?>" />
            <p>Sử dụng link rút gọn zalo: <strong>https://zalo.me/sodienthoai</strong> để mở zalo trên cả Web và Điện thoại.</p>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Zalo OA ID (Widget Chat)</th>
            <td><input type="text" name="clbntb_zalo_oa_id" value="<?php echo esc_attr( get_option('clbntb_zalo_oa_id') ); ?>" />
            <p>Nhập Official Account ID để hiển thị Zalo Chat Widget (Tải kiểu Lazy load).</p>
            </td>
            </tr>
            
            <tr valign="top">
            <th scope="row">Link Messenger</th>
            <td><input type="text" name="clbntb_linkmessenger" value="<?php echo esc_attr( get_option('clbntb_linkmessenger') ); ?>" />
            <p>VD: <strong>https://m.me/id-fanpage</strong></p>
            </td>
            </tr>
             <tr valign="top">
            <th scope="row">Link Fanpage</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_linkfanpage" value="<?php echo esc_attr( get_option('clbntb_linkfanpage') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_fb" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_fb') ); ?>" /></div>
                </div>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Facebook Page ID (Widget Chat)</th>
            <td><input type="text" name="clbntb_id_fanpage" value="<?php echo esc_attr( get_option('clbntb_id_fanpage') ); ?>" />
            <p>Nhập Page ID để hiển thị Facebook Customer Chat (Tải kiểu Lazy load).</p>
            </td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Tiktok</th>
            <td><input type="text" name="clbntb_tiktok" value="<?php echo esc_attr( get_option('clbntb_tiktok') ); ?>" /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Telegram</th>
            <td><input type="text" name="clbntb_telegram" value="<?php echo esc_attr( get_option('clbntb_telegram') ); ?>" /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Instagram</th>
            <td><input type="text" name="clbntb_instagram" value="<?php echo esc_attr( get_option('clbntb_instagram') ); ?>" /></td>
            </tr>
             <tr valign="top">
            <th scope="row">Link Viber</th>
            <td><input type="text" name="clbntb_viber" value="<?php echo esc_attr( get_option('clbntb_viber') ); ?>" /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Whatsapp</th>
            <td><input type="text" name="clbntb_whatsapp" value="<?php echo esc_attr( get_option('clbntb_whatsapp') ); ?>" /></td>
            </tr>
            <tr valign="top">
            <th scope="row">Link Google Map</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_linkggmap" value="<?php echo esc_attr( get_option('clbntb_linkggmap') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_linkggmap" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_linkggmap') ); ?>" /></div>
                </div>
            </td>
            </tr>

            <tr valign="top">
            <th scope="row">Link Form Liên Hệ</th>
            <td>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <input type="text" name="clbntb_contact_link" value="<?php echo esc_attr( get_option('clbntb_contact_link') ); ?>" />
                    <div><strong>Màu nền:</strong> <input type="text" name="clbntb_color_clbntb_contact" class="clbntb_color" value="<?php echo esc_attr( get_option('clbntb_color_clbntb_contact') ); ?>" /></div>
                </div>
                <p>Bạn có thể chèn liên kết trang liên hệ hoặc sử dụng Shortcode. Nhớ thêm thuộc tính hiển thị kiểu Popup đối với Shortcode bằng cách thêm <strong style="color:red">[popup]</strong> phía trước. VD: <strong>[popup][contact-form-7 id="000" title="Contact form 1"]</strong></p>
            </td>
            </tr>
            
             
        </table>
        
        <?php submit_button(); ?>
        <?php else: ?>
            <p><input type="submit" name="submit" id="submit" class="button button-primary" value="Lưu mã kích hoạt"></p>
        <?php endif; ?>

    </form>
</div>