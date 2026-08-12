<?php 

namespace app\init;

/* Exit if accessed directly. */
if (!defined('ABSPATH')) {
	exit;
}

if (!function_exists('get_home_path')) {
	require_once ABSPATH . 'wp-admin/includes/file.php';
}

class Sitemap {	
	protected function getPermalinkFromId($id) {
		$post_status = get_post_status($id);
		$post_type = get_post_type_object(get_post_type($id));
		if ($post_status === 'private' && $post_type !== null && !current_user_can($post_type->cap->read_private_posts)) {
			return '';
		}
		$url = get_permalink($id);
		if ($url === false) {
			return '';
		}
		return $url;
	}
	
	public function buildSitemap() {
		global $wpdb;
		$path = get_home_path();
		$site_url = trailingslashit(get_site_url());

        // Create XSLT file for beautiful browser rendering
        $xsl_content = '<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:sitemap="http://www.sitemaps.org/schemas/sitemap/0.9">
  <xsl:output method="html" indent="yes" encoding="UTF-8"/>
  <xsl:template match="/">
    <html>
      <head>
        <title>Generated Sitemaps</title>
        <style>
          body { font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen-Sans,Ubuntu,Cantarell,"Helvetica Neue",sans-serif; color: #444; }
          #sitemap { max-width: 980px; margin: 0 auto; }
          table { border: 1px solid #ccc; border-collapse: collapse; width: 100%; margin-top: 20px; }
          th, td { padding: 15px; text-align: left; border-bottom: 1px solid #ccc; }
          th { background-color: #f9f9f9; font-weight: bold; border-bottom: 2px solid #ccc; }
          tr:hover { background-color: #f1f1f1; }
          a { color: #2271b1; text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <div id="sitemap">
          <h2>Generated Sitemaps</h2>
          <table>
            <thead>
              <tr>
                <th>Sitemap</th>
                <th>URL</th>
                <th>Last Modified</th>
                <th>Priority</th>
              </tr>
            </thead>
            <tbody>
              <xsl:for-each select="sitemap:sitemapindex/sitemap:sitemap | sitemap:urlset/sitemap:url">
                <tr>
                  <td>
                    <xsl:variable name="itemURL"><xsl:value-of select="sitemap:loc"/></xsl:variable>
                    <xsl:value-of select="substring-after($itemURL, \'' . rtrim($site_url, '/') . '/\')"/>
                  </td>
                  <td><a href="{sitemap:loc}"><xsl:value-of select="sitemap:loc"/></a></td>
                  <td><xsl:value-of select="concat(substring(sitemap:lastmod,0,11),concat(\' \', substring(sitemap:lastmod,12,5)))"/></td>
                  <td><xsl:value-of select="sitemap:priority"/></td>
                </tr>
              </xsl:for-each>
            </tbody>
          </table>
        </div>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>';
        @unlink($path . 'sitemap.xsl');
        $file = fopen($path . 'sitemap.xsl', "w");
        fwrite($file, $xsl_content);
        fclose($file);

		$sitemap_index = '<?xml version="1.0" encoding="UTF-8"?>' . PHP_EOL . '<?xml-stylesheet type="text/xsl" href="' . $site_url . 'sitemap.xsl"?>' . PHP_EOL . '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . PHP_EOL;

		// 1. POST TYPES
		$postTypes = get_option('sseo_sitemap_post_types');
		if (!is_array($postTypes)) {
			$postTypes = ['post', 'page'];
		}

		foreach ($postTypes as $postType) {
			$qs = $wpdb->prepare("SELECT ID, post_date_gmt FROM {$wpdb->posts} WHERE post_password = '' AND post_status = 'publish' AND post_type = %s ORDER BY post_date_gmt ASC", $postType);
			$posts = $wpdb->get_results($qs);
			if (empty($posts)) continue;

			$xmlString = '<?xml version="1.0" encoding="UTF-8"?>' . PHP_EOL . '<?xml-stylesheet type="text/xsl" href="' . $site_url . 'sitemap.xsl"?>' . PHP_EOL . '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . PHP_EOL;
			$last_mod_index = '';
			foreach($posts as $post) {
				$permalink = $this->getPermalinkFromId($post->ID);
				if (empty($permalink)) continue;
				$last_mod = date('c', strtotime($post->post_date_gmt));
				$last_mod_index = $last_mod;
				$xmlString .= '   <url>' . PHP_EOL .
				'      <loc>'.htmlspecialchars($permalink).'</loc>' . PHP_EOL .
				'      <lastmod>'.$last_mod.'</lastmod>' . PHP_EOL .
				'      <changefreq>weekly</changefreq>' . PHP_EOL .
				'      <priority>0.80</priority>' . PHP_EOL .
				'   </url>' . PHP_EOL;
			}
			$xmlString .= '</urlset>' . PHP_EOL;

			$filename = $postType . 's-sitemap.xml';
			@unlink($path . $filename);
			$file = fopen($path . $filename, "w");
			fwrite($file, $xmlString);
			fclose($file);

			$sitemap_index .= '   <sitemap>' . PHP_EOL .
			'      <loc>' . $site_url . $filename . '</loc>' . PHP_EOL .
			'      <lastmod>' . $last_mod_index . '</lastmod>' . PHP_EOL .
			'   </sitemap>' . PHP_EOL;
		}

		// 2. TAXONOMIES (Categories and Tags)
		$taxonomies = ['category' => 'categories', 'post_tag' => 'tags'];
		foreach ($taxonomies as $tax => $slug) {
			$terms = get_terms(['taxonomy' => $tax, 'hide_empty' => true]);
			if (empty($terms) || is_wp_error($terms)) continue;

			$xmlString = '<?xml version="1.0" encoding="UTF-8"?>' . PHP_EOL . '<?xml-stylesheet type="text/xsl" href="' . $site_url . 'sitemap.xsl"?>' . PHP_EOL . '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . PHP_EOL;
			$last_mod_index = date('c'); 
			foreach($terms as $term) {
				$permalink = get_term_link($term);
				if (is_wp_error($permalink)) continue;
				$xmlString .= '   <url>' . PHP_EOL .
				'      <loc>'.htmlspecialchars($permalink).'</loc>' . PHP_EOL .
				'      <lastmod>'.date('c').'</lastmod>' . PHP_EOL .
				'      <changefreq>weekly</changefreq>' . PHP_EOL .
				'      <priority>0.80</priority>' . PHP_EOL .
				'   </url>' . PHP_EOL;
			}
			$xmlString .= '</urlset>' . PHP_EOL;

			$filename = $slug . '-sitemap.xml';
			@unlink($path . $filename);
			$file = fopen($path . $filename, "w");
			fwrite($file, $xmlString);
			fclose($file);

			$sitemap_index .= '   <sitemap>' . PHP_EOL .
			'      <loc>' . $site_url . $filename . '</loc>' . PHP_EOL .
			'      <lastmod>' . $last_mod_index . '</lastmod>' . PHP_EOL .
			'   </sitemap>' . PHP_EOL;
		}

		$sitemap_index .= '</sitemapindex>' . PHP_EOL;

		@unlink($path.'sitemap.xml');
		$file = fopen($path."sitemap.xml", "w");
		fwrite($file, $sitemap_index);
		fclose($file);		
	}
}
