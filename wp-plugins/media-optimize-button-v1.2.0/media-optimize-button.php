<?php
/*
Plugin Name: Media Optimize Button (MOB)
Plugin URI: https://example.com
Description: Thêm nút "Optimize", cột "Size" và cơ chế tối ưu an toàn cho PNG (fallback regenerate thumbnails) + lưu tạm rồi thay thế file gốc để tránh lỗi fatal.
Version: 1.2.0
Author: mang
License: GPLv2 or later
Text Domain: media-optimize-button
*/

if ( ! defined( 'ABSPATH' ) ) { exit; }

class MOB_Plugin {
    const NONCE_ACTION   = 'mob_optimize_attachment_';
    const FILESIZE_META  = '_mob_filesize';

    public static function init() {
        add_action( 'admin_enqueue_scripts', [ __CLASS__, 'enqueue' ] );
        add_filter( 'media_row_actions', [ __CLASS__, 'add_row_action' ], 10, 3 );
        add_filter( 'bulk_actions-upload', [ __CLASS__, 'register_bulk_action' ] );
        add_filter( 'handle_bulk_actions-upload', [ __CLASS__, 'handle_bulk_action' ], 10, 3 );
        add_action( 'admin_notices', [ __CLASS__, 'bulk_notice' ] );
        add_action( 'add_meta_boxes_attachment', [ __CLASS__, 'add_metabox' ] );
        add_action( 'wp_ajax_mob_optimize_image', [ __CLASS__, 'ajax_optimize_single' ] );

        // Columns: Size + sorting
        add_filter( 'manage_media_columns', [ __CLASS__, 'add_size_column' ] );
        add_filter( 'manage_upload_columns', [ __CLASS__, 'add_size_column' ] );
        add_action( 'manage_media_custom_column', [ __CLASS__, 'render_custom_column' ], 10, 2 );
        add_filter( 'manage_upload_sortable_columns', [ __CLASS__, 'register_sortable_column' ] );
        add_action( 'pre_get_posts', [ __CLASS__, 'handle_size_sorting' ] );

        // Keep filesize meta updated
        add_action( 'add_attachment', [ __CLASS__, 'update_filesize_meta' ] );
        add_action( 'edit_attachment', [ __CLASS__, 'update_filesize_meta' ] );
    }

    public static function enqueue( $hook ) {
        $is_media_list = ( 'upload.php' === $hook );
        $is_attachment_edit = ( 'post.php' === $hook && isset($_GET['post']) && 'attachment' === get_post_type( intval($_GET['post']) ) );

        if ( $is_media_list || $is_attachment_edit ) {
            wp_enqueue_script(
                'mob-admin',
                plugins_url( 'assets/admin.js', __FILE__ ),
                [ 'jquery' ],
                '1.2.0',
                true
            );
            wp_localize_script( 'mob-admin', 'MOB', [
                'ajaxUrl' => admin_url( 'admin-ajax.php' ),
                'i18n'    => [
                    'optimizing' => __( 'Đang tối ưu...', 'media-optimize-button' ),
                    'done'       => __( 'Đã tối ưu', 'media-optimize-button' ),
                    'failed'     => __( 'Tối ưu thất bại', 'media-optimize-button' ),
                ],
            ] );
            wp_enqueue_style(
                'mob-admin',
                plugins_url( 'assets/admin.css', __FILE__ ),
                [],
                '1.2.0'
            );
        }
    }

    public static function add_row_action( $actions, $post, $detached ) {
        if ( 'attachment' !== $post->post_type ) return $actions;
        if ( ! wp_attachment_is_image( $post->ID ) )  return $actions;
        if ( ! current_user_can( 'edit_post', $post->ID ) ) return $actions;

        $nonce = wp_create_nonce( self::NONCE_ACTION . $post->ID );
        $label = esc_html__( 'Optimize', 'media-optimize-button' );
        $actions['mob_optimize'] = sprintf(
            '<a href="#" class="mob-optimize-link" data-id="%d" data-nonce="%s">%s</a>',
            $post->ID, esc_attr( $nonce ), $label
        );
        return $actions;
    }

