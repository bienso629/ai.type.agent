<?php
if (!defined('ABSPATH')) exit;

class CLBNTB_CSS_JS_Pusher {
    const ASSETS_KEY = 'clbntb_cdn_assets';
    const MAP_KEY    = 'clbntb_cdn_map';

    private static $instance = null;

    public static function instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action('wp_ajax_clbntb_scan_assets', array($this, 'ajax_scan_assets'));
        add_action('wp_ajax_clbntb_upload_asset', array($this, 'ajax_upload_asset'));
        add_action('wp_ajax_clbntb_upload_all',  array($this, 'ajax_upload_all'));
        add_action('wp_ajax_clbntb_clear_map',   array($this, 'ajax_clear_map'));

        // Rewrite enqueued assets site-wide
        add_filter('style_loader_src', array($this, 'filter_src_rewrite'), 999, 2);
        add_filter('script_loader_src', array($this, 'filter_src_rewrite'), 999, 2);
    }

    /* ---------------- Core: Scan & Upload ---------------- */
    public function ajax_scan_assets() {
        if (!current_user_can('manage_options')) wp_send_json_error('no-perm');
        $url = home_url('/');
        $assets = $this->scan_assets_from_url($url);
        update_option(self::ASSETS_KEY, $assets, false);
        wp_send_json_success(array('count' => count($assets)));
    }

    public function ajax_upload_asset() {
        if (!current_user_can('manage_options')) wp_send_json_error('no-perm');
        $site_url = isset($_POST['site_url']) ? esc_url_raw($_POST['site_url']) : '';
        $cdn_url  = isset($_POST['cdn_url'])  ? esc_url_raw($_POST['cdn_url'])  : '';
        if (!$site_url || !$cdn_url) wp_send_json_error('bad-params');

        $error_msg = '';
        $ok = $this->post_to_cdn($site_url, $cdn_url, $error_msg);
        if ($ok) {
            $map = get_option(self::MAP_KEY, array());
            $map[$this->normalize_key($site_url)] = $this->strip_query($cdn_url);
            update_option(self::MAP_KEY, $map, false);
            wp_send_json_success(true);
        }
        wp_send_json_error('upload-failed: ' . $error_msg);
    }

    public function ajax_upload_all() {
        if (!current_user_can('manage_options')) wp_send_json_error('no-perm');

        $assets = get_option(self::ASSETS_KEY, array());
        $okCount = 0; $failCount = 0;

        foreach ($assets as $item) {
            $site_url = isset($item['src']) ? $item['src'] : '';
            $cdn_url  = isset($item['cdn']) ? $item['cdn'] : '';
            if (!$site_url || !$cdn_url) { $failCount++; continue; }
            $ok = $this->post_to_cdn($site_url, $cdn_url);
            if ($ok) {
                $map = get_option(self::MAP_KEY, array());
                $map[$this->normalize_key($site_url)] = $this->strip_query($cdn_url);
                update_option(self::MAP_KEY, $map, false);
                $okCount++;
            } else {
                $failCount++;
            }
        }
        wp_send_json_success(array('ok' => $okCount, 'fail' => $failCount));
    }

    public function ajax_clear_map() {
        if (!current_user_can('manage_options')) wp_send_json_error('no-perm');
        delete_option(self::MAP_KEY);
        wp_send_json_success(true);
    }

    private function post_to_cdn($source_url, $target_url, &$error_detail = '') {
        $cdn_base = rtrim(get_option('clbntb_cdn_url', ''), '/');
        $endpoint = $cdn_base . '/upload';
        $api_key = get_option('clbntb_cdn_api_key', '');
        
        $headers = array('Accept' => 'application/json');
        if (!empty($api_key)) {
            $headers['x-api-key'] = trim($api_key);
        }
        $args = array(
            'timeout' => 60,
            'headers' => array_merge($headers, array('Content-Type' => 'application/json; charset=utf-8')),
            'body'    => wp_json_encode(array(
                'path'   => $source_url,
                'target' => $target_url,
            )),
        );
        $res = wp_remote_post($endpoint, $args);
        if (is_wp_error($res)) {
            $error_detail = $res->get_error_message();
            return false;
        }
        $code = wp_remote_retrieve_response_code($res);
        $body = wp_remote_retrieve_body($res);
        if ($code < 200 || $code >= 300) {
            $error_detail = 'HTTP ' . $code . ' - ' . substr($body, 0, 100);
            return false;
        }
        $json = json_decode($body, true);
        if (is_array($json) && isset($json['ok']) && $json['ok']) return true;
        
        $error_detail = 'CDN: ' . (isset($json['error']['message']) ? $json['error']['message'] : substr($body, 0, 100));
        return false;
    }

    private function scan_assets_from_url($url) {
        $assets = array();
        
        // Dùng tham số clbntb_scan=1 để yêu cầu trả về HTML thô chưa Rewrite CDN
        $scan_url = add_query_arg('clbntb_scan', '1', $url);
        
        $resp = wp_remote_get($scan_url, array('timeout' => 30, 'redirection' => 5));
        if (is_wp_error($resp)) return $assets;
        $html = wp_remote_retrieve_body($resp);
        if (!$html) return $assets;

        $home = home_url();
        $host = $this->url_host($home);

        $css = array();
        if (preg_match_all('#<link[^>]+href=["\']([^"\']+\.css[^"\']*)["\']#i', $html, $m)) {
            $css = $m[1];
        }
        $js = array();
        if (preg_match_all('#(?:src|data-src)=["\']([^"\']+\.js[^"\']*)["\']#i', $html, $m2)) {
            $js = $m2[1];
        }
        $urls = array_unique(array_map('trim', array_merge($css, $js)));
        
        $cdn_base = rtrim(get_option('clbntb_cdn_url', ''), '/');
        if (empty($cdn_base)) return $assets;
        
        $cdn_host = $this->url_host($cdn_base);

        foreach ($urls as $u) {
            $abs = $this->absolutize($u, $url);
            
            $h = $this->url_host($abs);
            if ($h && strcasecmp($h, $host) !== 0) continue;
            
            $type = $this->guess_type($abs);
            if (!$type) continue;
            $assets[] = array(
                'src' => $abs,
                'type'=> $type,
                'cdn' => $this->build_cdn_url_fullpath($abs, $cdn_base),
            );
        }
        return array_values($assets);
    }

    private function guess_type($url) {
        $p = $this->url_path($url);
        if (!$p) return '';
        $ext = strtolower(pathinfo($p, PATHINFO_EXTENSION));
        if ($ext === 'css') return 'css';
        if ($ext === 'js') return 'js';
        return '';
    }

    private function build_cdn_url_fullpath($src, $cdn_base) {
        $site_url = rtrim(site_url(), '/');
        $domain = clbntb_get_cdn_domain();
        $cdn_full_base = rtrim($cdn_base, '/') . '/' . trim($domain, '/');
        
        // Nếu file nằm trên website gốc, ta mô phỏng y hệt thuật toán ảo hóa bên cache-reader.php
        if (stripos($src, $site_url) === 0) {
            $cdn_url = $cdn_full_base . substr($src, strlen($site_url));
            
            // Ảo hóa đường dẫn
            $cdn_url = str_replace(
                array($cdn_full_base . '/wp-content/themes/', $cdn_full_base . '/wp-content/plugins/', $cdn_full_base . '/wp-content/uploads/', $cdn_full_base . '/wp-includes/'),
                array($cdn_full_base . '/themes/', $cdn_full_base . '/plugins/', $cdn_full_base . '/media/', $cdn_full_base . '/includes/'),
                $cdn_url
            );
            return $cdn_url;
        }
        
        // Fallback an toàn cho external file
        $u = $this->parse_url_safe($src);
        $host = isset($u['host']) ? $u['host'] : $this->url_host(home_url());
        $path = isset($u['path']) ? $u['path'] : '';
        $path_clean = ltrim($path, '/');
        $q = (isset($u['query']) && $u['query']) ? '?' . $u['query'] : '';
        return rtrim($cdn_base, '/') . '/assets/' . $host . '/' . $path_clean . $q;
    }

    private function parse_url_safe($url) {
        if (function_exists('wp_parse_url')) return wp_parse_url($url);
        return parse_url($url);
    }
    private function url_host($url) {
        $u = $this->parse_url_safe($url);
        return isset($u['host']) ? $u['host'] : '';
    }
    private function url_path($url) {
        $u = $this->parse_url_safe($url);
        return isset($u['path']) ? $u['path'] : '';
    }
    private function absolutize($maybe, $base_url) {
        $maybe = trim($maybe);
        if ($maybe === '' || stripos($maybe, 'data:') === 0) return '';
        if (preg_match('#^https?://#i', $maybe)) return $maybe;
        $base = $this->parse_url_safe($base_url);
        $scheme = isset($base['scheme']) ? $base['scheme'] : 'https';
        $host   = isset($base['host']) ? $base['host'] : $this->url_host(home_url());
        $port   = isset($base['port']) ? ':' . $base['port'] : '';
        $bp     = isset($base['path']) ? $base['path'] : '/';
        if (strpos($maybe, '//') === 0) return $scheme . ':' . $maybe;
        if (strpos($maybe, '/') === 0) {
            return $scheme . '://' . $host . $port . $maybe;
        }
        $dir = preg_replace('#/[^/]*$#', '/', $bp);
        return $scheme . '://' . $host . $port . $this->resolve_path($dir . $maybe);
    }
    private function resolve_path($path) {
        $parts = array();
        foreach (explode('/', $path) as $p) {
            if ($p === '' || $p === '.') continue;
            if ($p === '..') { if (!empty($parts)) array_pop($parts); continue; }
            $parts[] = $p;
        }
        return '/' . implode('/', $parts);
    }
    private function normalize_key($url) {
        $u = $this->parse_url_safe($url);
        $host = isset($u['host']) ? strtolower($u['host']) : '';
        $path = isset($u['path']) ? $u['path'] : '';
        return $host . $path;
    }
    private function strip_query($url) {
        $u = $this->parse_url_safe($url);
        $scheme = isset($u['scheme']) ? $u['scheme'] : 'https';
        $host = isset($u['host']) ? $u['host'] : '';
        $port = isset($u['port']) ? ':' . $u['port'] : '';
        $path = isset($u['path']) ? $u['path'] : '';
        return $scheme . '://' . $host . $port . $path;
    }

    public function filter_src_rewrite($src, $handle = null) {
        if (is_admin() || isset($_GET['clbntb_scan']) || isset($_GET['uxb_iframe']) || isset($_GET['elementor-preview']) || isset($_GET['fl_builder']) || isset($_GET['et_fb']) || isset($_GET['vcv-action']) || isset($_GET['cornerstone'])) return $src;
        $map = get_option(self::MAP_KEY, array());
        if (empty($map)) return $src;
        $key = $this->normalize_key($src);
        if (isset($map[$key])) {
            $u = $this->parse_url_safe($src);
            $q = (isset($u['query']) && $u['query']) ? '?' . $u['query'] : '';
            return $map[$key] . $q;
        }
        return $src;
    }
}

CLBNTB_CSS_JS_Pusher::instance();
