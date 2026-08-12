<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

function clbntb_getUserIP() {
    // Cloudflare
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        return sanitize_text_field($_SERVER['HTTP_CF_CONNECTING_IP']);
    }

    // Proxy
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ipList = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        return sanitize_text_field(trim($ipList[0]));
    }

    // Fallback
    if (!empty($_SERVER['REMOTE_ADDR'])) {
        return sanitize_text_field($_SERVER['REMOTE_ADDR']);
    }

    return 'unknown';
}

// Tải assets
add_action('wp_enqueue_scripts', function () {
    if (isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) {
        return;
    }
    wp_enqueue_style('clbntb-chatbot-style', plugin_dir_url(CLBNTB_FILE) . 'dist/simple-chatbot-v5.css', [], filemtime(plugin_dir_path(CLBNTB_FILE) . 'dist/simple-chatbot-v5.css'));

    // Load JS vào frontend
    global $wp_version;
    $js_args = version_compare($wp_version, '6.3', '>=') ? ['in_footer' => true, 'strategy' => 'defer'] : true;
    
    // Register a dummy script to attach inline scripts
    wp_register_script('ai-type-chatbot-init', false);
    wp_enqueue_script('ai-type-chatbot-init');

    $vue_loader_script = "
    window.chatbotLoaded = false;
    window.clbntbInitChatbot = function() {
        if (window.chatbotLoaded) {
            if (typeof window.clbntbToggleChat === 'function') {
                window.clbntbToggleChat();
            }
            return;
        }
        window.chatbotLoaded = true;
        
        // Hiển thị trạng thái loading cho nút fake
        let fakeBtnIcon = document.querySelector('#chatbot-ui-ntbox img');
        if (fakeBtnIcon) {
            fakeBtnIcon.style.opacity = '0.5';
        }

        const loadScript = (src) => new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = src;
            script.onload = resolve;
            script.onerror = reject;
            document.head.appendChild(script);
        });

        Promise.all([
            loadScript('https://unpkg.com/vue@3/dist/vue.global.prod.js'),
            loadScript('https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.js')
        ]).then(() => {
            return loadScript('https://cdn.jsdelivr.net/npm/vue3-sfc-loader/dist/vue3-sfc-loader.js');
        }).then(() => {
            const options = {
                moduleCache: { vue: Vue },
                async getFile(url) {
                    const res = await fetch(url);
                    if (!res.ok) throw Object.assign(new Error(res.statusText + ' ' + url), { res });
                    return { getContentData: asBinary => asBinary ? res.arrayBuffer() : res.text() }
                },
                addStyle(textContent) {
                    const style = Object.assign(document.createElement('style'), { textContent });
                    const ref = document.head.getElementsByTagName('style')[0] || null;
                    document.head.insertBefore(style, ref);
                },
            };
            const { loadModule } = window['vue3-sfc-loader'];
            const app = Vue.createApp({
                components: { 'app-component': Vue.defineAsyncComponent(() => loadModule('" . plugin_dir_url(CLBNTB_FILE) . "App.vue?v=" . filemtime(plugin_dir_path(CLBNTB_FILE) . "App.vue") . "', options)) },
                template: '<app-component></app-component>'
            });
            
            let container = document.getElementById('chatbot-container');
            if (!container) {
                container = document.createElement('div');
                container.id = 'chatbot-container';
                document.body.appendChild(container);
            }
            
            // Set flag để tự động mở cửa sổ chat sau khi mount
            window.chatbotAutoOpen = true;
            
            // Đặt lại opacity cho nút fake
            let fakeBtnIcon = document.querySelector('#chatbot-ui-ntbox img');
            if (fakeBtnIcon) fakeBtnIcon.style.opacity = '1';
            
            app.mount('#chatbot-container');
        }).catch(err => console.error('Lỗi tải Chatbot:', err));
    };
    ";
    
    wp_add_inline_script('ai-type-chatbot-init', $vue_loader_script);

    $simple_chatbot_logo = get_option('simple_chatbot_logo');
    $simple_chatbot_image = get_option('simple_chatbot_image');

    // Tự động thay đổi đường dẫn ảnh sang CDN nếu có cấu hình
    $cdn_url = get_option('clbntb_cdn_url');
    if (!empty($cdn_url)) {
        $site_url = site_url();
        $domain = clbntb_get_cdn_domain();
        $cdn_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');
        
        if (!empty($simple_chatbot_logo)) {
            $simple_chatbot_logo = str_replace($site_url, $cdn_base, $simple_chatbot_logo);
        }
        if (!empty($simple_chatbot_image)) {
            $simple_chatbot_image = str_replace($site_url, $cdn_base, $simple_chatbot_image);
        }
    }

    // Truyền biến vào JS
    $ajax_relative = str_replace(site_url(), '', admin_url('admin-ajax.php'));
    $plugin_relative = str_replace(site_url(), '', plugin_dir_url(CLBNTB_FILE));
    
    $is_configured = !empty(get_option('simple_chatbot_app_token'));

    wp_add_inline_script('ai-type-chatbot-init', 'window.ChatbotSettings = ' . json_encode([
        'pluginUrl' => $plugin_relative,
        'ajax_url' => $ajax_relative,
        'simple_chatbot_logo' => $simple_chatbot_logo,
        'simple_chatbot_image' => $simple_chatbot_image,
        'is_configured' => $is_configured
    ]) . ';', 'before');
});