    public static function register_bulk_action( $bulk_actions ) {
        $bulk_actions['mob_bulk_optimize'] = __( 'Optimize images (MOB)', 'media-optimize-button' );
        return $bulk_actions;
    }

    public static function handle_bulk_action( $redirect_url, $action, $post_ids ) {
        if ( 'mob_bulk_optimize' !== $action ) return $redirect_url;
        $count = 0;
        foreach ( $post_ids as $post_id ) {
            $result = self::optimize_attachment( intval( $post_id ) );
            if ( true === $result ) $count++;
        }
        return add_query_arg( [ 'mob_optimized' => $count ], $redirect_url );
    }

    public static function bulk_notice() {
        if ( ! isset( $_GET['mob_optimized'] ) ) return;
        $count = intval( $_GET['mob_optimized'] );
        if ( $count > 0 ) {
            printf('<div class="notice notice-success is-dismissible"><p>%s</p></div>',
                esc_html( sprintf( _n( 'Đã tối ưu %d ảnh.', 'Đã tối ưu %d ảnh.', $count, 'media-optimize-button' ), $count ) )
            );
        } else {
            echo '<div class="notice notice-warning is-dismissible"><p>' . esc_html__( 'Không có ảnh nào được tối ưu.', 'media-optimize-button' ) . '</p></div>';
        }
    }

    public static function add_metabox() {
        add_meta_box(
            'mob-optimize-box',
            __( 'Media Optimize Button', 'media-optimize-button' ),
            [ __CLASS__, 'render_metabox' ],
            'attachment',
            'side',
            'high'
        );
    }

    public static function render_metabox( $post ) {
        if ( ! wp_attachment_is_image( $post->ID ) ) {
            echo '<p>' . esc_html__( 'Đính kèm này không phải là ảnh.', 'media-optimize-button' ) . '</p>';
            return;
        }
        $nonce = wp_create_nonce( self::NONCE_ACTION . $post->ID );
        echo '<p><button type="button" class="button button-primary mob-optimize-btn" data-id="' . esc_attr( $post->ID ) . '" data-nonce="' . esc_attr( $nonce ) . '">' . esc_html__( 'Optimize ảnh này', 'media-optimize-button' ) . '</button></p>';
        echo '<p class="description">' . esc_html__( 'Nén ảnh gốc theo chất lượng tiêu chuẩn + tái tạo thumbnail. Có fallback an toàn cho PNG khi server thiếu thư viện/bộ nhớ.', 'media-optimize-button' ) . '</p>';
    }

    public static function ajax_optimize_single() {
        $id = isset($_POST['id']) ? intval($_POST['id']) : 0;
        if ( ! $id ) wp_send_json_error( __( 'Thiếu ID ảnh.', 'media-optimize-button' ) );
        check_ajax_referer( self::NONCE_ACTION . $id );
        if ( ! current_user_can( 'edit_post', $id ) ) wp_send_json_error( __( 'Bạn không có quyền.', 'media-optimize-button' ) );

        $result = self::optimize_attachment( $id );
        if ( true === $result ) {
            $meta = wp_get_attachment_metadata( $id );
            $sizes = isset( $meta['sizes'] ) ? array_keys( $meta['sizes'] ) : [];
            self::update_filesize_meta( $id );
            wp_send_json_success( [ 'message' => __( 'Đã tối ưu', 'media-optimize-button' ), 'sizes' => $sizes ] );
        } else {
            $error = is_wp_error( $result ) ? $result->get_error_message() : __( 'Không xác định.', 'media-optimize-button' );
            wp_send_json_error( $error );
        }
    }

