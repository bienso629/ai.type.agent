<?php 

namespace app\Admin\Meta;

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

use app\Helpers as Helper;

/**
 * Header class. This is the meat and potatoes.
 * All meta data is gathered and printed within
 * the header.
 *
 * @since  2.0.0
 */
class Header {

    public function __construct() {
		global $post;
		global $wp_query;

		/* double line break, we want some space to see our content within the header. */
		echo "\n\n".'<!-- This site is optimized with the AI Type SEO plugin v'.SSEO_VERSION.' - https://wordpress.org/plugins/ai-type-seo/ -->' . "\n";

		$keywords = null;
		$description = null;

		/**
		 *
		 * Remember always escape late, escape when you use a variable.
		 *
		 * esc_attr() within a attribute; src="esc_attr($value)"
		 * esc_html() within for a variable; <p>esc_html($value)</p>
		 * esc_url() within a href attribute; href="esc_url($value)"
		 * esc_textarea() within a textarea; <textarea>esc_textarea($value)</textarea>
		 *
		 */
		 
		/*$allmeta = get_post_meta($post->ID);
		echo '<pre>';
		Print_r($allmeta);
		echo '</pre>';*/

		$sseo_canonical_url = null;
		if (is_front_page() && is_home()) { /* Default Homepage */
			$description = get_option('sseo_default_meta_description');
			$keywords = get_option('sseo_default_meta_keywords');
			$sseo_canonical_url = get_home_url();
		} elseif (is_home()) { /* Blog Page */
			$description = get_post_meta(get_option('page_for_posts'), 'sseo_meta_description', true);
			$keywords = get_post_meta(get_option('page_for_posts'), 'sseo_meta_keywords', true);
			$sseo_canonical_url = get_permalink(get_option('page_for_posts'));
		} elseif ((is_front_page() || is_home()) && isset($post->ID)) { /* Static */
			$keywords = get_post_meta($post->ID, 'sseo_meta_keywords', true);
			$description = get_post_meta($post->ID, 'sseo_meta_description', true);
		} elseif (isset($post->ID)) {
			$keywords = get_post_meta($post->ID, 'sseo_meta_keywords', true);
			$description = get_post_meta($post->ID, 'sseo_meta_description', true);
		}

		if (empty($keywords)) {
			$keywords = get_option('sseo_default_meta_keywords');
		}

		if ($keywords) {
			echo '<meta name="keywords" content="'.esc_attr($keywords).'" />' . "\n";
		}

		if (empty($sseo_canonical_url) && isset($post->ID)) {
			$possible_canonical_url = get_post_meta($post->ID, 'sseo_canonical_url', true);
			if (!empty($possible_canonical_url)) {
				$sseo_canonical_url = get_post_meta($post->ID, 'sseo_canonical_url', true);
			} else {
				$sseo_canonical_url = wp_get_canonical_url($post->ID);
			}
		}

		if (in_array('woocommerce/woocommerce.php', apply_filters('active_plugins', get_option('active_plugins')))) {
			if (is_shop()) {
				$shop_page_id = get_option('woocommerce_shop_page_id');
				$description = get_post_meta($shop_page_id, 'sseo_meta_description', true);
				$description = apply_filters('sseo_meta_description', $description);

				$sseo_canonical_url = get_post_meta($shop_page_id, 'sseo_canonical_url', true);
				$sseo_canonical_url = apply_filters('sseo_canonical_url', $sseo_canonical_url);
			} elseif (is_product_category() || is_product_tag()) {
				$term = $wp_query->get_queried_object();
				if (!empty($term->term_id)) {
					$term_meta = get_option("taxonomy_".$term->term_id);

					if (!empty($term_meta['sseo_description']))
					$description = $term_meta['sseo_description'];

					if (!empty($term_meta['sseo_canonical_url']))
					$sseo_canonical_url = $term_meta['sseo_canonical_url'];
				}
			}
		}

		if (is_category() || is_tag()) {
			$term = $wp_query->get_queried_object();
			if (!empty($term->term_id)) {
				$term_meta = get_option("taxonomy_".$term->term_id);

				if (!empty($term_meta['sseo_description']))
				$description = $term_meta['sseo_description'];

				if (!empty($term_meta['sseo_canonical_url']))
				$sseo_canonical_url = $term_meta['sseo_canonical_url'];
			}
		}

		if (empty($description)) {
			$description = get_option('sseo_default_meta_description');
		}

		if ($description) {
			echo '<meta name="description" content="'.esc_attr($description).'" />' . "\n";
		}

		if (isset($post->ID)) {
			$sseo_robot_noindex = get_post_meta($post->ID, 'sseo_robot_noindex', true);
			$sseo_robot_nofollow = get_post_meta($post->ID, 'sseo_robot_nofollow', true);
		
			if (!empty($sseo_robot_noindex) && !empty($sseo_robot_nofollow)) {
				echo '<meta name="robots" content="noindex, nofollow" />' . "\n";
			} elseif (empty($sseo_robot_noindex) && !empty($sseo_robot_nofollow)) {
				echo '<meta name="robots" content="nofollow" />' . "\n";
			}
			if (!empty($sseo_robot_noindex) && empty($sseo_robot_nofollow)) {
				echo '<meta name="robots" content="noindex" />' . "\n";
			}

			$sseo_fb_title = get_post_meta($post->ID, 'sseo_fb_title', true);
			$sseo_fb_description = get_post_meta($post->ID, 'sseo_fb_description', true);
			$sseo_fb_image_id = get_post_meta($post->ID, 'sseo_fb_image', true);
		}
		
		if (!empty($description) && empty($sseo_fb_description)) {
			$sseo_fb_description = $description;
		}

		$current_url = null;
		$sseo_fb_app_id = get_option('sseo_fb_app_id');
		$sseo_thumbnail_url = $this->get_thumbnail_url($post);

		if (in_array('woocommerce/woocommerce.php', apply_filters('active_plugins', get_option('active_plugins')))) {
			if (is_shop()) {
				$shop_page_id = get_option('woocommerce_shop_page_id');
				$sseo_fb_title = get_post_meta($shop_page_id, 'sseo_fb_title', true);
				$sseo_fb_description = get_post_meta($shop_page_id, 'sseo_fb_description', true);
				$current_url = get_permalink($shop_page_id);
			}
		}

		if (empty($current_url) && (is_front_page() && is_home())) {
			$current_url = home_url('/');
		} elseif (empty($current_url) && (is_category() || is_tag() || is_tax())) {
			$obj_id = get_queried_object_id();
			$current_url = get_term_link($obj_id);
		} elseif (empty($current_url) && isset($post->ID)) {
			$current_url = get_permalink($post->ID);
		}

		if (empty($sseo_fb_title)) {
			$sseo_fb_title = Title::getTitle();
		}

		// Google Snippet Thumbnail Meta Tags
		if (!empty($sseo_thumbnail_url)) {
			echo '<meta name="thumbnail" content="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
			echo '<meta name="image" content="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
			echo '<link rel="image_src" href="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
		}

		if ($sseo_fb_app_id) { echo '<meta property="fb:app_id" content="'.esc_attr($sseo_fb_app_id).'" />' . "\n"; }
		echo '<meta property="og:locale" content="'.esc_attr(get_locale()).'" />'."\n";
		echo '<meta property="og:site_name" content="'.esc_attr(get_bloginfo('name')).'" />'."\n";
		if ($current_url) { echo '<meta property="og:url" content="'.esc_url($current_url).'" />' . "\n"; }
		if ($current_url) { echo '<meta property="og:type" content="website" />'."\n"; }
		if ($sseo_fb_title) { echo '<meta property="og:title" content="'.esc_attr($sseo_fb_title).'" />' . "\n"; }
		if (!empty($sseo_fb_description)) { echo '<meta property="og:description" content="'.esc_attr($sseo_fb_description).'" />' . "\n"; }
		
		if (!empty($sseo_thumbnail_url)) {
			echo '<meta property="og:image" content="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
			echo '<meta property="og:image:secure_url" content="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
			echo '<meta property="og:image:width" content="1200" />' . "\n";
			echo '<meta property="og:image:height" content="630" />' . "\n";
		}
		
		if (isset($post->ID)) {
			$sseo_tw_title = get_post_meta($post->ID, 'sseo_tw_title', true);
			$sseo_tw_description = get_post_meta($post->ID, 'sseo_tw_description', true);
		}
		
		$sseo_twitter_username = get_option('sseo_twitter_username');

		if (empty($sseo_tw_title)) {
			$sseo_tw_title = Title::getTitle();
		}
		if (empty($sseo_tw_description)) {
			$sseo_tw_description = $description;
		}

		if ($sseo_twitter_username) { echo '<meta name="twitter:site" content="'.esc_attr($sseo_twitter_username).'">' . "\n"; }

		if ($sseo_tw_title) { echo '<meta name="twitter:title" content="'.esc_attr($sseo_tw_title).'" />' . "\n"; }
		if ($sseo_tw_description) { echo '<meta name="twitter:description" content="'.esc_attr($sseo_tw_description).'" />' . "\n"; }
		
		if (!empty($sseo_thumbnail_url)) {
			echo '<meta name="twitter:image" content="'.esc_url($sseo_thumbnail_url).'" />' . "\n";
			echo '<meta name="twitter:card" content="summary_large_image">' . "\n";
		}

		$sseo_gsite_verification = esc_attr(get_option('sseo_gsite_verification'));
		if ($sseo_gsite_verification) {
			echo '<meta name="google-site-verification" content="'.esc_attr($sseo_gsite_verification).'" />' . "\n";
		}

		$sseo_baidu = esc_attr(get_option('sseo_baidu'));
		if ($sseo_baidu) {
			echo '<meta name="baidu-site-verification" content="'.esc_attr($sseo_baidu).'" />' . "\n";
		}

		$sseo_bing = esc_attr(get_option('sseo_bing'));
		if ($sseo_bing) {
			echo '<meta name="msvalidate.01" content="'.esc_attr($sseo_bing).'" />' . "\n";
		}

		$sseo_yandex = esc_attr(get_option('sseo_yandex'));
		if ($sseo_yandex) {
			echo '<meta name="yandex-verification" content="'.esc_attr($sseo_yandex).'" />' . "\n";
		}

		if (!empty($sseo_canonical_url)) {
			echo '<link rel="canonical" href="'.esc_url($sseo_canonical_url).'" />' . "\n";
		}
		
		// Article Schema
		if (get_option('sseo_schema_enable') == '1' && is_singular(['post', 'page'])) {
			global $post;
			
			$schema_title = !empty($sseo_fb_title) ? $sseo_fb_title : get_the_title($post->ID);
			$schema_desc = !empty($description) ? $description : wp_trim_words(strip_shortcodes(strip_tags($post->post_content)), 30);
			
			$schema_image = $sseo_thumbnail_url;
			
			$author_id = $post->post_author;
			$author_name = get_the_author_meta('display_name', $author_id);
			if (empty($author_name)) $author_name = 'Admin';
			
			$article_schema = array(
				'@context' => 'https://schema.org',
				'@type' => (is_page() ? 'Article' : 'BlogPosting'),
				'mainEntityOfPage' => array(
					'@type' => 'WebPage',
					'@id' => get_permalink($post->ID)
				),
				'headline' => esc_attr($schema_title),
				'description' => esc_attr($schema_desc),
				'datePublished' => get_the_date('c', $post->ID),
				'dateModified' => get_the_modified_date('c', $post->ID),
				'author' => array(
					'@type' => 'Person',
					'name' => esc_attr($author_name),
					'url' => get_author_posts_url($author_id)
				)
			);
			
			if (!empty($schema_image)) {
				$article_schema['image'] = array(esc_url($schema_image));
			}
			
			$publisher_name = get_option('sseo_local_name');
			if (empty($publisher_name)) $publisher_name = get_bloginfo('name');
			
			$publisher_logo = get_option('sseo_local_logo');
			
			$article_schema['publisher'] = array(
				'@type' => 'Organization',
				'name' => esc_attr($publisher_name)
			);
			
			if (!empty($publisher_logo)) {
				$article_schema['publisher']['logo'] = array(
					'@type' => 'ImageObject',
					'url' => esc_url($publisher_logo)
				);
			}
			
			echo '<script type="application/ld+json">' . "\n";
			echo wp_json_encode($article_schema, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n";
			echo '</script>' . "\n";
		}
		
		if (get_option('sseo_local_enable') == '1') {
			$local_type = get_option('sseo_local_type');
			if (empty($local_type)) $local_type = 'Organization';
			
			$schema = array(
				'@context' => 'https://schema.org',
				'@type' => esc_attr($local_type),
				'name' => get_option('sseo_local_name'),
				'url' => home_url('/'),
				'telephone' => get_option('sseo_local_phone')
			);
			
			$local_logo = get_option('sseo_local_logo');
			if (!empty($local_logo)) {
				$schema['logo'] = esc_url($local_logo);
				$schema['image'] = esc_url($local_logo);
			}
			
			$address = get_option('sseo_local_address');
			$city = get_option('sseo_local_city');
			
			if (!empty($address) || !empty($city)) {
				$schema['address'] = array(
					'@type' => 'PostalAddress',
					'streetAddress' => esc_attr($address),
					'addressLocality' => esc_attr($city),
					'addressCountry' => 'VN'
				);
			}
			
			echo '<script type="application/ld+json">' . "\n";
			echo wp_json_encode($schema, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n";
			echo '</script>' . "\n";
		}

		echo '<!-- / AI Type SEO plugin. -->' . "\n\n";
	}

	/**
	 * Resolves full absolute URL for a given image path/URL.
	 */
	private function resolve_image_url($url) {
		if (empty($url)) {
			return '';
		}
		$url = trim($url);
		if (strpos($url, 'http://') === 0 || strpos($url, 'https://') === 0) {
			return $url;
		}
		if (strpos($url, '//') === 0) {
			return (is_ssl() ? 'https:' : 'http:') . $url;
		}
		if (strpos($url, '/') === 0) {
			return home_url($url);
		}
		return home_url('/' . $url);
	}

	/**
	 * Gets the post/page thumbnail URL with smart fallback chain.
	 */
	private function get_thumbnail_url($post = null) {
		$image_url = '';

		// 1. Post/Page custom Facebook SEO image
		if (isset($post->ID)) {
			$fb_image_id = get_post_meta($post->ID, 'sseo_fb_image', true);
			if (!empty($fb_image_id)) {
				if (is_numeric($fb_image_id)) {
					$image_url = wp_get_attachment_image_url($fb_image_id, 'full');
				} else {
					$image_url = $fb_image_id;
				}
			}
		}

		// 2. Post/Page custom Twitter SEO image
		if (empty($image_url) && isset($post->ID)) {
			$tw_image_id = get_post_meta($post->ID, 'sseo_tw_image', true);
			if (!empty($tw_image_id)) {
				if (is_numeric($tw_image_id)) {
					$image_url = wp_get_attachment_image_url($tw_image_id, 'full');
				} else {
					$image_url = $tw_image_id;
				}
			}
		}

		// 3. Featured Image (Post Thumbnail)
		if (empty($image_url) && isset($post->ID) && has_post_thumbnail($post->ID)) {
			$thumb_id = get_post_thumbnail_id($post->ID);
			if ($thumb_id) {
				$image_url = wp_get_attachment_image_url($thumb_id, 'full');
				if (empty($image_url)) {
					$image_url = wp_get_attachment_url($thumb_id);
				}
			}
		}

		// 4. Extract first image from post content
		if (empty($image_url) && isset($post->post_content) && !empty($post->post_content)) {
			if (preg_match('/<img[^>]+src=["\']([^"\']+)["\']/i', $post->post_content, $matches)) {
				$image_url = $matches[1];
			}
		}

		// 5. Global default Facebook image setting
		if (empty($image_url)) {
			$default_fb_image = get_option('sseo_fb_image');
			if (!empty($default_fb_image)) {
				if (is_numeric($default_fb_image)) {
					$image_url = wp_get_attachment_image_url($default_fb_image, 'full');
				} else {
					$image_url = $default_fb_image;
				}
			}
		}

		// 6. Global default Twitter image setting
		if (empty($image_url)) {
			$default_tw_image = get_option('sseo_tw_image');
			if (!empty($default_tw_image)) {
				if (is_numeric($default_tw_image)) {
					$image_url = wp_get_attachment_image_url($default_tw_image, 'full');
				} else {
					$image_url = $default_tw_image;
				}
			}
		}

		// 7. Global site local logo setting
		if (empty($image_url)) {
			$local_logo = get_option('sseo_local_logo');
			if (!empty($local_logo)) {
				$image_url = $local_logo;
			}
		}

		// 8. Custom Theme Logo
		if (empty($image_url) && function_exists('get_theme_mod')) {
			$custom_logo_id = get_theme_mod('custom_logo');
			if ($custom_logo_id) {
				$image_url = wp_get_attachment_image_url($custom_logo_id, 'full');
			}
		}

		// 9. Site Icon (favicon / app icon)
		if (empty($image_url) && function_exists('get_site_icon_url')) {
			$site_icon = get_site_icon_url(512);
			if (!empty($site_icon)) {
				$image_url = $site_icon;
			}
		}

		return $this->resolve_image_url($image_url);
	}
}

?>