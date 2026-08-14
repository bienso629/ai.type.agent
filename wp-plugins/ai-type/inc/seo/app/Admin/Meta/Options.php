<?php 

namespace app\Admin\Meta;

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

/**
 * Options class for meta box. This contains the meta box,
 * HTML, form fields, everything to have a SimpleSEO 
 * options page.
 *
 * @since  2.0.0
 */
class Options {
	
    public function __construct() {
		
		if (!empty($_GET['sitemap_deleted'])) {
			echo '<div class="notice notice-success is-dismissible"><p>'.__('The current sitemap has been deleted!', SSEO_TXTDOMAIN).'</p></div>';
		}
		
		if (!empty($_GET['sitemap_created'])) {
			echo '<div class="notice notice-success is-dismissible"><p>'.__('A new sitemap has been created!', SSEO_TXTDOMAIN).'</p></div>';
		}
		
		if (!empty($_GET['yoast'])) {
			echo '<div class="notice notice-success is-dismissible"><p>'.__('Yoast metadata has been coppied to AI Type SEO, awesome!', SSEO_TXTDOMAIN).'</p></div>';
		}
		
		if (!empty($_GET['allinone'])) {
			echo '<div class="notice notice-success is-dismissible"><p>'.__('All in One SEO metadata has been coppied to AI Type SEO, awesome!', SSEO_TXTDOMAIN).'</p></div>';
		}
		
		if (!empty($_GET['rankmath'])) {
			echo '<div class="notice notice-success is-dismissible"><p>'.__('Rank Math metadata has been coppied to AI Type SEO, awesome!', SSEO_TXTDOMAIN).'</p></div>';
		}
		
		// Disabled donation notice
		
		
		$content = '<div class="wrap">';
		$content .= '<h1>AI Type</h1>';
		
		$content .= '<h2 class="nav-tab-wrapper">';
		$content .= '<a href="?page=connect_type" class="nav-tab">Danh sách nút</a>';
		$content .= '<a href="?page=connect_type_chatbot" class="nav-tab">Chatbot</a>';
		$content .= '<a href="?page=connect_type_cdn" class="nav-tab">CDN và Cache</a>';
		$content .= '<a href="?page=connect_type_status" class="nav-tab">Trạng thái</a>';
		$content .= '<a href="?page=simpleSEOAdminOptions" class="nav-tab nav-tab-active">SEO</a>';
		$content .= '<a href="?page=connect_type_setting" class="nav-tab">Cài đặt</a>';
		$content .= '</h2><br>';

		$content .= '<h2>';
		$content .= __('AI Type SEO Options', SSEO_TXTDOMAIN);
		$content .= '</h2>';
		
		$content .= '<form method="post" action="options.php" novalidate>';
		
		echo $content;
		
		settings_fields('sseo-settings-group');
		do_settings_sections('sseo-settings-group');
		
		$content = '<table class="form-table" role="presentation">';
		$content .= '<tbody>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_default_meta_title">';
		$content .= __('Default Meta Title', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '<td>';
		$content .= '<input name="sseo_default_meta_title" type="text" id="sseo_default_meta_title" value="'.esc_attr(get_option('sseo_default_meta_title')).'" class="regular-text">';
		$content .= '<p class="description">';
		$content .= __('This is the default information used for meta title (&lt;title&gt;&lt;&#47;title&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.', SSEO_TXTDOMAIN);
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row">';
		$content .= '<label for="sseo_default_meta_description">';
		$content .= __('Default Meta Description', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';
		$content .= '<textarea name="sseo_default_meta_description" rows="5" cols="50" class="large-text code">'.esc_textarea(get_option('sseo_default_meta_description')).'</textarea>';
		$content .= '<p class="description">';
		$content .= __('This is the default information used for meta description (&lt;meta name="description" content=""&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.', SSEO_TXTDOMAIN);
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row">';
		$content .= '<label for="sseo_default_meta_keywords">';
		$content .= __('Default Meta Keywords', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';
		$content .= '<textarea name="sseo_default_meta_keywords" rows="5" cols="50" class="large-text code">'.esc_textarea(get_option('sseo_default_meta_keywords')).'</textarea>';
		$content .= '<p class="description">';
		$content .= __('This is the default information used for meta keywords (&lt;meta name="keywords" content=""&gt;) this information will only be used if there is no set home page. If a homepage is set, then the meta data will be used from that page.<br/><em>A comma separated list of your most important keywords for this will be written as the meta keywords.</em>', SSEO_TXTDOMAIN);
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		/* sitemap */
		$content .= '<tr>';
		$content .= '<th scope="row">'; 
		$content .= '<label for="sseo_generate_sitemap">';		
		$content .= __('Tạo Sơ đồ trang web (Sitemap)?', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';       
		$sseo_sitemap_selected_n = null;
		$sseo_sitemap_selected_y = null;
		if (get_option('sseo_generate_sitemap') == true) {
			$sseo_sitemap_selected_y = ' selected="selected"';
		} else {
			$sseo_sitemap_selected_n = ' selected="selected"';
		}
		$content .= '<select name="sseo_generate_sitemap">';
		$content .= '<option value="0"'.$sseo_sitemap_selected_n.'>Không</option>';
		$content .= '<option value="1"'.$sseo_sitemap_selected_y.'>Có</option>';
		$content .= '</select>';
		$content .= '<p class="description">';
		$content .= __('Nếu chọn Có, tính năng SEO này sẽ tạo sơ đồ trang web cho website của bạn. Điều này sẽ vô hiệu hóa công cụ tạo sitemap mặc định của WordPress. Bạn phải nhấp vào lưu cài đặt ở bên dưới. Sơ đồ trang web hiện tại của bạn có thể được xem ');
		$content .= '<a href="/sitemap.xml" rel="noopener" target="_blank">';
		$content .= __('tại đây.', SSEO_TXTDOMAIN);
		$content .= '</a>';
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		/* sitemap buttons */
		$content .= '<tr>';
		$content .= '<th scope="row">'; 
		$content .= '</th>';
		$content .= '<td>';  
		$adminUrlCreate = wp_nonce_url(admin_url('admin-post.php?action=sseo_create_sitemap'));
		$adminUrlDel = wp_nonce_url(admin_url('admin-post.php?action=sseo_delete_sitemap'));
		$content .= '<a href="'.$adminUrlCreate.'" class="button button-primary" onClick="return confirm(\'Are you sure you want to create a new sitemap?\')">Create Sitemap</a>&nbsp;<a href="'.$adminUrlDel.'" class="button button-primary" onClick="return confirm(\'Are you sure you want to delete the current sitemap?\')">Delete Sitemap</a>';
		$content .= '</td>';
		$content .= '</tr>';
		
		/* llms.txt */
		$content .= '<tr>';
		$content .= '<th scope="row">'; 
		$content .= '<label for="sseo_generate_llms">';		
		$content .= __('Tạo tệp llms.txt tự động?', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';       
		$sseo_llms_selected_n = null;
		$sseo_llms_selected_y = null;
		if (get_option('sseo_generate_llms') == true) {
			$sseo_llms_selected_y = ' selected="selected"';
		} else {
			$sseo_llms_selected_n = ' selected="selected"';
		}
		$content .= '<select name="sseo_generate_llms">';
		$content .= '<option value="0"'.$sseo_llms_selected_n.'>Không</option>';
		$content .= '<option value="1"'.$sseo_llms_selected_y.'>Có</option>';
		$content .= '</select>';
		$content .= '<p class="description">';
		$content .= __('Nếu chọn Có, tính năng này sẽ tự động thu thập toàn bộ Bài viết (Posts) và Trang (Pages) để tạo thành một tệp llms.txt vật lý trên máy chủ. Tệp này sẽ tự cập nhật mỗi khi có bài viết mới. Tệp llms.txt hiện tại của bạn có thể được xem ');
		$content .= '<a href="/llms.txt" rel="noopener" target="_blank">';
		$content .= __('tại đây.', SSEO_TXTDOMAIN);
		$content .= '</a>';
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';

		$content .= '<tr>';
		$content .= '<th scope="row">'; 
		$content .= 'Sitemap Post Types';
		$content .= '</th>';
		$content .= '<td>'; 
		
		$post_types = get_post_types(['public' => true], 'names');
		$sseo_sitemap_post_types = get_option('sseo_sitemap_post_types');
		$content .= '<select name="sseo_sitemap_post_types[]" multiple>';
		if (is_array($post_types)) {
			foreach($post_types as $post_type) {
				$selected = null;
				if (is_array($sseo_sitemap_post_types) && in_array($post_type, $sseo_sitemap_post_types)) {
					$selected = ' selected="selected"';	
				}
				$content .= '<option value="'.$post_type.'"'.$selected.'>'.$post_type.'</option>';
			}
		}
		$content .= '</select>';
		$content .= '</td>';
		$content .= '</tr>';
		

		
		/* sseo_twitter_username */
		/*$content .= '<tr>';
		$content .= '<th scope="row"><label class="post-attributes-label" for="sseo_twitter_username">';
		$content .= __('Twitter username');
		$content .= '</label>';
		$content .= '<td>';
		$content .= '<input name="sseo_twitter_username" type="text" id="sseo_twitter_username" value="'.esc_attr(get_option('sseo_twitter_username')).'" class="regular-text">';
		$content .= '<p class="description">';
		$content .= __('for example @coledesignstudios');
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		$content .= '<tr>';
		$content .= '<th scope="row"><label class="post-attributes-label" for="sseo_fb_fimage">';
		$content .= __('Facebook Image');
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';
		$content .= '<select name="sseo_fb_fimage">';
		$selected = null;
		$sseo_fb_fimage = esc_attr(get_option('sseo_fb_fimage'));
		if (!empty($sseo_fb_fimage)) {
			$selected = ' selected="selected"';
		}
		$content .= '<option value="0"'.$selected.'>No</option>';
		$content .= '<option value="1"'.$selected.'>Yes</option>';
		$content .= '</select>';
		$content .= '<p class="description">';
		$content .= __('Use the post featured image instead of the facebook image. By default the featured image is used if there is no facebook image.');
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		$content .= '<tr>';
		$content .= '<th scope="row"><label class="post-attributes-label" for="sseo_tw_fimage">';
		$content .= __('Twitter Image');
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>';
		$content .= '<select name="sseo_tw_fimage">';
		$selected = null;
		$sseo_tw_fimage = esc_attr(get_option('sseo_tw_fimage'));
		if (!empty($sseo_tw_fimage)) {
			$selected = ' selected="selected"';
		}
		$content .= '<option value="0"'.$selected.'>No</option>';
		$content .= '<option value="1"'.$selected.'>Yes</option>';
		$content .= '</select>';
		$content .= '<p class="description">';
		$content .= __('Use the post featured image instead of the twitter image. By default the featured image is used if there is no twitter image.');
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';*/
		
		// --- SCHEMA MARKUP (ARTICLE/POST) ---
		$content .= '</tbody></table><hr><h2>Dữ liệu có cấu trúc (Schema Markup)</h2><table class="form-table" role="presentation"><tbody>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_schema_enable">' . __('Bật Schema bài viết', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><label><input type="checkbox" name="sseo_schema_enable" id="sseo_schema_enable" value="1" ' . checked(1, get_option('sseo_schema_enable'), false) . '> Tự động chèn dữ liệu cấu trúc (Article / BlogPosting) vào các bài viết để tạo Kết quả phong phú (Rich Results), giúp tăng tỷ lệ nhấp chuột (CTR).</label></td>';
		$content .= '</tr>';
		
		// --- LOCAL SEO ---
		$content .= '</tbody></table><hr><h2>Local SEO (Doanh nghiệp địa phương)</h2><table class="form-table" role="presentation"><tbody>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_enable">' . __('Bật Local SEO', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><label><input type="checkbox" name="sseo_local_enable" id="sseo_local_enable" value="1" ' . checked(1, get_option('sseo_local_enable'), false) . '> Kích hoạt Schema Markup LocalBusiness/Organization</label></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_type">' . __('Loại hình', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><select name="sseo_local_type" id="sseo_local_type">';
		$content .= '<option value="Organization" ' . selected('Organization', get_option('sseo_local_type'), false) . '>Organization (Tổ chức/Công ty)</option>';
		$content .= '<option value="LocalBusiness" ' . selected('LocalBusiness', get_option('sseo_local_type'), false) . '>LocalBusiness (Doanh nghiệp địa phương)</option>';
		$content .= '</select></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_name">' . __('Tên doanh nghiệp', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><input name="sseo_local_name" type="text" id="sseo_local_name" value="'.esc_attr(get_option('sseo_local_name')).'" class="regular-text"></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_phone">' . __('Số điện thoại', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><input name="sseo_local_phone" type="text" id="sseo_local_phone" value="'.esc_attr(get_option('sseo_local_phone')).'" class="regular-text"></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_address">' . __('Địa chỉ (Đường/Phố)', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><input name="sseo_local_address" type="text" id="sseo_local_address" value="'.esc_attr(get_option('sseo_local_address')).'" class="regular-text"></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_city">' . __('Tỉnh / Thành phố', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><input name="sseo_local_city" type="text" id="sseo_local_city" value="'.esc_attr(get_option('sseo_local_city')).'" class="regular-text"></td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_local_logo">' . __('Đường dẫn Logo (URL)', SSEO_TXTDOMAIN) . '</label></th>';
		$content .= '<td><input name="sseo_local_logo" type="text" id="sseo_local_logo" value="'.esc_attr(get_option('sseo_local_logo')).'" class="large-text"></td>';
		$content .= '</tr>';
		
		// --- IMAGE SEO ---
		$content .= '</tbody></table><hr><h2>Tối ưu Hình ảnh (Image SEO)</h2><table class="form-table" role="presentation"><tbody>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_image_auto_alt">';
		$content .= __('Tự động Thêm ALT Ảnh bị thiếu', SSEO_TXTDOMAIN);
		$content .= '</label></th>';
		$content .= '<td>';
		$content .= '<label><input type="checkbox" name="sseo_image_auto_alt" id="sseo_image_auto_alt" value="1" ' . checked(1, get_option('sseo_image_auto_alt'), false) . '> Tự động chèn Tiêu đề bài viết vào thuộc tính ALT cho các hình ảnh bị thiếu ALT trong nội dung.</label>';
		$content .= '</td>';
		$content .= '</tr>';
		
		// --- MỤC LỤC TỰ ĐỘNG ---
		$content .= '</tbody></table><hr><h2>Mục lục Tự động (Tóm tắt nội dung)</h2><table class="form-table" role="presentation"><tbody>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_toc_enable">';
		$content .= __('Bật Mục lục tự động', SSEO_TXTDOMAIN);
		$content .= '</label></th>';
		$content .= '<td>';
		$content .= '<label><input type="checkbox" name="sseo_toc_enable" id="sseo_toc_enable" value="1" ' . checked(1, get_option('sseo_toc_enable'), false) . '> Hiển thị bảng tóm tắt nội dung ở các bài viết chi tiết.</label>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_toc_title">';
		$content .= __('Tiêu đề Mục lục', SSEO_TXTDOMAIN);
		$content .= '</label></th>';
		$content .= '<td>';
		$content .= '<input name="sseo_toc_title" type="text" id="sseo_toc_title" value="'.esc_attr(get_option('sseo_toc_title')).'" class="regular-text" placeholder="Tóm tắt nội dung">';
		$content .= '<p class="description">Nhập tiêu đề mặc định để sử dụng cho khối Mục lục.</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_toc_list_style">';
		$content .= __('Kiểu danh sách Mục lục', SSEO_TXTDOMAIN);
		$content .= '</label></th>';
		$content .= '<td>';
		$content .= '<select name="sseo_toc_list_style" id="sseo_toc_list_style">';
		$content .= '<option value="ul" ' . selected('ul', get_option('sseo_toc_list_style'), false) . '>Không có thứ tự</option>';
		$content .= '<option value="ol" ' . selected('ol', get_option('sseo_toc_list_style'), false) . '>Có thứ tự</option>';
		$content .= '</select>';
		$content .= '<p class="description">Chọn kiểu danh sách mặc định cho khối Mục lục.</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '<tr>';
		$content .= '<th scope="row"><label>Mục lục Loại trừ Tiêu đề</label></th>';
		$content .= '<td>';
		$content .= '<fieldset>';
		$content .= '<legend class="screen-reader-text"><span>Mục lục Loại trừ Tiêu đề</span></legend>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h1" value="1" ' . checked(1, get_option('sseo_toc_exclude_h1'), false) . '> Tiêu đề H1</label>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h2" value="1" ' . checked(1, get_option('sseo_toc_exclude_h2'), false) . '> Tiêu đề H2</label><br>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h3" value="1" ' . checked(1, get_option('sseo_toc_exclude_h3'), false) . '> Tiêu đề H3</label>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h4" value="1" ' . checked(1, get_option('sseo_toc_exclude_h4'), false) . '> Tiêu đề H4</label><br>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h5" value="1" ' . checked(1, get_option('sseo_toc_exclude_h5'), false) . '> Tiêu đề H5</label>';
		$content .= '<label style="display:inline-block; width:150px;"><input type="checkbox" name="sseo_toc_exclude_h6" value="1" ' . checked(1, get_option('sseo_toc_exclude_h6'), false) . '> Tiêu đề H6</label>';
		$content .= '<p class="description">Chọn các tiêu đề để loại trừ khỏi khối Mục lục.</p>';
		$content .= '</fieldset>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '</tbody></table><hr><h2>Quản trị Hệ thống</h2><table class="form-table" role="presentation"><tbody>';

		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_htaccess">';
		$content .= __('Chỉnh sửa .htaccess', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>'; 
		
		require_once(ABSPATH . 'wp-admin/includes/file.php');
		$htaccess_file = get_home_path() . '.htaccess';
		$htaccess_content = '';
		if (file_exists($htaccess_file)) {
			$htaccess_content = file_get_contents($htaccess_file);
		}
		
		$content .= '<textarea name="sseo_htaccess" id="sseo_htaccess" rows="15" class="large-text code" style="font-family: monospace;">'.esc_textarea($htaccess_content).'</textarea>';
		$content .= '<p class="description" style="color: red; font-weight: bold;">';
		$content .= __('Cảnh báo: Cẩn thận khi chỉnh sửa file này. Một lỗi nhỏ cũng có thể làm trang web của bạn bị sập (Lỗi 500).', SSEO_TXTDOMAIN);
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';

		$content .= '<tr>';
		$content .= '<th scope="row"><label for="sseo_robots_txt">';
		$content .= __('Chỉnh sửa robots.txt', SSEO_TXTDOMAIN);
		$content .= '</label>';
		$content .= '</th>';
		$content .= '<td>'; 
		
		$robots_file = get_home_path() . 'robots.txt';
		$robots_content = '';
		if (file_exists($robots_file)) {
			$robots_content = file_get_contents($robots_file);
		} else {
			$robots_content = "# As a condition of accessing this website, you agree to abide by the following\n";
			$robots_content .= "# content signals:\n#\n";
			$robots_content .= "# (a)  If a Content-Signal = yes, you may collect content for the corresponding\n#      use.\n";
			$robots_content .= "# (b)  If a Content-Signal = no, you may not collect content for the\n#      corresponding use.\n";
			$robots_content .= "# (c)  If the website operator does not include a Content-Signal for a\n#      corresponding use, the website operator neither grants nor restricts\n#      permission via Content-Signal with respect to the corresponding use.\n#\n";
			$robots_content .= "# The content signals and their meanings are:\n#\n";
			$robots_content .= "# search:   building a search index and providing search results (e.g., returning\n#           hyperlinks and short excerpts from your website's contents). Search does not\n#           include providing AI-generated search summaries.\n";
			$robots_content .= "# ai-input: inputting content into one or more AI models (e.g., retrieval\n#           augmented generation, grounding, or other real-time taking of content for\n#           generative AI search answers).\n\n";
			$robots_content .= "User-Agent: *\n";
			$robots_content .= "Disallow: /wp-admin/\n";
			$robots_content .= "Allow: /wp-admin/admin-ajax.php\n\n";
			$robots_content .= "Sitemap: https://plugins.type.vn/sitemap.xml";
		}
		
		$content .= '<textarea name="sseo_robots_txt" id="sseo_robots_txt" rows="10" class="large-text code" style="font-family: monospace;">'.esc_textarea($robots_content).'</textarea>';
		$content .= '<p class="description">';
		$content .= __('File robots.txt giúp hướng dẫn các công cụ tìm kiếm (như Google) cách cào dữ liệu trên website của bạn.', SSEO_TXTDOMAIN);
		$content .= '</p>';
		$content .= '</td>';
		$content .= '</tr>';
		
		$content .= '</tbody>';
		$content .= '</table>';
		
		$content .= '<input type="submit" name="submit" id="submit" class="button button-primary" value="';
		$content .= __('Save Changes', SSEO_TXTDOMAIN);
		$content .= '">&nbsp;&nbsp;';
		

		
		$content .= '</form>';
		
		// Version text removed
		
		$content .= '</div>';
		
		echo $content;
    }
	
}

?>