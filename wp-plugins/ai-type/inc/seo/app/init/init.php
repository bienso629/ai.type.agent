<?php 

namespace app\init;

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

use app\Admin\Meta as Meta;

/**
 * Initialization class for, everything.
 *
 * @since 2.0.0
 */
class init {
    /**
     * Plugin version for enqueueing, etc.
     * The value is retrieved from the CDS_SSEO_VERSION constant.
     *
     * @since 2.0.0
     *
     * @var string
     */
	public $version = '';
	
	public function __construct() {
		$this->version = SSEO_VERSION;
		$this->settings();
		new Enqueue();

		/* headings, content, column sorting */
		$post_types = get_post_types(['public' => true]);
		if (is_array($post_types)) {
			foreach($post_types as $post_type) {
				add_filter('manage_'.$post_type.'_posts_columns', [$this, 'columnHeading'], 10, 1);
				add_action('manage_'.$post_type.'_posts_custom_column', [$this, 'columnContent'], 10, 2);
				add_action('manage_edit-'.$post_type.'_sortable_columns', [$this, 'columnSort'], 10, 2);
			}
			unset($post_type);
		}
		
		/* Default metabox for posts/pages */
		add_action('add_meta_boxes', [$this, 'metaBoxes']);
		
		/* Taxonomies */
		add_action('category_add_form_fields', [$this, 'renderNewTaxonomyMetaBox']);
		add_action('category_edit_form_fields', [$this, 'renderEditTaxonomyMetaBox']);
		add_action('post_tag_add_form_fields', [$this, 'renderNewTaxonomyMetaBox']);
		add_action('post_tag_edit_form_fields', [$this, 'renderEditTaxonomyMetaBox']);
		
		/* Quick Edit */
		add_action('quick_edit_custom_box', [$this, 'renderQuickEditMetaBox']);

		/* WooCommerce */
		if (in_array('woocommerce/woocommerce.php', apply_filters('active_plugins', get_option('active_plugins')))) {
			add_action('product_cat_add_form_fields', [$this, 'renderNewTaxonomyMetaBox']);
			add_action('product_cat_edit_form_fields', [$this, 'renderEditTaxonomyMetaBox']);
			add_action('product_tag_add_form_fields', [$this, 'renderNewTaxonomyMetaBox']);
			add_action('product_tag_edit_form_fields', [$this, 'renderEditTaxonomyMetaBox']);
		}
		
		/* Header, Title, Meta */
		add_action('wp_head', [$this, 'renderHeader'], 0);
		$title = new Meta\Title();
		add_filter('pre_get_document_title', [$title, 'getTitle']);
		add_filter('wp_title', [$title, 'getTitle']);
		
		/* Analytics */
		add_filter('wp_head', [$this, 'renderAnalytics']);
		
		/* Sitemap */
		if (get_option('sseo_generate_sitemap') == true) {
			/* disable WordPress sitemaps in favor of SimpleSEO sitemap. */
			apply_filters('wp_sitemaps_enabled', false);
		}
	}
	