// Chatbot container is now rendered inside button-contact.php to group it with other buttons.

add_action('wp_ajax_register_user', 'clbntb_chatbot_register_user');
add_action('wp_ajax_nopriv_register_user', 'clbntb_chatbot_register_user');
function clbntb_chatbot_register_user() {
    $input = json_decode(file_get_contents('php://input'), true);
    $name = sanitize_text_field($input['name']);
    $email = sanitize_email($input['email']);
    $phone = sanitize_text_field($input['phone']);

    if (!$name || !$email || !$phone) {
        wp_send_json_error(['message' => 'Thiếu thông tin']);
		wp_die();
    }

    $simple_chatbot_app_token = get_option('simple_chatbot_app_token');
    $simple_chatbot_api = get_option('simple_chatbot_api');
    $simple_chatbot_username = get_option('simple_chatbot_username');

	$url = rtrim($simple_chatbot_api, '/') . '/threads';

    $args = [
        'timeout' => 45,
        'headers' => [
            'Content-Type' => 'application/json',
            'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'X-Api-Key' => $simple_chatbot_app_token
        ],
        'body' => wp_json_encode([
            'username' => $simple_chatbot_username,
            'name'     => $name,
            'email'    => $email,
            'phone'    => $phone,
            'appId'    => 'ai.typing',
            'year'     => 2023,
            'appToken' => $simple_chatbot_app_token
        ])
    ];

    $response = wp_remote_post($url, $args);

    if (is_wp_error($response)) {
        // xử lý lỗi
		wp_send_json(['error' => [
			'message' => $response->get_error_message()
		]]);

        wp_die();
    }

    // Lấy body dạng string
    $raw = wp_remote_retrieve_body($response);

    wp_send_json(['user' => [
		'name' => $name,
		'email' => $email,
		'phone' => $phone,
		'thread_id' => $raw
	]]);
    
    wp_die();
}

// AJAX xử lý chat history
add_action('wp_ajax_nopriv_get_chat_history', 'clbntb_wp_get_chat_history');
add_action('wp_ajax_get_chat_history', 'clbntb_wp_get_chat_history');
function clbntb_wp_get_chat_history() {
    $thread_id = sanitize_text_field($_GET['thread_id'] ?? '');
    if (!$thread_id) {
        wp_send_json(['success' => false, 'message' => 'Missing thread_id']);
        wp_die();
    }

    $simple_chatbot_app_token = get_option('simple_chatbot_app_token');
    $simple_chatbot_api = get_option('simple_chatbot_api');
    
    // Nếu chưa cấu hình, trả về mảng rỗng để không bị lỗi trên Frontend
    if (empty($simple_chatbot_app_token) || empty($simple_chatbot_api)) {
        wp_send_json(['success' => true, 'data' => []]);
        wp_die();
    }

    $url = rtrim($simple_chatbot_api, '/') . '/threads/' . $thread_id . '/messages';

    $args = [
        'timeout' => 15,
        'headers' => [
            'Content-Type' => 'application/json',
            'X-Api-Key' => $simple_chatbot_app_token
        ]
    ];

    $response = wp_remote_get($url, $args);

    if (is_wp_error($response)) {
        wp_send_json(['success' => false, 'message' => $response->get_error_message()]);
        wp_die();
    }

    $body = wp_remote_retrieve_body($response);
    $data = json_decode($body, true);

    if (is_array($data) && isset($data['data'])) {
        wp_send_json(['success' => true, 'data' => $data['data']]);
    } else {
        wp_send_json(['success' => true, 'data' => is_array($data) ? $data : []]);
    }
    wp_die();
}

