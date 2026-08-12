<?php 

/*
Module: AI Type SEO (Integrated into AI Type)
*/

/*
Copyright (C) 2022 Cole Design Studios, LLC

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

define('SSEO_TXTDOMAIN', 'ai-type-seo');
define('SSEO_VERSION', '2.0.38');
define('SSEO_PATH', plugin_dir_path(__FILE__));

require_once(dirname( __FILE__ ).'/autoloader.php');

global $SimpleSEO;
$SimpleSEO = new app\SimpleSEO();

add_filter('pre_update_option_sseo_htaccess', function($value, $old_value, $option) {
    if (!function_exists('get_home_path')) require_once(ABSPATH . 'wp-admin/includes/file.php');
    $htaccess_file = get_home_path() . '.htaccess';
    file_put_contents($htaccess_file, $value);
    return $value;
}, 10, 3);

add_filter('pre_update_option_sseo_robots_txt', function($value, $old_value, $option) {
    if (!function_exists('get_home_path')) require_once(ABSPATH . 'wp-admin/includes/file.php');
    $robots_file = get_home_path() . 'robots.txt';
    file_put_contents($robots_file, $value);
    return $value;
}, 10, 3);

global $ai_type_is_singular;
add_action('template_redirect', function() {
    global $wp_the_query, $ai_type_is_singular;
    $ai_type_is_singular = $wp_the_query->is_singular(['post', 'page']);
});

add_filter('ai_type_html_output', function($html) {
	if (get_option('sseo_toc_enable') != '1') return $html . "";
	global $ai_type_is_singular;
	if (!$ai_type_is_singular) return $html . "";
		$headings_to_match = [];
		if (get_option('sseo_toc_exclude_h1') != '1') $headings_to_match[] = '1';
		if (get_option('sseo_toc_exclude_h2') != '1') $headings_to_match[] = '2';
		if (get_option('sseo_toc_exclude_h3') != '1') $headings_to_match[] = '3';
		if (get_option('sseo_toc_exclude_h4') != '1') $headings_to_match[] = '4';
		if (get_option('sseo_toc_exclude_h5') != '1') $headings_to_match[] = '5';
		if (get_option('sseo_toc_exclude_h6') != '1') $headings_to_match[] = '6';
		
		if (empty($headings_to_match)) return $html . "";
		$h_pattern = implode('', $headings_to_match);
		
		$html .= '<!-- sseo-toc-debug-callback-called -->';
		if (preg_match('/(<(div|article|section)[^>]*class="[^"]*\b(td-post-content|entry-content|post-content)\b[^"]*"[^>]*>)/is', $html, $container_match)) {
			$container = $container_match[1];
			$tag_name = $container_match[2];
			$parts = explode($container, $html, 2);
			if (count($parts) == 2) {
				$pre_content = $parts[0] . $container;
				$content_and_after = $parts[1];
				
				preg_match_all('/<\/?' . $tag_name . '\b/i', $content_and_after, $tag_matches, PREG_OFFSET_CAPTURE);
				$open_tags = 1;
				$pos = strlen($content_and_after);
				foreach ($tag_matches[0] as $match) {
					if (strtolower(substr($match[0], 0, 2)) === '</') {
						$open_tags--;
					} else {
						$open_tags++;
					}
					if ($open_tags == 0) {
						$pos = $match[1];
						break;
					}
				}
				$content = substr($content_and_after, 0, $pos);
				$after_content = substr($content_and_after, $pos);
				
				if (!preg_match_all('/<h(['.$h_pattern.'])([^>]*)>(.*?)<\/h\1>/is', $content, $matches)) {
					return $html . "";
				}
				
				$toc_title = get_option('sseo_toc_title');
				if (empty($toc_title)) $toc_title = 'Tóm tắt nội dung';
				
				$list_tag = (get_option('sseo_toc_list_style') == 'ol') ? 'ol' : 'ul';
				
				$toc_html = '<div class="sseo-toc" style="background:#f9f9f9; padding:20px; border:1px solid #eee; margin-bottom:25px;">';
				$toc_html .= '<p style="font-weight:bold; margin-top:0; margin-bottom:15px; font-size:18px; color:#333;">' . esc_html($toc_title) . '</p>';
				$toc_html .= '<' . $list_tag . ' style="margin-bottom:0; padding-left:20px; line-height: 1.6;">';
				
				$used_anchors = [];
				
				foreach ($matches[0] as $i => $full_heading) {
					$level = $matches[1][$i];
					$attributes = $matches[2][$i];
					$text = strip_tags($matches[3][$i]);
					
					if (preg_match('/id=["\']([^"\']+)["\']/i', $attributes, $id_match)) {
						$anchor = $id_match[1];
					} else {
						$anchor = sanitize_title($text);
						if (empty($anchor)) $anchor = 'heading-' . $i;
						if (in_array($anchor, $used_anchors)) {
							$anchor .= '-' . $i;
						}
						
						$style_addition = 'scroll-margin-top: 80px;';
						if (preg_match('/style=["\'](.*?)["\']/i', $attributes, $style_match)) {
							$new_style = $style_match[1] . ' ' . $style_addition;
							$new_attributes = preg_replace('/style=["\'](.*?)["\']/i', 'style="' . esc_attr($new_style) . '"', $attributes);
							$new_heading = '<h' . $level . $new_attributes . ' id="' . esc_attr($anchor) . '">' . $matches[3][$i] . '</h' . $level . '>';
						} else {
							$new_heading = '<h' . $level . $attributes . ' id="' . esc_attr($anchor) . '" style="' . $style_addition . '">' . $matches[3][$i] . '</h' . $level . '>';
						}
						
						$content = str_replace($full_heading, $new_heading, $content);
					}
					$used_anchors[] = $anchor;
					
					$margin = ((int)$level - 1) * 15;
					$toc_html .= '<li style="margin-left:' . $margin . 'px; margin-bottom:8px;"><a href="#' . esc_attr($anchor) . '" style="text-decoration:none; color:#0073aa; font-weight: 500;">' . esc_html($text) . '</a></li>';
				}
				$toc_html .= '</' . $list_tag . '></div>';
				
				$first_heading_pos = strpos($content, $matches[0][0]);
				if ($first_heading_pos !== false) {
					$content = substr_replace($content, $toc_html, $first_heading_pos, 0);
				} else {
					$content = $toc_html . $content;
				}
				
				return $pre_content . $content . $after_content;
			}
		}
		
		return $html . "<!-- AI Type sseo-debug: aborted early -->";
});

?>