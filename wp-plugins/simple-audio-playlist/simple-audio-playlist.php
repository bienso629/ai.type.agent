<?php
/**
 * Plugin Name: Simple Audio Playlist
 * Description: Hiển thị playlist audio có tự động phát, lưu trạng thái, responsive, hỗ trợ Gutenberg, và cho phép nhập tiêu đề tùy chỉnh.
 * Version: 1.17
 * Author: Yen AI
 */

add_shortcode('simple_playlist', 'sap_render_playlist');

// Enqueue CSS + JS cho frontend
add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style('sap-style', plugins_url('/assets/style.css', __FILE__));
    wp_enqueue_script('sap-script', plugins_url('/assets/script.js', __FILE__), [], false, true);
});

// Đăng ký block Gutenberg
add_action('init', function () {
    if (function_exists('register_block_type')) {
        // Load JS cho editor
        wp_register_script(
            'sap-block-editor',
            plugins_url('block/edit.js', __FILE__),
            ['wp-blocks', 'wp-element', 'wp-editor', 'wp-components'],
            filemtime(__DIR__ . '/block/edit.js')
        );

        // Load CSS cho editor
        wp_register_style(
            'sap-block-style',
            plugins_url('block/style.css', __FILE__),
            [],
            filemtime(__DIR__ . '/block/style.css')
        );

        // Đăng ký block
        register_block_type(__DIR__ . '/block', [
            'editor_script' => 'sap-block-editor',
            'editor_style'  => 'sap-block-style',
            'render_callback' => 'sap_render_audio_playlist_block',
        ]);
    }
});

function sap_render_audio_playlist_block($attributes) {
    if (!isset($attributes['ids']) || empty($attributes['ids'])) {
        return '<p style="color:red">Không có audio nào được nhập.</p>';
    }

    $items_raw = explode(',', $attributes['ids']);
    $playlist = [];

    foreach ($items_raw as $item_raw) {
        $item = trim($item_raw);
        if (empty($item)) continue;

        $parts = explode('|', $item);
        $url = trim($parts[0] ?? '');
        $title = trim($parts[1] ?? 'Audio không tên');

        if (!filter_var($url, FILTER_VALIDATE_URL)) continue;

        $playlist[] = [
            'url' => esc_url($url),
            'title' => esc_html($title)
        ];
    }

    if (empty($playlist)) {
        return '<p style="color:red">Không có audio nào hợp lệ.</p>';
    }

    ob_start(); ?>
    <div class="sap-playlist" data-sap-playlist>
        <ul class="sap-list">
            <?php foreach ($playlist as $index => $item): ?>
                <li data-index="<?php echo $index; ?>" data-src="<?php echo $item['url']; ?>">
                    <?php echo $item['title']; ?>
                </li>
            <?php endforeach; ?>
        </ul>
        <audio controls id="sap-player" preload="auto" style="width: 100%; margin-top: 10px;"></audio>
    </div>
    <style>
    .sap-playlist {
        padding: 15px;
        margin-bottom: 30px;
        border-radius: 8px;
        background: #f9f9f9;
        max-width: 100%;
    }
    .sap-playlist ul {
        display: flex;
        list-style: none;
        padding: 0;
        margin: 0;
    }
    .sap-playlist audio {
        width: 100%;
        margin-top: 10px;
    }
    .sap-playlist li {
        padding: 10px;
        margin: 0 0 5px 0 !important;
        border-radius: 5px;
        cursor: pointer;
        transition: background 0.2s ease;
        word-break: break-word;
    }
    .sap-playlist li:hover {
        background: #eef;
    }
    .sap-playlist li.active {
        font-weight: bold;
        color: #0073aa;
        background: #e0f0ff;
    }
    @media (max-width: 600px) {
        .sap-playlist li {
            font-size: 16px;
            padding: 10px;
        }
    }
    </style>
    <?php
    return ob_get_clean();
}

// Hàm hiển thị playlist
function sap_render_playlist($atts) {
    $atts = shortcode_atts(['ids' => ''], $atts, 'simple_playlist');
    if (empty($atts['ids'])) return 'No audio provided.';

    $items = explode(',', $atts['ids']);
    $output = '<div class="simple-audio-playlist" data-playlist>';

    foreach ($items as $item) {
        $item = trim($item);
        $parts = explode('|', $item);
        $srcPart = trim($parts[0]);
        $customTitle = isset($parts[1]) ? trim($parts[1]) : '';

        if (is_numeric($srcPart)) {
            $url = wp_get_attachment_url($srcPart);
            $title = $customTitle ?: get_the_title($srcPart);
        } else {
            $url = esc_url_raw($srcPart);
            $basename = basename(parse_url($url, PHP_URL_PATH));
            $title = $customTitle ?: preg_replace('/\\.[^.]+$/', '', $basename);
        }

        if ($url) {
            $output .= '<div class="sap-track" data-src="' . esc_url($url) . '">';
            $output .= '<p>' . esc_html($title) . '</p>';
            $output .= '</div>';
        }
    }

    $output .= '<audio id="sap-player" controls></audio>';
    $output .= '</div>';

    return $output;
}

add_action('wp_footer', function () {
    ?>
    <script>
    document.addEventListener("DOMContentLoaded", function () {
        const wrapper = document.querySelector('[data-sap-playlist]');
        if (!wrapper) return;

        const items = wrapper.querySelectorAll(".sap-list li");
        const player = wrapper.querySelector("#sap-player");
        let current = 0;
        let userInteracted = false;
        const keyIndex = "sap_last_index_" + location.pathname;
        const keyTime = "sap_last_time_" + location.pathname;

        function play(index) {
            const li = items[index];
            if (!li) return;
            player.src = li.dataset.src;
            current = index;
            localStorage.setItem(keyIndex, current);
            player.currentTime = 0;
            if (userInteracted) {
                player.play().catch(e => console.warn("Autoplay bị chặn:", e));
            }
        }

        items.forEach((li, index) => {
            li.addEventListener("click", () => {
                userInteracted = true;
                play(index);
            });
        });

        player.addEventListener("timeupdate", () => {
            localStorage.setItem(keyTime, player.currentTime);
        });

        player.addEventListener("ended", () => {
            current++;
            if (current < items.length) play(current);
        });

        // Khôi phục lại bài và thời điểm
        const savedIndex = parseInt(localStorage.getItem(keyIndex));
        const savedTime = parseFloat(localStorage.getItem(keyTime));

        if (!isNaN(savedIndex) && items[savedIndex]) {
            current = savedIndex;
            player.src = items[current].dataset.src;

            player.addEventListener("loadedmetadata", () => {
                if (!isNaN(savedTime)) {
                    player.currentTime = savedTime;
                }
            });
        }
    });

    </script>
    <?php
});