// AJAX xử lý chat
add_action('wp_ajax_nopriv_handle_chat', 'clbntb_wp_handle_chat');
add_action('wp_ajax_handle_chat', 'clbntb_wp_handle_chat');
function clbntb_wp_handle_chat() {
    $input = json_decode(file_get_contents('php://input'), true);
    $msg = sanitize_text_field($input['message'] ?? '');
    $thread_id = sanitize_text_field($input['thread_id'] ?? '');
	
	$google_api_key = get_option('google_api_key');
    $llm_model = get_option('llm_model', 'gemini-3.5-flash');
    $simple_chatbot_app_token = get_option('simple_chatbot_app_token');
    $simple_chatbot_data_source = get_option('simple_chatbot_data_source');

    if (!$google_api_key || !$msg) {
        wp_send_json(['reply' => 'Missing API key or message']);
        wp_die();
    }

    $domainOnly = explode(':', $_SERVER['HTTP_HOST'])[0];
	$ip_address = clbntb_getUserIP();
	$user_agent = $_SERVER['HTTP_USER_AGENT'] ?? 'unknown';

    $simple_chatbot_api = get_option('simple_chatbot_api');
    $simple_chatbot_username = get_option('simple_chatbot_username');

    $response = wp_remote_post($simple_chatbot_api . "/messages", [
		'method'    => 'POST',
    	'timeout'   => 45,
        'headers' => [
            'Content-Type' => 'application/json',
            'X-Api-Key' => $simple_chatbot_app_token
        ],
        'body' => json_encode([
            'username' => $simple_chatbot_username,
            'message' => $msg,
            'thread_id' => $thread_id,
			'ip_address' => $ip_address,
    		'sender_info' => $user_agent,
            'simple_chatbot_data_source' => $simple_chatbot_data_source,
			'llm_model' => $llm_model,
			'google_api_key' => $google_api_key,
			'index_dir' => 'faiss_pdf_index',
            'appId' => 'ai.typing',
            'year' => 2023,
            'appToken' => $simple_chatbot_app_token
        ])
    ]);
	
	if ( is_wp_error($response) ) {
        error_log("Simple Chatbot Connection Error: " . $response->get_error_message());
        wp_send_json(['reply' => ['content' => "Chatbot chưa thể phục vụ bạn lúc này. Vui lòng thử lại sau!"]]);
        wp_die();
    }

    $body = wp_remote_retrieve_body($response);
    
    // Xử lý nếu API trả về dạng SSE Stream (data: {...})
    $full_content = "";
    $error_msg = "";
    if (strpos($body, 'data:') !== false) {
        $lines = explode("\n", $body);
        foreach ($lines as $line) {
            if (strpos($line, 'data: ') === 0) {
                $json = json_decode(substr($line, 6), true);
                if (is_array($json)) {
                    if (isset($json['chunk'])) {
                        $full_content .= $json['chunk'];
                    }
                    if (isset($json['error'])) {
                        $error_msg = $json['error'];
                    }
                }
            }
        }
        
        if ($error_msg) {
            error_log("Simple Chatbot AI Error: " . $error_msg);
            wp_send_json(['reply' => ['content' => "Chatbot chưa thể phục vụ bạn lúc này. Vui lòng thử lại sau!"]]);
            wp_die();
        }
        
        if ($full_content) {
            wp_send_json(['reply' => ['content' => $full_content]]);
            wp_die();
        }
    }

    // Fallback cho JSON bình thường
    $data = json_decode($body, true);
    if (!is_array($data)) {
        error_log("Simple Chatbot API Format Error: " . substr(strip_tags((string)$body), 0, 500));
        wp_send_json(['reply' => ['content' => "Chatbot chưa thể phục vụ bạn lúc này. Vui lòng thử lại sau!"]]);
        wp_die();
    }
    wp_send_json(['reply' => $data]);
    wp_die();
}

add_action('wp_ajax_get_chat_history', 'clbntb_chatbot_get_chat_history');
add_action('wp_ajax_nopriv_get_chat_history', 'clbntb_chatbot_get_chat_history');
function clbntb_chatbot_get_chat_history() {
    $thread_id = sanitize_text_field($_GET['thread_id'] ?? '');

    if (!$thread_id) {
        wp_send_json_error('Missing thread_id');
    }

    $simple_chatbot_app_token = get_option('simple_chatbot_app_token');
    $simple_chatbot_api = get_option('simple_chatbot_api');
    $simple_chatbot_username = get_option('simple_chatbot_username');

    $url = $simple_chatbot_api . "/messages/" . $simple_chatbot_username . "/" . $thread_id;

    $response = wp_remote_get($url, [
		'method'    => 'GET',
    	'timeout'   => 45,
        'headers' => [
            'Content-Type' => 'application/json',
            'X-Api-Key' => $simple_chatbot_app_token
        ]
    ]);

    if (is_wp_error($response)) {
        wp_send_json_error('Không lấy được lịch sử chat');
    }

    $body = wp_remote_retrieve_body($response);
    $data = json_decode($body, true);

    if (!is_array($data)) {
        wp_send_json_error([]);
    }

    wp_send_json_success($data);
    wp_die();
}
