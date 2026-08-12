<?php
require_once('../../../wp-load.php');

$cdn_url = get_option('clbntb_cdn_url');
$api_key = get_option('clbntb_cdn_api_key', '');
$domain = clbntb_get_cdn_domain();
$cdn_api_url = rtrim($cdn_url, '/') . '/upload';
$target_base = rtrim($cdn_url, '/') . '/' . trim($domain, '/');

$path = ABSPATH . 'wp-content/uploads/2026/06/BIA-12-324x400.png';
$webp_path = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $path);

$source_url = "https://tanngoctax.vn/wp-content/uploads/2026/06/BIA-12-324x400.png";
$target_url = "https://cdn1.type.vn/tanngoctax.vn/media/2026/06/BIA-12-324x400.png";
$webp_source_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $source_url);
$webp_target_url = preg_replace('/\.(jpg|jpeg|png)$/i', '.webp', $target_url);

if (!file_exists($webp_path)) {
    $img = @imagecreatefrompng($path);
    if ($img) {
        imagepalettetotruecolor($img);
        imagealphablending($img, true);
        imagesavealpha($img, true);
        imagewebp($img, $webp_path, 80);
        imagedestroy($img);
    }
}

echo "Pushing origin PNG to CDN API...\n";
$res_orig = wp_remote_post($cdn_api_url, array(
    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
    'body'    => json_encode(array('path' => $source_url, 'target' => $target_url, 'file_base64' => base64_encode(file_get_contents($path)))),
    'timeout' => 45, 'sslverify' => false
));
echo "API Response (PNG): " . wp_remote_retrieve_body($res_orig) . "\n";

echo "Pushing WebP to CDN API...\n";
$res_webp = wp_remote_post($cdn_api_url, array(
    'headers' => array('Content-Type' => 'application/json', 'X-API-Key' => $api_key),
    'body'    => json_encode(array('path' => $webp_source_url, 'target' => $webp_target_url, 'file_base64' => base64_encode(file_get_contents($webp_path)))),
    'timeout' => 45, 'sslverify' => false
));
echo "API Response (WebP): " . wp_remote_retrieve_body($res_webp) . "\n";

@unlink($webp_path);
@unlink(__FILE__);
