<?php
require_once('../../../wp-load.php');

$cdn_url = get_option('clbntb_cdn_url');
$api_key = get_option('clbntb_cdn_api_key', '');
$domain = clbntb_get_cdn_domain();
$cdn_api_url = rtrim($cdn_url, '/') . '/upload';
$target_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');

$path = ABSPATH . 'wp-content/uploads/2026/06/BIA-12-324x400.png';
$webp_path = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $path);
$base_dir = wp_upload_dir()['basedir'];
$base_url = wp_upload_dir()['baseurl'];

$source_url = str_replace($base_dir, $base_url, $path);
$url_path = parse_url($source_url, PHP_URL_PATH);
$url_path = str_replace(
    array('/wp-content/themes/', '/wp-content/plugins/', '/wp-content/uploads/', '/wp-includes/'),
    array('/themes/', '/plugins/', '/media/', '/includes/'),
    $url_path
);
$target_url = $target_base . $url_path;
$webp_target_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $target_url);

echo "Pushing $webp_path to CDN...\n";

// Generate WebP if not exists
if (!file_exists($webp_path)) {
    $img = @imagecreatefrompng($path);
    if ($img) {
        imagepalettetotruecolor($img);
        imagealphablending($img, true);
        imagesavealpha($img, true);
        imagewebp($img, $webp_path, 80);
        imagedestroy($img);
        echo "Local WebP generated.\n";
    }
}

$res_webp = wp_remote_post($cdn_api_url, array(
    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
    'body'    => json_encode(array('path' => preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $source_url), 'target' => $webp_target_url, 'file_base64' => base64_encode(file_get_contents($webp_path)))),
    'timeout' => 45, 'sslverify' => false
));

if (is_wp_error($res_webp)) {
    echo "Error: " . $res_webp->get_error_message();
} else {
    echo "Response Code: " . wp_remote_retrieve_response_code($res_webp) . "\n";
    echo "Response Body: " . wp_remote_retrieve_body($res_webp) . "\n";
}
unlink($webp_path);
unlink(__FILE__);