    /**
     * Optimize an attachment image with safety for PNG.
     * - Recompress to temp file then replace original.
     * - Regenerate thumbnails.
     * - On PNG, fallback to "thumbnails-only" if editor not available or save fails.
     * Returns true|WP_Error.
     */
    protected static function optimize_attachment( $attachment_id ) {
        if ( ! wp_attachment_is_image( $attachment_id ) ) {
            return new WP_Error( 'not_image', __( 'Tệp không phải là ảnh.', 'media-optimize-button' ) );
        }
        $file = get_attached_file( $attachment_id );
        if ( ! $file || ! file_exists( $file ) ) {
            return new WP_Error( 'missing_file', __( 'Không tìm thấy tệp nguồn.', 'media-optimize-button' ) );
        }

        $mime = get_post_mime_type( $attachment_id );
        $is_png = ( 'image/png' === $mime );

        // Allow site owner to force strategy
        $png_strategy = apply_filters( 'mob_png_strategy', 'recompress', $attachment_id ); // 'recompress' | 'thumbnails_only'

        // Try to open editor
        $editor = wp_get_image_editor( $file );
        if ( is_wp_error( $editor ) ) {
            if ( $is_png && 'thumbnails_only' === $png_strategy ) {
                $meta = wp_generate_attachment_metadata( $attachment_id, $file );
                if ( ! is_wp_error( $meta ) ) {
                    wp_update_attachment_metadata( $attachment_id, $meta );
                    self::update_filesize_meta( $attachment_id );
                    return true;
                }
            }
            return $editor;
        }

        // Optional: bump temporary memory limit (filter-adjustable)
        $tmp_mem = apply_filters( 'mob_temp_memory_limit', null );
        if ( $tmp_mem ) { @ini_set( 'memory_limit', $tmp_mem ); }

        // Set quality/compression
        $quality = apply_filters( 'mob_image_quality', 82, $attachment_id );
        if ( method_exists( $editor, 'set_quality' ) ) { $editor->set_quality( intval( $quality ) ); }

        // Save to a temp file first
        $tmp = wp_tempnam( wp_basename( $file ) );
        if ( ! $tmp ) { return new WP_Error( 'temp_failed', __( 'Không tạo được tệp tạm.', 'media-optimize-button' ) ); }
        $saved = $editor->save( $tmp, $mime );

        if ( is_wp_error( $saved ) ) {
            if ( $is_png && 'thumbnails_only' === $png_strategy ) {
                $meta = wp_generate_attachment_metadata( $attachment_id, $file );
                if ( ! is_wp_error( $meta ) ) {
                    wp_update_attachment_metadata( $attachment_id, $meta );
                    self::update_filesize_meta( $attachment_id );
                    return true;
                }
            }
            return $saved;
        }

        // Replace original with temp
        $saved_path = isset( $saved['path'] ) ? $saved['path'] : $tmp;
        if ( ! @copy( $saved_path, $file ) ) {
            if ( ! @rename( $saved_path, $file ) ) {
                @unlink( $tmp );
                return new WP_Error( 'replace_failed', __( 'Không thể ghi đè tệp gốc.', 'media-optimize-button' ) );
            }
        }
        @unlink( $tmp );

        // Regenerate metadata / thumbnails
        $meta = wp_generate_attachment_metadata( $attachment_id, $file );
        if ( is_wp_error( $meta ) ) { return $meta; }
        wp_update_attachment_metadata( $attachment_id, $meta );

        // Generate WEBP if supported
        $webp_enabled = apply_filters( 'mob_generate_webp', true, $attachment_id );
        if ( $webp_enabled && self::webp_supported() ) {
            self::maybe_generate_webp_copy( $file, $attachment_id );
        }

        self::update_filesize_meta( $attachment_id );
        return true;
    }

    protected static function webp_supported() {
        if ( function_exists( 'wp_image_editor_supports' ) ) {
            return wp_image_editor_supports( [ 'mime_type' => 'image/webp' ] );
        }
        return false;
    }

