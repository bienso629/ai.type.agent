<?php

final class CLBNTB {

    protected static $_instance = null;

    public static function instance() {
        if (is_null(self::$_instance)) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }

    public function __construct() {
        if (did_action('plugins_loaded')) {
            $this->init_hooks();
        } else {
            add_action('plugins_loaded', [$this, 'init_hooks']);
        }
    }

    public function init_hooks() {
        add_action('wp_footer', [$this, 'clbntb_frontend']);
        add_action('wp_enqueue_scripts', [$this, 'enqueue_scripts']);
        add_action('admin_enqueue_scripts', [$this, 'mw_enqueue_color_picker']);
    }

    public function enqueue_scripts() {
        if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) {
            return;
        }
        wp_register_style('clbntb-style', CLBNTB_URL . 'css/style.css', array(), filemtime(CLBNTB_PATH . '/css/style.css'));
        wp_enqueue_style('clbntb-style');
        
        $dynamic_css = $this->generate_dynamic_css();
        if (!empty($dynamic_css)) {
            wp_add_inline_style('clbntb-style', $dynamic_css);
        }
    }

    private function generate_dynamic_css() {
        $css = '';
        
        $chatbot_image = get_option('simple_chatbot_image');
        if ($chatbot_image) {
            $custom_color = '#ffb300';
            $css .= '
                #chatbot-ui-ntbox .phone-ntbox-circle-fill {
                    box-shadow: 0 0 0 0 ' . $custom_color . ';
                    background-color: rgba(255, 179, 0, 0.7) !important;
                }
                #chatbot-ui-ntbox .phone-ntbox-img-circle {
                    background-color: ' . $custom_color . ' !important;
                }
                #chatbot-ui-ntbox .phone-ntbox-img-circle img {
                    max-width: 32px;
                    max-height: 32px;
                    width: 100%;
                    height: 100%;
                    border-radius: 50% !important;
                    overflow: hidden !important;
                    object-fit: cover !important;
                }
            ';
        }

        $location = get_option('clbntb_location', 2);
        $chatbox_alignment = ($location == 2 || $location === 'right') ? 'right: 110px !important; left: auto !important;' : 'left: 110px !important; right: auto !important;';
        $toggle_bg_color = get_option('clbntb_toggle_bg_color', '');
        if (empty($toggle_bg_color)) {
            $toggle_bg_color = 'transparent';
        }

        $css .= '
            .simple-chatbot #chatbot-toggle {
                display: none !important;
            }
            .simple-chatbot .chatbox {
                position: fixed !important;
                bottom: 20px !important;
                margin-bottom: 0 !important;
                width: 440px !important;
                max-width: calc(100vw - 120px) !important;
                ' . $chatbox_alignment . '
                z-index: 999999 !important;
            }
            @media (max-width: 768px) {
                .simple-chatbot .chatbox {
                    max-width: calc(100vw - 40px) !important;
                    left: 20px !important;
                    right: 20px !important;
                }
            }
            
            /* Hieu ung Chỉ tỏa sáng (Không lắc) */
            .effect-type-zoom_only .phone-ntbox-circle-fill,
            .effect-type-zoom_only .phone-ntbox-img-circle {
                animation-name: zoom !important;
                transform-origin: center center;
            }
            
            /* Fix lỗi tác giả plugin viết sai class Kích thước */
            #button-contact-ntbox.size-3 { transform: scale(0.85) !important; }
            #button-contact-ntbox.size-1 { transform: scale(1) !important; }
            #button-contact-ntbox.size-2 { transform: scale(1.2) !important; }
            
            #button-contact-ntbox.loco-left { transform-origin: left bottom !important; }
            #button-contact-ntbox.loco-right { transform-origin: right bottom !important; }
            
            /* Giảm khoảng cách giữa các nút - giãn ra một chút so với trước */
            #button-contact-ntbox .button-contact {
                margin-top: -12px !important;
            }
            
            /* Fix Căn giữa hoàn hảo cho các vòng tròn */
            .simple-chatbot .phone-ntbox-circle-fill {
                top: 50% !important;
                left: 50% !important;
                transform: translate(-50%, -50%) !important;
            }
            .simple-chatbot .phone-ntbox-img-circle {
                top: 50% !important;
                left: 50% !important;
                transform: translate(-50%, -50%) !important;
            }

            /* Layout Ngang (Horizontal) */
            #button-contact-ntbox.layout-horizontal {
                display: flex !important;
                flex-direction: row-reverse !important;
                align-items: center;
                gap: 5px;
            }
            #button-contact-ntbox.layout-horizontal.loco-left {
                flex-direction: row !important;
            }
            #button-contact-ntbox.layout-horizontal .button-contact {
                margin-top: 0 !important;
            }
            #button-contact-ntbox.layout-horizontal .phone-ntbox-title {
                display: none !important;
            }

            /* Layout Collapse (Thu gọn) */
            #button-contact-ntbox.layout-collapse {
                display: flex !important;
                flex-direction: column-reverse;
                gap: 15px;
            }
            #button-contact-ntbox.layout-collapse .button-contact:not(#clbntb-menu-toggle) {
                display: none;
                z-index: 1;
            }
            #button-contact-ntbox.layout-collapse.expanded .button-contact:not(#clbntb-menu-toggle) {
                display: flex;
                animation: clbntb-slideUp 0.3s cubic-bezier(0.68, -0.55, 0.265, 1.55) forwards;
            }
            @keyframes clbntb-slideUp {
                from { opacity: 0; transform: translateY(30px) scale(0.5); }
                to { opacity: 1; transform: translateY(0) scale(1); }
            }
            #clbntb-menu-toggle {
                display: none;
                cursor: pointer;
                position: relative;
                z-index: 100;
                margin-top: 45px;
                order: -100; /* Đưa xuống dưới cùng trong column-reverse */
            }
            #button-contact-ntbox.layout-collapse #clbntb-menu-toggle {
                display: block;
            }
            #clbntb-menu-toggle .phone-ntbox-circle-fill {
                display: none !important; /* Tắt vòng tỏa sáng */
            }
            #clbntb-menu-toggle .phone-ntbox-img-circle {
                background-color: ' . esc_attr($toggle_bg_color) . ' !important;
                transition: all 0.3s ease;
                display: flex;
                align-items: center;
                justify-content: center;
                width: 150px !important;
                height: 150px !important;
                top: -30px !important;
                left: -30px !important;
            }
            #clbntb-menu-toggle .phone-ntbox-img-circle img {
                max-width: 100% !important;
                max-height: 100% !important;
                border-radius: 50% !important;
                overflow: hidden !important;
                object-fit: cover !important;
            }
            #button-contact-ntbox.layout-collapse.expanded #clbntb-menu-toggle .phone-ntbox-img-circle {
                transform: rotate(360deg) !important;
                /* Giữ nguyên màu nền đã cấu hình, không bị đổi sang đỏ nữa */
            }

            .simple-chatbot .phone-ntbox-img-circle {
                /* Thu nhỏ vòng tròn background một chút và căn giữa lại */
                width: 36px !important;
                height: 36px !important;
                top: 27px !important;
                left: 27px !important;
                box-sizing: border-box !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
            }
            .simple-chatbot .phone-ntbox-img-circle a {
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
                width: 100% !important;
                height: 100% !important;
            }
            .simple-chatbot .phone-ntbox-img-circle img {
                position: static !important;
                transform: none !important;
                max-width: 65% !important;
                max-height: 65% !important;
                margin: 0 !important;
            }
            
            /* Giữ lại animation zoom/lắc */
            @keyframes zoom {
                0% { transform: scale(0.9); }
                70% { transform: scale(1); box-shadow: 0 0 0 15px transparent; }
                100% { transform: scale(0.9); box-shadow: 0 0 0 0 transparent; }
            }
            @-webkit-keyframes zoom {
                0% { transform: scale(0.9); }
                70% { transform: scale(1); box-shadow: 0 0 0 15px transparent; }
                100% { transform: scale(0.9); box-shadow: 0 0 0 0 transparent; }
            }
            
            /* Hieu ung Nhip tim (Heartbeat) */
            @keyframes heartbeat-ntbox {
                0% { transform: scale(1); }
                14% { transform: scale(1.3); }
                28% { transform: scale(1); }
                42% { transform: scale(1.3); }
                70% { transform: scale(1); }
            }
            .effect-type-heartbeat .phone-ntbox-circle-fill,
            .effect-type-heartbeat .phone-ntbox-img-circle {
                animation: heartbeat-ntbox 1.5s infinite ease-in-out !important;
                box-shadow: none !important;
            }
            
            /* Hieu ung Xoay tron (Spinning) */
            @keyframes spin-ntbox {
                100% { transform: rotate(360deg); }
            }
            .effect-type-spin .phone-ntbox-circle-fill {
                animation: zoom 1.3s infinite !important;
            }
            .effect-type-spin .phone-ntbox-img-circle {
                animation: spin-ntbox 3s linear infinite !important;
                transform-origin: center center;
            }
            
            /* Hieu ung Nhun nhay (Bouncing) */
            @keyframes bounce-ntbox {
                0%, 100% { transform: translateY(0); }
                40% { transform: translateY(-12px); }
                60% { transform: translateY(-5px); }
            }
            .effect-type-bounce .phone-ntbox {
                animation: bounce-ntbox 1.5s infinite ease-in-out !important;
            }
            .effect-type-bounce .phone-ntbox-circle-fill {
                animation: zoom 1.3s infinite !important;
            }
            
            /* Hieu ung Sang mo dan (Fade Glow) */
            @keyframes fade-glow-ntbox {
                0%, 100% { transform: scale(0.9); opacity: 0.5; box-shadow: 0 0 0 0 transparent; }
                50% { transform: scale(1.1); opacity: 1; box-shadow: 0 0 0 10px transparent; }
            }
            .effect-type-fade_glow .phone-ntbox-circle-fill {
                animation: fade-glow-ntbox 2s infinite ease-in-out !important;
            }
            
            /* Hieu ung Rung chuong (Ringing) */
            @keyframes ring-ntbox {
                0% { transform: rotate(0deg); }
                10% { transform: rotate(20deg); }
                20% { transform: rotate(-15deg); }
                30% { transform: rotate(10deg); }
                40% { transform: rotate(-5deg); }
                50%, 100% { transform: rotate(0deg); }
            }
            .effect-type-ring .phone-ntbox-img-circle {
                animation: ring-ntbox 2s infinite ease-in-out !important;
                transform-origin: center center;
            }
            .effect-type-ring .phone-ntbox-circle-fill {
                animation: zoom 1.3s infinite !important;
            }
            
            /* Wobble effect */
            @keyframes clbntb-wobble {
              0% { transform: translate(-50%, -50%) translateX(0%); }
              15% { transform: translate(-50%, -50%) translateX(-25%) rotate(-5deg); }
              30% { transform: translate(-50%, -50%) translateX(20%) rotate(3deg); }
              45% { transform: translate(-50%, -50%) translateX(-15%) rotate(-3deg); }
              60% { transform: translate(-50%, -50%) translateX(10%) rotate(2deg); }
              75% { transform: translate(-50%, -50%) translateX(-5%) rotate(-1deg); }
              100% { transform: translate(-50%, -50%) translateX(0%); }
            }
            .effect-type-wobble .phone-ntbox-img-circle img {
                animation: clbntb-wobble 2s infinite !important;
            }

            /* Tada effect */
            @keyframes clbntb-tada {
              0% { transform: translate(-50%, -50%) scale3d(1, 1, 1); }
              10%, 20% { transform: translate(-50%, -50%) scale3d(.9, .9, .9) rotate3d(0, 0, 1, -3deg); }
              30%, 50%, 70%, 90% { transform: translate(-50%, -50%) scale3d(1.1, 1.1, 1.1) rotate3d(0, 0, 1, 3deg); }
              40%, 60%, 80% { transform: translate(-50%, -50%) scale3d(1.1, 1.1, 1.1) rotate3d(0, 0, 1, -3deg); }
              100% { transform: translate(-50%, -50%) scale3d(1, 1, 1); }
            }
            .effect-type-tada .phone-ntbox-img-circle img {
                animation: clbntb-tada 2s infinite !important;
            }
        ';

        $custom_css = get_option('clbntb_custom_css');
        if (!empty($custom_css)) {
            $css .= strip_tags($custom_css);
        }

        // Add CSS for each configured button color
        $buttons = [
            'map' => ['option' => 'clbntb_linkggmap', 'color' => ''],
            'contact' => ['option' => 'clbntb_contact_link', 'color' => ''],
            'viber' => ['option' => 'clbntb_viber', 'color' => ''],
            'fanpage' => ['option' => 'clbntb_linkfanpage', 'color' => ''],
            'messenger' => ['option' => 'clbntb_linkmessenger', 'color' => ''],
            'tiktok' => ['option' => 'clbntb_tiktok', 'color' => ''],
            'telegram' => ['option' => 'clbntb_telegram', 'color' => ''],
            'instagram' => ['option' => 'clbntb_instagram', 'color' => ''],
            'youtube' => ['option' => 'clbntb_youtube', 'color' => ''],
            'zalo' => ['option' => 'clbntb_zalo', 'color' => ''],
            'whatsapp' => ['option' => 'clbntb_whatsapp', 'color' => ''],
            'phone' => ['option' => 'clbntb_phone', 'color' => 'clbntb_color_clbntb_phone'],
            'phone2' => ['option' => 'clbntb_phone2', 'color' => 'clbntb_color_clbntb_phone2'],
            'phone3' => ['option' => 'clbntb_phone3', 'color' => 'clbntb_color_clbntb_phone3']
        ];

        foreach ($buttons as $key => $button) {
            $option_value = get_option($button['option']);
            if ($option_value && !empty($button['color'])) {
                $custom_color = get_option($button['color']);
                if (!empty($custom_color) && preg_match('/^#([a-f0-9]{3}){1,2}$/i', $custom_color)) {
                    $hex = ltrim($custom_color, '#');
                    if (strlen($hex) == 3) {
                        $r = hexdec(substr($hex, 0, 1) . substr($hex, 0, 1));
                        $g = hexdec(substr($hex, 1, 1) . substr($hex, 1, 1));
                        $b = hexdec(substr($hex, 2, 1) . substr($hex, 2, 1));
                    } else {
                        $r = hexdec(substr($hex, 0, 2));
                        $g = hexdec(substr($hex, 2, 2));
                        $b = hexdec(substr($hex, 4, 2));
                    }
                    $rgba = "rgba($r, $g, $b, 0.7)";
                    $css .= "
                        #{$key}-ntbox .phone-ntbox-circle-fill {
                            box-shadow: 0 0 0 0 {$custom_color};
                            background-color: {$rgba} !important;
                        }
                        #{$key}-ntbox .phone-ntbox-img-circle {
                            background-color: {$custom_color} !important;
                        }
                    ";
                }
            }
        }

        return $css;
    }

    public function mw_enqueue_color_picker() {
        wp_enqueue_style('wp-color-picker');
        wp_enqueue_script('my-script-handle', CLBNTB_URL . '/inc/js/script.js', ['wp-color-picker'], '1.0.1', true);
    }

    public function clbntb_frontend() {
        if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) {
            return;
        }
        $buttons = [
            'map' => ['option' => 'clbntb_linkggmap', 'color' => '', 'img' => 'showroom4.webp', 'alt' => 'Google Map'],
            'contact' => ['option' => 'clbntb_contact_link', 'color' => '', 'img' => 'contact.webp', 'alt' => 'Liên hệ'],
            'viber' => ['option' => 'clbntb_viber', 'color' => '', 'url' => 'viber://add?number=', 'img' => 'viber.webp', 'alt' => 'Viber'],
            'fanpage' => ['option' => 'clbntb_linkfanpage', 'color' => '', 'img' => 'Facebook.webp', 'alt' => 'Fanpage'],
            'messenger' => ['option' => 'clbntb_linkmessenger', 'color' => '', 'img' => 'messenger.webp', 'alt' => 'Messenger'],
            'tiktok' => ['option' => 'clbntb_tiktok', 'color' => '', 'img' => 'tiktok.webp', 'alt' => 'Tiktok'],
            'telegram' => ['option' => 'clbntb_telegram', 'color' => '', 'img' => 'telegram.webp', 'alt' => 'Telegram'],
            'instagram' => ['option' => 'clbntb_instagram', 'color' => '', 'img' => 'instagram.webp', 'alt' => 'Instagram'],
            'youtube' => ['option' => 'clbntb_youtube', 'color' => '', 'img' => 'youtube.webp', 'alt' => 'Youtube'],
            'zalo' => ['option' => 'clbntb_zalo', 'color' => '', 'url' => 'https://zalo.me/', 'img' => 'zalo.webp', 'alt' => 'Zalo'],
            'whatsapp' => ['option' => 'clbntb_whatsapp', 'color' => '', 'url' => 'https://wa.me/', 'img' => 'whatsapp.webp', 'alt' => 'Whatsapp'],
            'phone' => ['option' => 'clbntb_phone', 'color' => 'clbntb_color_clbntb_phone', 'url' => 'tel:', 'img' => 'phone.webp', 'alt' => 'Phone'],
            'phone2' => ['option' => 'clbntb_phone2', 'color' => 'clbntb_color_clbntb_phone2', 'url' => 'tel:', 'img' => 'phone.webp', 'alt' => 'Phone'],
            'phone3' => ['option' => 'clbntb_phone3', 'color' => 'clbntb_color_clbntb_phone3', 'url' => 'tel:', 'img' => 'phone.webp', 'alt' => 'Phone']
        ];

        $loco_val = get_option('clbntb_location', 2);
        $loco_class = ($loco_val == 2 || $loco_val === 'right') ? 'loco-right' : 'loco-left';
        
        $effect_type = get_option('clbntb_effect_type', 'default');
        $layout_type = get_option('clbntb_layout_type', 'vertical');
        $toggle_bg_color = get_option('clbntb_toggle_bg_color', '');
        if (empty($toggle_bg_color)) {
            $toggle_bg_color = 'transparent';
        }

        ob_start();

        echo '<div style="bottom: 0'.esc_attr(get_option('clbntb_location_bottom')).'%;" id="button-contact-ntbox" 
        class="size-'. esc_attr(get_option('setting_size')) . ' '
            . $loco_class . ' '
            . 'layout-' . esc_attr($layout_type) . ' '
            . 'effect-type-' . esc_attr($effect_type) . ' '
            . 'mobile' . esc_attr(get_option('clbntb_hide_mobile')) . ' '
            . 'pc' . esc_attr(get_option('clbntb_hide_desktop')) . '">';
            
        // Embed the chatbot container here so it stacks with the other buttons
        $popups_html = '';
        foreach ($buttons as $key => $button) {
            $popups_html .= $this->render_button($button, $key);
        }

        $chatbot_image = str_replace('.png', '.webp', get_option('simple_chatbot_image'));
        $cdn_url = get_option('clbntb_cdn_url');
        if (!empty($cdn_url) && !empty($chatbot_image)) {
            $site_url = site_url();
            $domain = clbntb_get_cdn_domain();
            $cdn_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
            $chatbot_image = str_replace($site_url, $cdn_base, $chatbot_image);
        }

        if ($chatbot_image) {
            echo '<div id="chatbot-ui-ntbox" class="button-contact">
                    <div class="phone-ntbox">
                        <div class="phone-ntbox-circle-fill"></div>
                        <div class="phone-ntbox-img-circle">
                            <a href="#" onclick="event.preventDefault(); event.stopPropagation(); if(typeof window.clbntbInitChatbot === \'function\') window.clbntbInitChatbot(); return false;">
                                <img loading="lazy" alt="Chatbot" src="' . esc_url($chatbot_image) . '" />
                            </a>
                        </div>
                    </div>
                  </div>';
        }

        if ($layout_type === 'collapse') {
            $chatbot_img_src = $chatbot_image; // Tái sử dụng biến đã được replace CDN ở trên
            $toggle_icon = $chatbot_img_src ? '<img loading="lazy" src="'.esc_url($chatbot_img_src).'" alt="Toggle" style="max-width:32px;max-height:32px;" />' : '<svg fill="#fff" viewBox="0 0 24 24" width="24" height="24"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>';
            
            echo '<div id="clbntb-menu-toggle" class="button-contact">
                    <div class="phone-ntbox" style="visibility: visible;">
                        <div class="phone-ntbox-circle-fill"></div>
                        <div class="phone-ntbox-img-circle">
                            ' . $toggle_icon . '
                        </div>
                    </div>
                  </div>';
            echo '<script>
                document.addEventListener("DOMContentLoaded", function() {
                    var toggleBtn = document.getElementById("clbntb-menu-toggle");
                    var ntbox = document.getElementById("button-contact-ntbox");
                    if(toggleBtn && ntbox) {
                        toggleBtn.addEventListener("click", function(e) {
                            e.preventDefault();
                            ntbox.classList.toggle("expanded");
                            
                            // Nếu layout thu gọn, mở/đóng Chatbot luôn
                            if (ntbox.classList.contains("layout-collapse")) {
                                var realChatbotToggle = document.getElementById("chatbot-toggle");
                                if (realChatbotToggle) {
                                    realChatbotToggle.click();
                                }
                            }
                        });
                    }
                });
            </script>';
        }

        echo '</div>';
        echo $popups_html;
        
        $zalo_oa_id = get_option('clbntb_zalo_oa_id');
        $fb_page_id = get_option('clbntb_id_fanpage');
        
        if (!empty($zalo_oa_id) || !empty($fb_page_id)) {
            echo '<script>
                document.addEventListener("DOMContentLoaded", function() {
                    var socialLoaded = false;
                    function loadSocialWidgets() {
                        if (socialLoaded) return;
                        socialLoaded = true;
            ';
            if (!empty($zalo_oa_id)) {
                echo '
                        var zaloDiv = document.createElement("div");
                        zaloDiv.className = "zalo-chat-widget";
                        zaloDiv.setAttribute("data-oaid", "' . esc_attr($zalo_oa_id) . '");
                        zaloDiv.setAttribute("data-welcome-message", "Rất vui khi được hỗ trợ bạn!");
                        zaloDiv.setAttribute("data-autopopup", "0");
                        zaloDiv.setAttribute("data-width", "350");
                        zaloDiv.setAttribute("data-height", "420");
                        document.body.appendChild(zaloDiv);
                        
                        var zaloScript = document.createElement("script");
                        zaloScript.src = "https://sp.zalo.me/plugins/sdk.js";
                        document.body.appendChild(zaloScript);
                ';
            }
            if (!empty($fb_page_id)) {
                echo '
                        var fbDiv = document.createElement("div");
                        fbDiv.id = "fb-root";
                        document.body.appendChild(fbDiv);
                        
                        var fbChat = document.createElement("div");
                        fbChat.className = "fb-customerchat";
                        fbChat.setAttribute("attribution", "biz_inbox");
                        fbChat.setAttribute("page_id", "' . esc_attr($fb_page_id) . '");
                        document.body.appendChild(fbChat);
                        
                        window.fbAsyncInit = function() {
                            FB.init({
                              xfbml            : true,
                              version          : "v18.0"
                            });
                        };
                        var fbScript = document.createElement("script");
                        fbScript.src = "https://connect.facebook.net/vi_VN/sdk/xfbml.customerchat.js";
                        document.body.appendChild(fbScript);
                ';
            }
            echo '
                    }
                    window.addEventListener("scroll", loadSocialWidgets, { once: true, passive: true });
                    window.addEventListener("mousemove", loadSocialWidgets, { once: true, passive: true });
                    window.addEventListener("touchstart", loadSocialWidgets, { once: true, passive: true });
                });
            </script>';
        }
        
        $clbntb_html = ob_get_clean();

        // Xuất trực tiếp HTML danh sách nút ngay khi tải trang (hiển thị lập tức 0ms)
        echo $clbntb_html;
    }

    private function get_active_class() {
        if (get_option('clbntb_hide_default_all_in_one')) {
            return '';
        }
        return get_option('clbntb_enable_all_in_one') ? 'active' : '';
    }
    //  * Version: 1.1
    private function render_button($button, $key) {
    $option_value = get_option($button['option']);
    if ($option_value) {
        $is_popup = false;
        $shortcode_content = '';
        if (strpos(trim($option_value), '[popup]') === 0) {
            $is_popup = true;
            $shortcode_content = substr(trim($option_value), 7);
        }

        $sanitized_value = sanitize_text_field($option_value);
        if ($is_popup) {
            $url = '#';
            $onclick = 'onclick="document.getElementById(\'popup-form-contact-ntbox\').classList.add(\'active\'); return false;"';
        } else {
            $url = isset($button['url']) ? $button['url'] . esc_html(preg_replace('/\D/', '', $sanitized_value)) : esc_url($sanitized_value);
            $onclick = '';
        }

        $custom_color = get_option($button['color']);

        echo '<div id="' . esc_attr($key) . '-ntbox" class="button-contact" data-color="'.esc_attr($custom_color).'">
                <div class="phone-ntbox">
                    <div class="phone-ntbox-circle-fill"></div>
                    <div class="phone-ntbox-img-circle">
                        <a ' . ($is_popup ? '' : 'target="_blank"') . ' href="' . esc_attr($url) . '" ' . $onclick . '>
                            <img loading="lazy" alt="' . esc_attr($button['alt']) . '" src="' . esc_url(CLBNTB_URL . 'img/' . $button['img']) . '" />
                        </a>
                    </div>
                </div>
              </div>';
              
        if ($is_popup) {
            $popup_html = '<div id="popup-form-contact-ntbox">
                <div class="bg-popup-ntbox" onclick="document.getElementById(\'popup-form-contact-ntbox\').classList.remove(\'active\');"></div>
                <div class="content-popup-ntbox">
                    <div class="close-popup-ntbox" onclick="document.getElementById(\'popup-form-contact-ntbox\').classList.remove(\'active\');">x</div>
                    <div class="content-popup-div-ntbox">
                        ' . do_shortcode($shortcode_content) . '
                    </div>
                </div>
            </div>';
            return $popup_html;
        }
        return '';
    }
}
}

// Khởi tạo Singleton cho Nút liên hệ (button-contact)
CLBNTB::instance();