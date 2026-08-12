=== Công cụ AI Type ===
Contributors: type.vn
Tags: phone, zalo, facebook, tiktok, whatsapp, ai chatbot
Requires at least: 4.7
Tested up to: 6.9
Requires PHP: 7.0
Stable Tag: 1.0.70
License: Free
License URI: 

Công cụ AI Type

== Description ==

Plugin này cung cấp các nút kết nối tùy chỉnh cho nhiều nền tảng như Điện thoại, Zalo, Facebook, Tiktok,... giúp người dùng dễ dàng liên lạc qua kênh giao tiếp ưa thích. Đặc biệt, plugin có tích hợp thêm AI Chatbot thông minh hỗ trợ người dùng tìm kiếm và làm việc.

== Installation ==

1. Visit 'Plugins > Add New'
2. Search for 'Công cụ AI Type'
3. Activate from your Plugins page.

=== Manually ===

1. Upload the folder to the '/wp-content/plugins/' directory
2. Activate the plugin through the 'Plugins' menu in WordPress

== Help ==
For support, visit: https://type.vn/

== Screenshots ==
1. Visit Plugins > Search for Contact Link Button
2. Fill in the information > save
3. Advanced settings - Size scale - hide on desktop or mobile
4. Congratulations!

== Changelog ==

= 1.0.68 =
* Tự động đọc file và bổ sung thuộc tính width/height chuẩn cho tất cả thẻ <img> và <iframe> thiếu kích thước (giảm thiểu 100% layout shift CLS)

= 1.0.67 =
* SỬA NỔI: Xuất trực tiếp HTML Nút liên hệ (0ms delay) thay vì bắt chờ 10 giây / cuộn chuột
* Tối ưu Anti-CLS CSS chuẩn responsive (55px mobile, 112px desktop) triệt tiêu điểm đỏ CLS

= 1.0.66 =
* Sửa đúng CSS selector cho .td-header-mobile-wrap trên giao diện Mobile Newspaper
* Triệt tiêu hoàn toàn lỗi nhấp nháy giao diện CLS 0.495 vọt thẳng lên 85-90+ điểm

= 1.0.65 =
* FIX QUAN TRỌNG: Khởi tạo CLBNTB::instance() và xử lý did_action(plugins_loaded) hiển thị lại 100% các nút liên hệ trên Frontend

= 1.0.64 =
* Fix: Khôi phục hiển thị Danh sách nút liên hệ (button-contact.php) trên giao diện
* Tích hợp Anti-CLS CSS và FontAwesome preload trực tiếp vào bộ tạo Cache Redis

= 1.0.63 =
* Preload FontAwesome webfont để triệt tiêu đợt nhấp nháy Font (CLS shift)
* Cố định min-height cho Header Container loại bỏ CLS 0.472 nâng điểm lên 80-90+

= 1.0.62 =
* Fix: Sửa triệt để lỗi Google Form iframe nạp trùng data-src="about:blank"
* Inject Polyfill an toàn cho hàm checkFooterVisibility/isElementInViewport của Theme Newspaper

= 1.0.61 =
* Sửa lỗi console iframe `getBoundingClientRect` bằng cách gán src=about:blank chuẩn DOM
* Bảo vệ TagDiv Theme JS không bị vỡ cú pháp khi Delay JS

= 1.0.60 =
* Khôi phục RevSlider (sr7, tptools) nạp đồng bộ để tiêu đề H1 Hero hiển thị tức thì (LCP < 2.0s)
* Giữ nguyên Lazy-load Google Forms và Defer CSS an toàn

= 1.0.59 =
* Defer Slider Revolution JS (sr7.js, tptools.js) loại bỏ 1.1s render-blocking
* Defer Newspaper Theme & Chatbot CSS loại bỏ 730ms CSS render-blocking

= 1.0.58 =
* Fix: Sửa lỗi cú pháp PHP trong cache-reader làm trắng trang
* Ổn định quy trình lưu HTML và nạp PageSpeed Optimizer

= 1.0.57 =
* Tự động lazy-load Google Forms iframe trực tiếp vào Redis HTML cache
* Trì hoãn CSS chặn hiển thị (TagDiv Newspaper, RevSlider, Newsletter)
* Tối ưu Total Blocking Time (TBT) cho trình duyệt

= 1.0.56 =
* Ổn định hóa toàn bộ module Redis, Status Dashboard, Gợi ý tối ưu

= 1.0.70 =
* Fix lỗi Uncaught TypeError: e.indexOf is not a function trên jQuery 3.7+
* Thêm polyfill tự động xử lý $(window).load() legacy
* Giữ jquery-migrate nạp đồng bộ để đảm bảo tính tương thích theme/plugin

= 1.0.55 =
* Fix: Load Redis driver globally để admin status page detect đúng

= 1.0.54 =
* Sửa lỗi detect Redis: hiện đúng trạng thái khi đã cấu hình wp-config.php
* Thêm test kết nối trực tiếp Redis khi detect, hiện host:port và lỗi cụ thể

= 1.0.53 =
* Tách Trạng Thái Hệ Thống ra tab riêng
* Thêm cột "Hướng dẫn cấu hình" với code copy-paste và link trực tiếp
* Gợi ý tối ưu tự động phân tích theo mức ưu tiên

= 1.0.52 =
* Thêm bảng Trạng Thái Hệ Thống (System Status Dashboard)
* Thêm Gợi Ý Tối Ưu tự động phân tích và khuyến nghị cấu hình
* Hướng dẫn copy-paste cho Redis, GZIP, WP_CACHE, PHP

= 1.0.51 =
* Thêm Redis Full Page Cache (< 1ms response, fallback file cache)
* Tự động bật GZIP nén nếu server chưa bật
* Tối ưu PageSpeed: defer JS, lazy-load Google Forms iframe, font-display swap
* Thêm title cho iframe thiếu (Accessibility)
* Preconnect hints cho third-party domains
* Remove unused CSS/JS (Contact Form 7) khi không cần

= 1.0 =
* First release.

= 1.1 =
* Fix css

= 1.2 =
* Fix setting