<?php 

namespace app\Admin\Meta;

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

use app\Helpers as Helper;

/**
 * Post class for meta box. This contains the meta box,
 * HTML, form fields, everything to have a SimpleSEO work 
 * for pages and posts.
 *
 * @since  2.0.0
 */
class Post {

    public function __construct($post) {
		$form = new Helper\Form();

		wp_nonce_field(SSEO_PATH, 'sseo_nonce');

		$content = '<div class="ai-type-seo-metabox-tabs">';
		$content .= '<input id="ai-type-seo-tab1" type="radio" name="tab-group" checked="checked" />';
		$content .= '<label class="tab active" for="ai-type-seo-tab1">'.__('SEO', SSEO_TXTDOMAIN).'</label>';
		$content .= '<input id="ai-type-seo-tab2" type="radio" name="tab-group" />';
		$content .= '<label class="tab" for="ai-type-seo-tab2">'.__('Từ khóa', SSEO_TXTDOMAIN).'</label>';
		$content .= '<input id="ai-type-seo-tab3" type="radio" name="tab-group" />';
		$content .= '<label class="tab" for="ai-type-seo-tab3">'.__('Máy tìm kiếm (Robots)', SSEO_TXTDOMAIN).'</label>';
		$content .= '<input id="ai-type-seo-tab4" type="radio" name="tab-group" />';
		$content .= '<label class="tab" for="ai-type-seo-tab4">'.__('Facebook', SSEO_TXTDOMAIN).'</label>';
		$content .= '<input id="ai-type-seo-tab5" type="radio" name="tab-group" />';
		$content .= '<label class="tab" for="ai-type-seo-tab5">'.__('Twitter', SSEO_TXTDOMAIN).'</label>';
		$content .= '<input id="ai-type-seo-tab6" type="radio" name="tab-group" />';
		$content .= '<label class="tab" for="ai-type-seo-tab6">'.__('Nâng cao', SSEO_TXTDOMAIN).'</label>';

		$content .= '<div id="ai-type-seo-preview" class="ai-type-seo-tab">';

		$sseo_meta_title = esc_html(get_post_meta($post->ID, 'sseo_meta_title', true));
		if (empty($sseo_meta_title)) {
			$sseo_meta_title = esc_html($post->post_title);
		}
		
		$sseo_meta_description = esc_html(get_post_meta($post->ID, 'sseo_meta_description', true));
		if (empty($sseo_meta_description)) {
			$excerpt = $post->post_excerpt;
			if (empty($excerpt)) {
				$excerpt = wp_trim_words(strip_shortcodes(strip_tags($post->post_content)), 25);
			}
			$sseo_meta_description = esc_html($excerpt);
		}

		$sseo_canonical_url = esc_html(get_post_meta($post->ID, 'sseo_canonical_url', true));
		if (empty($sseo_canonical_url)) {
			$sseo_canonical_url = esc_html(get_permalink($post->ID));
		}
		$sseo_meta_keywords = esc_html(get_post_meta($post->ID, 'sseo_meta_keywords', true));
		if (empty($sseo_meta_keywords)) {
			$tags = wp_get_post_tags($post->ID, array('fields' => 'names'));
			if (!empty($tags)) {
				$sseo_meta_keywords = esc_html(implode(', ', $tags));
			}
		}
		$sseo_robot_noindex = esc_html(get_post_meta($post->ID, 'sseo_robot_noindex', true));
		$sseo_robot_nofollow = esc_html(get_post_meta($post->ID, 'sseo_robot_nofollow', true));
		$sseo_fb_title = esc_html(get_post_meta($post->ID, 'sseo_fb_title', true));
		$sseo_fb_description = esc_html(get_post_meta($post->ID, 'sseo_fb_description', true));
		$sseo_fb_image = esc_html(get_post_meta($post->ID, 'sseo_fb_image', true));
		$sseo_tw_title = esc_html(get_post_meta($post->ID, 'sseo_tw_title', true));
		$sseo_tw_description = esc_html(get_post_meta($post->ID, 'sseo_tw_description', true));
		$sseo_tw_image = esc_html(get_post_meta($post->ID, 'sseo_tw_image', true));
		$current_url = get_permalink($post->ID);

		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>'.__('Xem trước', SSEO_TXTDOMAIN).'</h3>';
		$content .= '<div class="preview_snippet">';
		$content .= '<div id="sseo_snippet">';
		$content .= '<a><span id="sseo_snippet_title">'.$sseo_meta_title.'</span></a>';
		$content .= '<div class="ai-type-seo-current-url">';
		$content .= '<cite id="sseo_snippet_link">'.$current_url.'</cite>';
		$content .= '</div>'; /* ai-type-seo-current-url */
		$content .= '<span id="sseo_snippet_description">'.esc_attr($sseo_meta_description).'</span>';
		$content .= '</div>'; /* sseo_snippet */
		$content .= '</div>'; /* preview_snippet */
		$content .= '</div>'; /* ai-type-seo-section */

		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>';
		$content .= __('SEO', SSEO_TXTDOMAIN);
		$content .= '</h3>';

		$content .= $form->input('sseo_meta_title', array(
			'label' => __('Tiêu đề SEO', SSEO_TXTDOMAIN),
			'value' => $sseo_meta_title,
		));

		$content .= '<p><span id="sseo_title_count">0</span> '.__('ký tự. Công cụ tìm kiếm hiển thị tốt nhất dưới 60 ký tự.', SSEO_TXTDOMAIN).'</p>';

		$content .= $form->textarea('sseo_meta_description', array(
			'label' => __('Mô tả (Meta Description)', SSEO_TXTDOMAIN),
			'value' => $sseo_meta_description,
		));

		$content .= '<p><span id="sseo_desc_count">0</span> '.__('ký tự. Công cụ tìm kiếm hiển thị tốt nhất dưới 160 ký tự.', SSEO_TXTDOMAIN).'</p>';

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* #ai-type-seo-preview */

		$content .= '<div id="ai-type-seo-keywords" class="ai-type-seo-tab">';
		$content .= '<div class="ai-type-seo-section">';

		$content .= $form->textarea('sseo_meta_keywords', array(
			'label' => __('Từ khóa', SSEO_TXTDOMAIN),
			'value' => $sseo_meta_keywords,
		));

		$content .= '<p>';
		$content .= __('Danh sách các từ khóa quan trọng nhất cho trang này, cách nhau bằng dấu phẩy.', SSEO_TXTDOMAIN);
		$content .= '</p>';

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* ai-type-seo-keywords */

		$content .= '<div id="ai-type-seo-robots" class="ai-type-seo-tab">';
		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>'.__('Máy tìm kiếm (Robots)', SSEO_TXTDOMAIN).'</h3>';

		$content .= $form->input('sseo_robot_noindex', array(
			'type' => 'checkbox',
			'label' => __('Chặn lập chỉ mục (NOINDEX)', SSEO_TXTDOMAIN),
			'checked' => $sseo_robot_noindex,
		));

		$content .= $form->input('sseo_robot_nofollow', array(
			'type' => 'checkbox',
			'label' => __('Chặn theo liên kết (NOFOLLOW)', SSEO_TXTDOMAIN),
			'checked' => $sseo_robot_nofollow,
		));

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* #ai-type-seo-robots */



		$content .= '<div id="ai-type-seo-facebook" class="ai-type-seo-tab">';
		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>'.__('Facebook', SSEO_TXTDOMAIN).'</h3>';

		$content .= $form->input('sseo_fb_title', array(
			'label' => __('Tiêu đề Facebook', SSEO_TXTDOMAIN),
			'value' => $sseo_fb_title,
		));

		$content .='<p>';
		$content .= __('Tiêu đề được chia sẻ trên Facebook. Nếu để trống, tiêu đề bài viết sẽ được sử dụng.', SSEO_TXTDOMAIN);
		$content .= '</p>';

		$content .= $form->textarea('sseo_fb_description', array(
			'label' => __('Mô tả Facebook', SSEO_TXTDOMAIN),
			'value' => $sseo_fb_description,
		));

		$content .= '<p>'.__('Mô tả được chia sẻ trên Facebook. Nếu để trống, mô tả bài viết sẽ được sử dụng.', SSEO_TXTDOMAIN).'</p>';
		
		$content .= '<div class="fb-img-container">';

		$image = null;
		if (intval($sseo_fb_image) > 0) {
			$image = wp_get_attachment_image($sseo_fb_image, 'medium', false, array('id' => 'sseo-fb-preview-image', 'class' => 'media-input', 'style' => 'display:block !important;'));
		} else {
			//$image = '<img id="sseo-fb-preview-image" src="" class="media-input" />';
		}

		$content .= $image.'</div><div class="clearfix">&nbsp;</div>';

		$content .= '<input type="hidden" name="sseo_fb_image" value="'.esc_attr($sseo_fb_image).'" id="sseo-fb-image" />
		<input type="button" class="button-primary sseo-media-button" value="'.__('Tải lên / Chọn ảnh', SSEO_TXTDOMAIN).'" id="sseo_fb_media_manager"/>
		<input type="button" class="button-primary sseo-media-button" value="'.__('Xóa ảnh', SSEO_TXTDOMAIN).'" id="sseo-fb-media-remove"/>';

		$content .= '<p>'.__('If you want to override the image used on Facebook for this post, upload / choose an image here. The size of the image file must not exceed 8 MB. Use images that are at least 1200 x 630 pixels for the best display on high resolution devices. At the minimum, you should use images that are 600 x 315 pixels to display link page posts with larger images.', SSEO_TXTDOMAIN).'</p>';

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* #ai-type-seo-facebook */



		$content .= '<div id="ai-type-seo-twitter" class="ai-type-seo-tab">';
		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>'.__('Twitter', SSEO_TXTDOMAIN).'</h3>';

		$content .= $form->input('sseo_tw_title', array(
			'label' => __('Tiêu đề Twitter', SSEO_TXTDOMAIN),
			'value' => $sseo_tw_title,
		));

		$content .= '<p>'.__('Tiêu đề được chia sẻ trên Twitter. Nếu để trống, tiêu đề bài viết sẽ được sử dụng.', SSEO_TXTDOMAIN).'</p>';

		$content .= $form->textarea('sseo_tw_description', array(
			'label' => __('Mô tả Twitter', SSEO_TXTDOMAIN),
			'value' => $sseo_tw_description,
		));

		$content .= '<p>'.__('Mô tả được chia sẻ trên Twitter. Nếu để trống, mô tả bài viết sẽ được sử dụng.', SSEO_TXTDOMAIN).'</p>';
		
		$content .= '<div class="tw-img-container">';

		$image = null;
		if (intval($sseo_tw_image) > 0) {
			$image = wp_get_attachment_image($sseo_tw_image, 'medium', false, array('id' => 'sseo-tw-preview-image', 'class' => 'media-input', 'style' => 'display:block !important;'));
		} else {
			//$image = '<img id="sseo-tw-preview-image" src="" class="media-input" />';
		}

		$content .= $image.'</div><div class="clearfix">&nbsp;</div>';

		$content .= '<input type="hidden" name="sseo_tw_image" value="'.esc_attr($sseo_tw_image).'" id="sseo-tw-image" />
		<input type="button" class="button-primary sseo-media-button" value="'.__('Tải lên / Chọn ảnh', SSEO_TXTDOMAIN).'" id="sseo_tw_media_manager"/>
		<input type="button" class="button-primary sseo-media-button" value="'.__('Xóa ảnh', SSEO_TXTDOMAIN).'" id="sseo-tw-media-remove"/>';

		$content .= '<p>'.__('If you want to override the image used on Twitter for this post, upload / choose an image here. The recommended image size for Twitter is 1024 by 512 pixels.', SSEO_TXTDOMAIN).'</p>';

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* #ai-type-seo-twitter */

		$content .= '<div id="ai-type-seo-advanced" class="ai-type-seo-tab">';
		$content .= '<div class="ai-type-seo-section">';
		$content .= '<h3>'.__('Nâng cao', SSEO_TXTDOMAIN).'</h3>';

		$content .= $form->input('sseo_canonical_url', array(
			'label' => 'Đường dẫn chuẩn (Canonical URL)',
			'value' => $sseo_canonical_url,
		));
		$content .= '<div class="clearfix">&nbsp;</div>';

		$content .= '</div>'; /* .ai-type-seo-section */
		$content .= '</div>'; /* #ai-type-seo-advanced */

		$content .= '<div class="clearfix">&nbsp;</div>';
		$content .= '</div>'; /* .ai-type-seo-metabox-tabs */

		echo $content;
    }
	
}

?>