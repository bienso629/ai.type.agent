<?php
$html = "url('https://cdn1.type.vn/tanngoctax.vn/wp-content/uploads/2026/06/bia-16-150x150.webp');\n";
$html .= "url(https://cdn1.type.vn/tanngoctax.vn/wp-content/uploads/2026/06/bia-16-150x150.webp);\n";
$html .= "<img src=\"https://cdn1.type.vn/tanngoctax.vn/wp-content/uploads/2026/06/bia-16-150x150.webp\">\n";
$html .= "<img src=\"https://cdn1.type.vn/tanngoctax.vn/wp-content/uploads/2026/06/bia-16-150x150.webp?v=old\">\n";

$cdn_upload = "https://cdn1.type.vn/tanngoctax.vn/wp-content/uploads";
$pattern = "#" . preg_quote($cdn_upload, "#") . "([^\"]*\.)(jpg|jpeg|png|webp)(?:\?[^\"]*)?#i";

echo preg_replace($pattern, $cdn_upload . "$1webp?v=clb5", $html);