    protected static function maybe_generate_webp_copy( $file, $attachment_id ) {
        $pathinfo  = pathinfo( $file );
        $webp_path = $pathinfo['dirname'] . '/' . $pathinfo['filename'] . '.webp';
        if ( file_exists( $webp_path ) ) return;

        $editor = wp_get_image_editor( $file );
        if ( is_wp_error( $editor ) ) return;

        if ( method_exists( $editor, 'set_quality' ) ) {
            $quality = apply_filters( 'mob_webp_quality', 80, $attachment_id );
            $editor->set_quality( intval( $quality ) );
        }

        if ( method_exists( $editor, 'save' ) ) {
            $result = $editor->save( $webp_path, 'image/webp' );
            if ( ! is_wp_error( $result ) ) { update_post_meta( $attachment_id, '_mob_webp_generated', 1 ); }
        }
    }

    // ===== Size column and helpers =====
    public static function add_size_column( $columns ) {
        $new = []; $inserted = false;
        foreach ( $columns as $key => $label ) {
            $new[ $key ] = $label;
            if ( 'author' === $key && ! $inserted ) {
                $new['mob_size'] = __( 'Size', 'media-optimize-button' );
                $inserted = true;
            }
        }
        if ( ! $inserted ) $new['mob_size'] = __( 'Size', 'media-optimize-button' );
        return $new;
    }

    public static function render_custom_column( $column_name, $post_id ) {
        if ( 'mob_size' !== $column_name ) return;
        if ( ! wp_attachment_is_image( $post_id ) ) { echo '&mdash;'; return; }
        $size = self::get_filesize_bytes( $post_id );
        if ( $size <= 0 ) { echo esc_html__( 'N/A', 'media-optimize-button' ); return; }
        $human = size_format( $size, 2 );
        $class = '';
        if ( $size >= 3 * 1024 * 1024 ) $class = 'mob-size--heavy';
        elseif ( $size >= 1 * 1024 * 1024 ) $class = 'mob-size--medium';
        printf( '<span class="mob-size %s" title="%s">%s</span>', esc_attr( $class ), esc_attr( number_format_i18n( $size ) . ' bytes' ), esc_html( $human ) );
    }

    public static function register_sortable_column( $sortable ) {
        $sortable['mob_size'] = 'mob_size';
        return $sortable;
    }

    public static function handle_size_sorting( $query ) {
        if ( ! is_admin() || ! $query->is_main_query() ) return;
        $screen = function_exists('get_current_screen') ? get_current_screen() : null;
        if ( $screen && 'upload' !== $screen->id ) return;
        if ( isset( $_GET['orderby'] ) && 'mob_size' === $_GET['orderby'] ) {
            $query->set( 'meta_key', self::FILESIZE_META );
            $query->set( 'orderby', 'meta_value_num' );
            if ( ! isset( $_GET['order'] ) ) $query->set( 'order', 'DESC' );
        }
    }

    public static function update_filesize_meta( $attachment_id ) {
        if ( 'attachment' !== get_post_type( $attachment_id ) ) return;
        $file = get_attached_file( $attachment_id );
        if ( ! $file || ! file_exists( $file ) ) { delete_post_meta( $attachment_id, self::FILESIZE_META ); return; }
        $bytes = @filesize( $file );
        if ( false === $bytes ) { delete_post_meta( $attachment_id, self::FILESIZE_META ); return; }
        update_post_meta( $attachment_id, self::FILESIZE_META, intval( $bytes ) );
    }

    protected static function get_filesize_bytes( $attachment_id ) {
        $bytes = get_post_meta( $attachment_id, self::FILESIZE_META, true );
        if ( '' === $bytes ) {
            self::update_filesize_meta( $attachment_id );
            $bytes = get_post_meta( $attachment_id, self::FILESIZE_META, true );
        }
        return intval( $bytes );
    }
}

MOB_Plugin::init();
