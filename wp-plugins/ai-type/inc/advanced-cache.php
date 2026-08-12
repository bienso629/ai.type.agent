<?php
/**
 * AI Type Ultra-Fast FPC Engine (Drop-in Cache Loader)
 * Serves from Redis (< 1ms) or Static HTML/GZIP Cache (< 5ms) before WordPress Core or MySQL loads.
 */
if (!defined('ABSPATH')) exit;

if ($_SERVER['REQUEST_METHOD'] !== 'GET') return;

$uri = $_SERVER['REQUEST_URI'] ?? '';
if (
    strpos($uri, '/wp-admin/') !== false || 
    strpos($uri, '/wp-json/') !== false || 
    strpos($uri, '/wp-login.php') !== false ||
    isset($_GET['uxb_iframe']) || 
    isset($_GET['elementor-preview']) || 
    isset($_GET['fl_builder']) || 
    isset($_GET['et_fb']) ||
    isset($_GET['vcv-action']) ||
    isset($_GET['cornerstone'])
) {
    return;
}

$user_cookie = '';
foreach ($_COOKIE as $key => $val) {
    if (strpos($key, 'wp_woocommerce_session_') === 0 || strpos($key, 'comment_author_') === 0) {
        return;
    }
    if (strpos($key, 'wordpress_logged_in_') === 0) {
        $parts = explode('|', $val);
        if (isset($parts[0])) {
            $user_cookie = $parts[0];
        }
    }
}

$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$hosts_to_try = array($host, preg_replace('/:\d+$/', '', $host), 'plugins.type.vn');
$max_age = !empty($user_cookie) ? 43200 : 86400;
$accepts_gzip = isset($_SERVER['HTTP_ACCEPT_ENCODING']) && strpos($_SERVER['HTTP_ACCEPT_ENCODING'], 'gzip') !== false;

// === ƯU TIÊN 1: Redis Cache (< 1ms) ===
if (class_exists('Redis')) {
    try {
        $redis_host = defined('AITYPE_REDIS_HOST') ? AITYPE_REDIS_HOST : '127.0.0.1';
        $redis_port = defined('AITYPE_REDIS_PORT') ? AITYPE_REDIS_PORT : 6379;
        $redis_pass = defined('AITYPE_REDIS_PASSWORD') ? AITYPE_REDIS_PASSWORD : '';
        $redis_db = defined('AITYPE_REDIS_DB') ? (int)AITYPE_REDIS_DB : 0;
        $redis_prefix = defined('AITYPE_REDIS_PREFIX') ? AITYPE_REDIS_PREFIX : 'ait_fpc:';

        $r = new Redis();
        if ($r->connect($redis_host, $redis_port, 0.5)) { // 500ms timeout
            if (!empty($redis_pass)) $r->auth($redis_pass);
            if ($redis_db > 0) $r->select($redis_db);

            foreach ($hosts_to_try as $h) {
                $base_key = md5($h . $uri);
                $cache_key = !empty($user_cookie) ? $base_key . '_' . md5('user:' . $user_cookie) : $base_key;

                if ($accepts_gzip) {
                    $cached = $r->get($redis_prefix . $cache_key . ':gz');
                    if ($cached !== false) {
                        header('Content-Type: text/html; charset=UTF-8');
                        header('Content-Encoding: gzip');
                        header('X-AI-Type-FPC: HIT-REDIS-GZIP-ADVANCED (<1ms)');
                        header('Cache-Control: public, max-age=31536000, immutable');
                        echo $cached;
                        exit;
                    }
                }

                $cached = $r->get($redis_prefix . $cache_key);
                if ($cached !== false) {
                    header('Content-Type: text/html; charset=UTF-8');
                    header('X-AI-Type-FPC: HIT-REDIS-ADVANCED (<1ms)');
                    header('Cache-Control: public, max-age=31536000, immutable');
                    echo $cached;
                    exit;
                }
            }
            
            $r->close();
        }
    } catch (Exception $e) {
        // Redis unavailable, fallback to file
    }
}

// === ƯU TIÊN 2: File Cache (< 5ms) ===
$cache_dir = WP_CONTENT_DIR . '/uploads/ai-type-cache/html';

foreach ($hosts_to_try as $h) {
    $base_key = md5($h . $uri);
    $cache_key = !empty($user_cookie) ? $base_key . '_' . md5('user:' . $user_cookie) : $base_key;
    
    $cache_file = $cache_dir . '/' . $cache_key . '.html';
    $gz_file = $cache_file . '.gz';

    if ($accepts_gzip && file_exists($gz_file)) {
        if (time() - filemtime($gz_file) < $max_age) {
            header('Content-Type: text/html; charset=UTF-8');
            header('Content-Encoding: gzip');
            header('X-AI-Type-FPC: HIT-GZIP-ADVANCED (<5ms)');
            header('Cache-Control: public, max-age=31536000, immutable');
            header('Expires: ' . gmdate('D, d M Y H:i:s', time() + 31536000) . ' GMT');
            readfile($gz_file);
            exit;
        }
    } elseif (file_exists($cache_file)) {
        if (time() - filemtime($cache_file) < $max_age) {
            header('Content-Type: text/html; charset=UTF-8');
            header('X-AI-Type-FPC: HIT-ADVANCED (<5ms)');
            header('Cache-Control: public, max-age=31536000, immutable');
            header('Expires: ' . gmdate('D, d M Y H:i:s', time() + 31536000) . ' GMT');
            readfile($cache_file);
            exit;
        }
    }
}