	/**
 	 * Registers all the settings.
	 *
 	 * @since  2.0.0
 	 */
	private function settings() {
		register_setting('sseo-settings-group', 'sseo_default_meta_title');
		register_setting('sseo-settings-group', 'sseo_default_meta_description');
		register_setting('sseo-settings-group', 'sseo_default_meta_keywords');
		register_setting('sseo-settings-group', 'sseo_gsite_verification');
		register_setting('sseo-settings-group', 'sseo_ganalytics');
		register_setting('sseo-settings-group', 'sseo_g4analytics');
		register_setting('sseo-settings-group', 'sseo_bing');
		register_setting('sseo-settings-group', 'sseo_yandex');
		register_setting('sseo-settings-group', 'sseo_robot_noindex');
		register_setting('sseo-settings-group', 'sseo_robot_nofollow');
		register_setting('sseo-settings-group', 'sseo_fb_app_id');
		register_setting('sseo-settings-group', 'sseo_fb_title');
		register_setting('sseo-settings-group', 'sseo_fb_description');
		register_setting('sseo-settings-group', 'sseo_fb_image');
		register_setting('sseo-settings-group', 'sseo_twitter_username');
		register_setting('sseo-settings-group', 'sseo_tw_title');
		register_setting('sseo-settings-group', 'sseo_tw_description');
		register_setting('sseo-settings-group', 'sseo_tw_image');
		register_setting('sseo-settings-group', 'sseo_canonical_url');
		register_setting('sseo-settings-group', 'sseo_generate_sitemap');
		register_setting('sseo-settings-group', 'sseo_generate_llms');
		register_setting('sseo-settings-group', 'sseo_sitemap_post_types');
		register_setting('sseo-settings-group', 'sseo_htaccess');
		register_setting('sseo-settings-group', 'sseo_robots_txt');
		register_setting('sseo-settings-group', 'sseo_schema_enable');
		register_setting('sseo-settings-group', 'sseo_local_enable');
		register_setting('sseo-settings-group', 'sseo_local_type');
		register_setting('sseo-settings-group', 'sseo_local_name');
		register_setting('sseo-settings-group', 'sseo_local_phone');
		register_setting('sseo-settings-group', 'sseo_local_address');
		register_setting('sseo-settings-group', 'sseo_local_city');
		register_setting('sseo-settings-group', 'sseo_local_logo');
		register_setting('sseo-settings-group', 'sseo_image_auto_alt');
		register_setting('sseo-settings-group', 'sseo_toc_enable');
		register_setting('sseo-settings-group', 'sseo_toc_title');
		register_setting('sseo-settings-group', 'sseo_toc_list_style');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h1');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h2');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h3');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h4');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h5');
		register_setting('sseo-settings-group', 'sseo_toc_exclude_h6');
		
		add_action('update_option_sseo_htaccess', function($old_value, $new_value) {
			require_once(ABSPATH . 'wp-admin/includes/file.php');
			$htaccess_file = get_home_path() . '.htaccess';
			if (file_exists($htaccess_file) && is_writable($htaccess_file)) {
				file_put_contents($htaccess_file, wp_unslash($new_value));
			}
		}, 10, 2);

		add_action('update_option_sseo_robots_txt', function($old_value, $new_value) {
			require_once(ABSPATH . 'wp-admin/includes/file.php');
			$robots_file = get_home_path() . 'robots.txt';
			file_put_contents($robots_file, wp_unslash($new_value));
		}, 10, 2);
		
		add_action('save_post', function($post_id, $post, $update) {
			if (get_option('sseo_generate_llms') == '1' && in_array($post->post_type, ['post', 'page']) && $post->post_status == 'publish') {
				self::generate_llms_txt();
			}
		}, 10, 3);
		
		add_action('update_option_sseo_generate_llms', function($old_value, $new_value) {
			if ($new_value == '1') {
				self::generate_llms_txt();
			} else {
				require_once(ABSPATH . 'wp-admin/includes/file.php');
				$llms_file = get_home_path() . 'llms.txt';
				if (file_exists($llms_file)) {
					@unlink($llms_file);
				}
			}
		}, 10, 2);
    }
	
	public static function generate_llms_txt() {
		require_once(ABSPATH . 'wp-admin/includes/file.php');
		$llms_file = get_home_path() . 'llms.txt';
		
		$content = "# " . esc_html(get_bloginfo('name')) . "\n";
		$content .= "> " . esc_html(get_bloginfo('description')) . "\n\n";
		
		$content .= "## Trang (Pages)\n";
		$pages = get_posts(['post_type' => 'page', 'posts_per_page' => 500, 'post_status' => 'publish']);
		foreach ($pages as $p) {
			$excerpt = $p->post_excerpt ? $p->post_excerpt : wp_trim_words(strip_shortcodes(strip_tags($p->post_content)), 25);
			$content .= "- [" . esc_html($p->post_title) . "](" . get_permalink($p->ID) . "): " . esc_html($excerpt) . "\n";
		}
		
		$content .= "\n## Bài viết (Posts)\n";
		$posts = get_posts(['post_type' => 'post', 'posts_per_page' => 500, 'post_status' => 'publish']);
		foreach ($posts as $p) {
			$excerpt = $p->post_excerpt ? $p->post_excerpt : wp_trim_words(strip_shortcodes(strip_tags($p->post_content)), 25);
			$content .= "- [" . esc_html($p->post_title) . "](" . get_permalink($p->ID) . "): " . esc_html($excerpt) . "\n";
		}
		
		file_put_contents($llms_file, $content);
	}
	
	/**
 	 * Activation.
	 *
	 * @since  2.0.0
 	 */
	public function activate() {
    }
    
	/**
 	 * Deactivate.
	 *
	 * @since  2.0.0
 	 */
	public function deactivate() {
    }

	/**
	 * Adds column heading names
	 *
	 * @since  2.0.0
	 */
	public function columnHeading($columns) {
		$columns['post_name'] = __('Đường dẫn', SSEO_TXTDOMAIN);
		$columns['seo_title'] = __('Tiêu đề SEO', SSEO_TXTDOMAIN);
		$columns['seo_description'] = __('Mô tả SEO', SSEO_TXTDOMAIN);
		return $columns;
	}

	/**
	 * Adds column heading names
	 *
	 * @since  2.0.0
	 */
	public function columnContent($column, $post_id) {
		switch ($column) {
			case 'post_name':
				$post = get_post($post_id);
				echo esc_html($post->post_name);
				break;
			case 'seo_title':
				$title = get_post_meta($post_id, 'sseo_meta_title', true);
				if (empty($title)) {
					$post = get_post($post_id);
					$title = $post->post_title;
				}
				echo esc_html($title);
				break;
			case 'seo_description':
				$desc = get_post_meta($post_id, 'sseo_meta_description', true);
				if (empty($desc)) {
					$post = get_post($post_id);
					$desc = $post->post_excerpt;
					if (empty($desc)) {
						$desc = wp_trim_words(strip_shortcodes(strip_tags($post->post_content)), 25);
					}
				}
				echo esc_html($desc);
				break;
		}
	}

	/**
	 * Adds column heading names
	 *
	 * @since  2.0.0
	 */
	public function columnSort($columns) {
		$columns['post_name'] = 'post_name';
		$columns['seo_title'] = 'seo_title';
		$columns['seo_description'] = 'seo_description';
		return $columns;
	}

	/**
	 * Creats our meta box for AI Type SEO.
	 * We can then use the app\Admin\Meta\Post
	 * in many places.
	 *
	 * @since  2.0.0
	 */
	public function metaBoxes($postType) {
		add_meta_box(
			'ai-type-seo', 
			__('AI Type SEO'), 
			[$this, 'renderMetaBox'],
			$postType
		);
	}

	/**
	 * Renders the meta box for pages, posts, etc
	 *
	 * @since  2.0.0
	 */
	public function renderMetaBox($post) {
		new Meta\Post($post);
	}

	/**
	 * Renders the meta box for a new taxonomy
	 *
	 * @since  2.0.0
	 */
	public function renderNewTaxonomyMetaBox() {
		$Taxonomy = new Meta\Taxonomy();
		$Taxonomy->newMetaBox();
	}

	/**
	 * Renders the meta box for editing a taxonomy
	 *
	 * @since  2.0.0
	 */
	public function renderEditTaxonomyMetaBox($term) {
		$Taxonomy = new Meta\Taxonomy();
		$Taxonomy->editMetaBox($term);
	}

	/**
	 * Renders the meta box for editing a quick edit
	 *
	 * @since  2.0.0
	 */
	public function renderQuickEditMetaBox($columnName) {
		new Meta\QuickEdit($columnName);
	}

	/**
	 * Renders the meta data for the header
	 *
	 * @since  2.0.0
	 */
	public function renderHeader() {
		if (!is_admin()) {
			new Meta\Header();
		}
	}

	/**
	 * Renders the meta data for Analytics
	 *
	 * @since  2.0.0
	 */
	public function renderAnalytics() {
		if (!is_admin()) {
			new Meta\Analytics();
		}
	}
	
}

?>