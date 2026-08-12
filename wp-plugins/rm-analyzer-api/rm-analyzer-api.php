<?php
/**
 * Plugin Name: RM Analyzer API
 * Description: REST API để gọi Rank Math SEO Analyzer cho URL bất kỳ. Xác thực bằng header x-app-token. Có debug & fallback.
 * Version: 1.1.0
 * Author: bạn
 */

if ( ! defined('ABSPATH') ) exit;

const RM_API_OPTION_TOKEN = 'rm_analyzer_api_token';
// define('RM_ANALYZER_FIXED_TOKEN', 'YOUR_SUPER_SECRET_TOKEN'); // (tùy chọn) hard-code token

/** =============== CORS cho route này =============== */
add_action('rest_api_init', function () {
    add_filter('rest_pre_serve_request', function ($served, $result, $request, $server) {
        $route = method_exists($request, 'get_route') ? $request->get_route() : '';
        if (strpos($route, '/rm-analyzer/v1/') === 0) {
            header('Access-Control-Allow-Origin: *'); // thay * = origin của bạn nếu muốn siết
            header('Vary: Origin');
            header('Access-Control-Allow-Headers: content-type, x-app-token, x-debug');
            header('Access-Control-Allow-Methods: POST, OPTIONS, GET');
        }
        return $served;
    }, 11, 4);
});

/** =============== Đăng ký endpoints =============== */
add_action('rest_api_init', function () {

    // Ping kiểm tra token
    register_rest_route('rm-analyzer/v1', '/ping', [
        'methods'  => 'GET',
        'callback' => function (\WP_REST_Request $req) {
            if (!rm_api_auth_ok($req)) return rm_api_error(401, 'Unauthorized');
            return new \WP_REST_Response(['success' => true, 'message' => 'pong'], 200);
        },
        'permission_callback' => '__return_true',
    ]);

    // Debug kết nối / cấu hình
    register_rest_route('rm-analyzer/v1', '/debug', [
        'methods'  => 'GET',
        'callback' => function (\WP_REST_Request $req) {
            if (!rm_api_auth_ok($req)) return rm_api_error(401, 'Unauthorized');
            $r = rm_api_connectivity_report();
            return new \WP_REST_Response(['success' => true, 'report' => $r], 200);
        },
        'permission_callback' => '__return_true',
    ]);

    // Phân tích URL
    register_rest_route('rm-analyzer/v1', '/analyze', [
        'methods'  => ['POST', 'OPTIONS'],
        'callback' => function (\WP_REST_Request $req) {

            // Preflight
            if ($req->get_method() === 'OPTIONS') {
                return new \WP_REST_Response(null, 204);
            }

            // Auth
            if (!rm_api_auth_ok($req)) {
                return rm_api_error(401, 'Unauthorized');
            }

            // URL vào
            $url = trim((string) $req->get_param('url'));
            if ($url === '') {
                $body = json_decode($req->get_body(), true);
                if (is_array($body) && !empty($body['url'])) $url = (string) $body['url'];
            }
            $url = rm_api_normalize_url($url);
            if (!$url) return rm_api_error(400, 'Invalid or missing URL.');

            // Bật debug khi có ?debug=1 hoặc header x-debug: 1
            $debug = (int)$req->get_param('debug') === 1 || $req->get_header('x-debug') === '1';
            $diag  = [];

            // Ưu tiên dùng class Rank Math nếu có
            $used_fallback = false;
            $data = null;

            try {
                if (class_exists('\RankMath\SEO_Analysis\SEO_Analyzer')) {
                    $analyzer = new \RankMath\SEO_Analysis\SEO_Analyzer();
                    $analyzer->analyse_url     = $url;
                    $analyzer->analyse_subpage = true;

                    $ok = $analyzer->run_api_tests();
                    if ($ok) {
                        $data = $analyzer->get_results(); // results, metrices, date, serpData
                    } else {
                        $diag['rankmath_run_api_tests'] = 'false';
                    }
                } else {
                    $diag['rankmath_class'] = 'not_found';
                }
            } catch (\Throwable $e) {
                $diag['rankmath_exception'] = $e->getMessage();
            }

            // Fallback: gọi trực tiếp endpoint RankMath nếu chưa có $data
            if (!$data) {
                $used_fallback = true;
                $fb = rm_api_rankmath_fetch($url);
                if (is_wp_error($fb)) {
                    $diag['fallback_error'] = $fb->get_error_message();
                    // Thêm báo cáo kết nối để biết vì sao 502
                    if ($debug) $diag['connectivity'] = rm_api_connectivity_report();
                    return rm_api_error(502, 'Rank Math analyze API error.' . ($debug ? ' (see diagnostics)' : ''), $diag);
                }
                $data = $fb;
            }

            $resp = [
                'success' => true,
                'url'     => $url,
                'data'    => $data,
                'source'  => $used_fallback ? 'rankmath-fallback' : 'rankmath',
            ];
            if ($debug) $resp['diagnostics'] = array_merge(['fallback' => $used_fallback], $diag);

            return new \WP_REST_Response($resp, 200);

        },
        'permission_callback' => '__return_true',
    ]);
});

/** =============== Helpers =============== */
function rm_api_error(int $status, string $message, array $extra = []) {
    $err = new \WP_Error('rm_analyzer_api_error', $message, ['status' => $status]);
    if (!empty($extra)) $err->add_data(['diagnostics' => $extra], 'rm_analyzer_api_error');
    return $err;
}

