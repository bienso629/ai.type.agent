<?php
/**
 * Plugin Name: Floating Side Ads Manager
 * Description: Hiển thị quảng cáo trượt dọc hai bên trái và phải của website.
 * Version: 1.0
 * Author: Yên AI
 */

if ( ! defined( 'ABSPATH' ) ) exit;

// 1. Tạo menu cài đặt trong Admin
add_action('admin_menu', 'fsa_create_menu');
function fsa_create_menu() {
    add_options_page('Floating Ads Settings', 'Floating Ads', 'manage_options', 'fsa-settings', 'fsa_settings_page');
}

// 2. Giao diện trang cài đặt
function fsa_settings_page() {
    ?>
    <div class="wrap">
        <h1>Cài đặt Quảng cáo hai bên</h1>
        <form method="post" action="options.php">
            <?php
            settings_fields('fsa-settings-group');
            do_settings_sections('fsa-settings-group');
            ?>
            <table class="form-table">
                <tr>
                    <th>Mã quảng cáo bên TRÁI</th>
                    <td><textarea name="fsa_left_code" rows="10" cols="50" style="width:100%"><?php echo esc_textarea(get_option('fsa_left_code')); ?></textarea></td>
                </tr>
                <tr>
                    <th>Mã quảng cáo bên PHẢI</th>
                    <td><textarea name="fsa_right_code" rows="10" cols="50" style="width:100%"><?php echo esc_textarea(get_option('fsa_right_code')); ?></textarea></td>
                </tr>
                <tr>
                    <th>Chiều rộng (px)</th>
                    <td><input type="number" name="fsa_width" value="<?php echo esc_attr(get_option('fsa_width', '160')); ?>" /> px</td>
                </tr>
                <tr>
                    <th>Khoảng cách từ trên xuống (px)</th>
                    <td><input type="number" name="fsa_top" value="<?php echo esc_attr(get_option('fsa_top', '100')); ?>" /> px</td>
                </tr>
            </table>
            <?php submit_button(); ?>
        </form>
    </div>
    <?php
}

// 3. Đăng ký các field cài đặt
add_action('admin_init', 'fsa_register_settings');
function fsa_register_settings() {
    register_setting('fsa-settings-group', 'fsa_left_code');
    register_setting('fsa-settings-group', 'fsa_right_code');
    register_setting('fsa-settings-group', 'fsa_width');
    register_setting('fsa-settings-group', 'fsa_top');
}

// 4. Hiển thị quảng cáo ra Frontend
add_action('wp_footer', 'fsa_display_ads');
function fsa_display_ads() {
    $left_code = get_option('fsa_left_code');
    $right_code = get_option('fsa_right_code');
    $width = get_option('fsa_width', '160');
    $top = get_option('fsa_top', '100');

    if (empty($left_code) && empty($right_code)) return;

    ?>
    <style>
        .fsa-side-ad {
            position: fixed;
            top: <?php echo $top; ?>px;
            width: <?php echo $width; ?>px;
            z-index: 9999;
            display: none; /* Mặc định ẩn trên mobile */
        }
        .fsa-left { left: 10px; }
        .fsa-right { right: 10px; }

        @media (min-width: 1200px) {
            .fsa-side-ad { display: block; }
        }
    </style>

    <?php if (!empty($left_code)): ?>
        <div class="fsa-side-ad fsa-left"><?php echo $left_code; ?></div>
    <?php endif; ?>

    <?php if (!empty($right_code)): ?>
        <div class="fsa-side-ad fsa-right"><?php echo $right_code; ?></div>
    <?php endif; ?>
    <?php
}