function rm_api_auth_ok(\WP_REST_Request $req): bool {
    $hdr = $req->get_header('x-app-token');
    if (!$hdr) return false;
    if (defined('RM_ANALYZER_FIXED_TOKEN') && RM_ANALYZER_FIXED_TOKEN !== '') {
        return hash_equals((string) RM_ANALYZER_FIXED_TOKEN, (string) $hdr);
    }
    $opt = get_option(RM_API_OPTION_TOKEN, '');
    return ($opt && hash_equals((string) $opt, (string) $hdr));
}

/** Chuẩn hóa URL */
function rm_api_normalize_url(string $url) {
    $url = trim($url);
    if ($url === '') return false;
    if (!preg_match('~^https?://~i', $url)) $url = 'https://' . ltrim($url, '/');
    $url = esc_url_raw($url);
    $p = wp_parse_url($url);
    if (empty($p['host'])) return false;
    return $url;
}

/** Tự gọi API RankMath (fallback) */
function rm_api_rankmath_fetch(string $url) {
    $endpoint = add_query_arg([
        'u'          => $url,
        'locale'     => get_locale(),
        'is_subpage' => 1,
    ], 'https://rankmath.com/analyze/v2/json/');

    $args = [
        'timeout'   => 30,
        'sslverify' => true,
        'headers'   => [
            'User-Agent' => 'WordPress/' . (function_exists('get_bloginfo') ? get_bloginfo('version') : '6') .
                            '; RM-Analyzer-API; ' . (function_exists('home_url') ? home_url() : ''),
            'Accept'     => 'application/json',
        ],
    ];

    $res = wp_remote_get($endpoint, $args);
    if (is_wp_error($res)) return $res;

    $code = wp_remote_retrieve_response_code($res);
    $body = wp_remote_retrieve_body($res);
    if ($code !== 200) {
        return new \WP_Error('rankmath_http_error', 'HTTP ' . $code . ' from RankMath', ['code' => $code, 'body' => $body]);
    }

    $json = json_decode($body, true);
    if (!is_array($json)) {
        return new \WP_Error('rankmath_bad_json', 'Invalid JSON from RankMath', ['body' => $body]);
    }
    return $json;
}

/** Báo cáo kết nối / cấu hình để chẩn đoán 502 */
function rm_api_connectivity_report(): array {
    $report = [
        'php' => [
            'version'         => PHP_VERSION,
            'curl_loaded'     => extension_loaded('curl'),
            'openssl_loaded'  => extension_loaded('openssl'),
            'allow_url_fopen' => (bool) ini_get('allow_url_fopen'),
        ],
        'wp'  => [
            'version'                 => (function_exists('get_bloginfo') ? get_bloginfo('version') : null),
            'WP_HTTP_BLOCK_EXTERNAL'  => defined('WP_HTTP_BLOCK_EXTERNAL') ? (WP_HTTP_BLOCK_EXTERNAL ? 'true' : 'false') : 'not_defined',
            'WP_ACCESSIBLE_HOSTS'     => defined('WP_ACCESSIBLE_HOSTS') ? WP_ACCESSIBLE_HOSTS : 'not_defined',
            'site_home'               => function_exists('home_url') ? home_url() : null,
            'locale'                  => function_exists('get_locale') ? get_locale() : null,
        ],
        'tests' => []
    ];

    // Test Google 204 (kết nối ra internet)
    $g = wp_remote_get('https://www.google.com/generate_204', ['timeout' => 10]);
    $report['tests']['google_generate_204'] = is_wp_error($g) ? $g->get_error_message() : ('HTTP ' . wp_remote_retrieve_response_code($g));

    // Test RankMath JSON endpoint
    $t = wp_remote_get('https://rankmath.com/analyze/v2/json/?u=https://example.com&is_subpage=1', ['timeout' => 15]);
    if (is_wp_error($t)) {
        $report['tests']['rankmath_json'] = $t->get_error_message();
    } else {
        $report['tests']['rankmath_json'] = 'HTTP ' . wp_remote_retrieve_response_code($t);
    }

    return $report;
}

/** =============== Trang cài đặt token =============== */
add_action('admin_menu', function () {
    add_options_page(
        'SEO Analyzer API',
        'SEO Analyzer API',
        'manage_options',
        'rm-analyzer-api',
        function () {
            if (isset($_POST['rm_token']) && check_admin_referer('rm_analyzer_api_save')) {
                update_option(RM_API_OPTION_TOKEN, sanitize_text_field(wp_unslash($_POST['rm_token'])));
                echo '<div class="updated"><p>Saved.</p></div>';
            }
            $val = esc_attr(get_option(RM_API_OPTION_TOKEN, ''));
            echo '<div class="wrap"><h1>SEO Analyzer API</h1><form method="post">';
            wp_nonce_field('rm_analyzer_api_save');
            echo '<p><label>App Token (x-app-token):</label></p>';
            echo '<p><input type="text" name="rm_token" value="' . $val . '" class="regular-text" style="width:42rem" placeholder="your-secret-token"></p>';
            submit_button('Save');
            if (defined('RM_ANALYZER_FIXED_TOKEN')) {
                echo '<p><em>Note: A hard-coded token via <code>RM_ANALYZER_FIXED_TOKEN</code> overrides this value.</em></p>';
            }
            echo '<p>Analyze endpoint: <code>' . esc_html( rest_url('rm-analyzer/v1/analyze') ) . '</code><br>';
            echo 'Debug endpoint: <code>' . esc_html( rest_url('rm-analyzer/v1/debug') ) . '</code></p>';
            echo '</form></div>';
        }
    );
});
