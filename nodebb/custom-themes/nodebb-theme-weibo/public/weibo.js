$(window).on('action:ajaxify.end', function (event, data) {
    // 1. Phục hồi Highlight cho các Tab (vì Header không được render lại khi điều hướng AJAX)
    var relative_path = window.config ? window.config.relative_path : '';
    $('.weibo-top-tabs a').removeClass('text-body border-bottom border-primary border-3').addClass('text-muted');
    
    // Nếu vào trang friends
    if (data.url === 'friends') {
        $('.weibo-top-tabs a[href="' + relative_path + '/friends"]').removeClass('text-muted').addClass('text-body border-bottom border-primary border-3');
    } else if (data.url === 'recent' || data.url === '') {
        // Nếu ở trang chủ Thế giới
        $('.weibo-top-tabs a[href="' + relative_path + '/"]').removeClass('text-muted').addClass('text-body border-bottom border-primary border-3');
    }

    if (data.tpl_url === 'recent' || data.url === '') {
        require(['api', 'alerts', 'bootbox', 'uploader'], function (api, alerts, bootbox, uploader) {
            var txt = $('#weibo-quick-post-content');
            var $categoryDropdown = $('.weibo-category-selector-wrapper [component="category-selector"]');
            var customSelectedCid = ajaxify.data.cid || 1;

            if ($categoryDropdown.length) {
                require(['categorySelector'], function (categorySelector) {
                    categorySelector.init($categoryDropdown, {
                        onSelect: function (category) {
                            customSelectedCid = category.cid;
                        }
                    });

                    // Nếu đang ở /category/:cid thì tự auto chọn cid đó
                    if (ajaxify.data.cid) {
                        categorySelector.selectCategory(ajaxify.data.cid, $categoryDropdown);
                    }
                });
            }

            // Handle action buttons
            $('.weibo-action-btn').off('click').on('click', function (e) {
                e.preventDefault();
                var action = $(this).data('action');

                if (action === 'image') {
                    // Tạo một hidden input file đa lựa chọn (multiple)
                    var $input = $('<input type="file" multiple accept="image/*,video/*,audio/*" style="display:none;" />');
                    $('body').append($input); // Gắn tạm vào DOM để chạy cho chuẩn

                    var $btn = $(this); // Lưu lại nút

                    $input.on('change', function (e) {
                        var files = e.target.files;
                        if (!files || !files.length) {
                            $input.remove();
                            return;
                        }

                        // Sử dụng FormData để gửi nhiều file đến API tải lên của NodeBB 
                        var formData = new FormData();
                        for (var i = 0; i < files.length; i++) {
                            formData.append('files[]', files[i]);
                        }

                        // Khóa phím Upload hiển thị đang quay
                        var originalHtml = $btn.html();
                        $btn.html('<i class="fa fa-spinner fa-spin"></i>').prop('disabled', true);

                        $.ajax({
                            url: config.relative_path + '/api/post/upload',
                            method: 'POST',
                            data: formData,
                            processData: false,
                            contentType: false,
                            headers: {
                                'x-csrf-token': config.csrf_token
                            },
                            success: function (res) {
                                var uploaded = [];
                                var data = res.responseJSON || res;
                                if (data && data.response) {
                                    if (data.response.images) uploaded = uploaded.concat(data.response.images);
                                    if (data.response.files) uploaded = uploaded.concat(data.response.files);
                                } else {
                                    uploaded = Array.isArray(data) ? data : [data];
                                }

                                var injectedText = '';
                                uploaded.forEach(function (u) {
                                    if (!u) return;
                                    var url = u.url ? u.url : (typeof u === 'string' ? u : (u.path || ''));
                                    if (url) {
                                        injectedText += '\n![](' + url + ')\n';
                                    }
                                });
                                txt.val(txt.val() + injectedText);
                                txt.focus();

                                $btn.html(originalHtml).prop('disabled', false);
                                $input.remove(); // Dọn dẹp DOM
                            },
                            error: function (err) {
                                require(['alerts'], function (alerts) {
                                    alerts.error(err.responseJSON ? err.responseJSON.error : 'Có lỗi khi tải lên');
                                });
                                $btn.html(originalHtml).prop('disabled', false);
                                $input.remove();
                            }
                        });
                    });

                    // Kích hoạt bật bảng chọn file của OS
                    $input.click();
                }
            });

            $('#weibo-quick-post-form').off('submit').on('submit', function (e) {
                e.preventDefault();
                var content = txt.val();
                var btn = $('#weibo-quick-post-btn');
                if (!content) return;

                btn.prop('disabled', true);

                // Lấy cid từ component Category Selector
                var cid = $categoryDropdown.attr('data-cid') || customSelectedCid;

                // Lọc bỏ markdown link hình / audio / thẻ a để có title bằng chữ tự nhiên
                var plainText = content
                    .replace(/!\[.*?\]\([^)]+\)/g, '')   // Xóa image markdown
                    .replace(/\[.*?\]\([^)]+\)/g, '')    // Xóa link / audio markdown
                    .replace(/\[.*?\]\(<[^>]+>\)/g, '')  // Xóa link / audio syntax <url>
                    .replace(/https?:\/\/[^\s]+/g, '')   // Xóa raw url
                    .trim();

                // Sinh tự động title, độ dài 40 kí tự
                var title = plainText.substring(0, 40);
                if (plainText.length > 40) {
                    title += '...';
                }

                // Nếu nội dung toàn ảnh (plainText rỗng), dùng fallback
                if (!title) {
                    title = 'Chia sẻ trạng thái mới';
                }

                api.post('/topics', {
                    cid: cid,
                    title: title,
                    content: content
                }).then(function (result) {
                    btn.prop('disabled', false);
                    txt.val('');
                    alerts.success('Tạo trạng thái thành công!');
                    // Load lại view hiện tại
                    ajaxify.refresh();
                }).catch(function (err) {
                    btn.prop('disabled', false);
                    alerts.error(err);
                });
            });
        });
    }
});

// Xử lý các sự kiện tải trang, tải thêm post trong chủ đề, và tải thêm topic (Load More / Infinite Scroll)
$(window).on('action:ajaxify.end action:posts.loaded action:topics.loaded', function () {

    // 0. Xử lý nút Reply trực tiếp trên Feed
    $('[component="category"]').off('click', '.weibo-reply-action').on('click', '.weibo-reply-action', function (e) {
        e.preventDefault();
        var tid = $(this).data('tid');
        var title = $(this).data('title') || 'Trả lời bài viết';
        require(['composer'], function (composer) {
            // composer.newReply(tid, pid, title, text)
            composer.newReply(tid, undefined, title, '');
        });
    });

    // 0. Xử lý nút Like trực tiếp trên Feed
    $('[component="category"]').off('click', '.weibo-like-action').on('click', '.weibo-like-action', function (e) {
        e.preventDefault();
        var $btn = $(this);
        var pid = $btn.data('pid');
        if (!pid) return; // Không có mainPid

        var isUpvoted = $btn.hasClass('upvoted');

        require(['api', 'alerts'], function (api, alerts) {
            if (isUpvoted) {
                api.del('/posts/' + pid + '/vote').then(function () {
                    $btn.removeClass('upvoted text-danger');
                    var $cnt = $btn.find('.vote-count');
                    $cnt.text(parseInt($cnt.text() || 0, 10) - 1);
                }).catch(function (err) { alerts.error(err); });
            } else {
                api.put('/posts/' + pid + '/vote', { delta: 1 }).then(function () {
                    $btn.addClass('upvoted text-danger');
                    var $cnt = $btn.find('.vote-count');
                    $cnt.text(parseInt($cnt.text() || 0, 10) + 1);
                }).catch(function (err) { alerts.error(err); });
            }
        });
    });

    // 1. Xử lý ảnh dạng Grid Album (Weibo-style)
    // Phần CSS Grid đã được di chuyển hoàn toàn sang weibo.scss để đồng bộ Giao diện Sáng/Tối

    $('.weibo-post .post-content, [component="post/content"]').each(function () {
        var $content = $(this);
        if ($content.data('grid-initialized')) return;
        $content.data('grid-initialized', true);

        var children = $content.contents();
        var currentGroup = [];
        var groupsToBuild = [];

        function flushGroup() {
            if (currentGroup.length > 0) {
                var $firstImg = currentGroup[0];
                var $target = $firstImg.parent('p');
                if (!$target.length) {
                    $target = $firstImg;
                }
                groupsToBuild.push({
                    images: currentGroup,
                    target: $target
                });
                currentGroup = [];
            }
        }

        children.each(function () {
            var $el = $(this);
            if (this.nodeType === 3) { // Text node
                if (this.textContent.trim() !== '') {
                    flushGroup();
                }
                return;
            }

            if (this.nodeType === 1) { // Element node
                var $imgs = $el.find('img:not(.emoji, .avatar, [alt="😎"])');
                if ($el.is('img:not(.emoji, .avatar, [alt="😎"])')) {
                    $imgs = $el;
                }

                if ($imgs.length > 0) {
                    var clone = $el.clone();
                    clone.find('img, script, style').remove();
                    var hasText = clone.text().trim() !== '';

                    if (!hasText) {
                        $imgs.each(function () {
                            currentGroup.push($(this));
                        });
                    } else {
                        flushGroup();
                    }
                } else {
                    flushGroup();
                }
            }
        });
        flushGroup();

        if (groupsToBuild.length === 0) return;

        // Lấy link topic để chuyển trang khi nhấp vào hình
        var topicUrl = $content.closest('li[component="category/topic"]').find('a[href*="/topic/"]').attr('href') || '#';

        groupsToBuild.forEach(function (group) {
            var $images = $(group.images.map(function ($img) { return $img[0]; }));
            var num = $images.length;
            var $target = group.target;

            var $grid = $('<div class="weibo-img-grid"></div>');
            $grid.addClass(num === 1 ? 'grid-1' : (num === 2 ? 'grid-2' : 'grid-3'));

            // Chèn grid vào trước phần tử mục tiêu
            $grid.insertBefore($target);

            // Bóc tách hình khỏi cấu trúc thẻ <p> mặc định
            $images.each(function () {
                var $img = $(this);
                var $p = $img.parent('p');
                $img.detach();
                if ($p.length && $p.html().trim() === '') {
                    $p.remove();
                }
            });

            // Append hình ảnh vào grid
            var limit = Math.min(3, num);
            $images.each(function (i) {
                if (i >= limit) return;
                var $img = $(this);
                var $wrap = $('<a href="' + topicUrl + '" class="grid-img-wrap text-decoration-none fb-skeleton-loading"></a>');
                $wrap.append($img);

                // Bắt sự kiện load xong ảnh để xóa class skeleton
                $img.on('load', function() {
                    $wrap.removeClass('fb-skeleton-loading');
                }).each(function() {
                    if(this.complete) $img.trigger('load');
                });

                if (i === 2 && num > 3) {
                    var leftover = num - limit;
                    $wrap.append('<div class="more-images-overlay">+' + leftover + '</div>');
                }
                $grid.append($wrap);
            });
        });
    });

    // 2. Lọc các bài post dài để thêm nút "See more" một cách thông minh (bất chấp ảnh load chậm)
    $('.weibo-post .post-content').each(function () {
        var $content = $(this);
        if ($content.data('seemore-initialized')) return;
        $content.data('seemore-initialized', true);

        // Chèn sẵn nút Mở rộng và sương mờ vào bên TRONG nội dung (dùng absolute để không làm giật / đẩy giao diện)
        var $fade = $('<div class="see-more-fade" style="position: absolute; bottom: 0; left: 0; right: 0; height: 120px; background: linear-gradient(to bottom, transparent, var(--bs-body-bg)); pointer-events: none; opacity: 0; transition: opacity 0.3s ease; z-index: 1;"></div>');
        var $btnContainer = $('<div class="text-center see-more-btn-container" style="position: absolute; bottom: 15px; left: 0; right: 0; opacity: 0; transition: opacity 0.3s ease; z-index: 2;"></div>');
        var $btn = $('<button class="btn btn-sm px-4" style="color: var(--bs-body-color); font-weight: 600; background: var(--bs-dark); border: 0px solid var(--bs-border-color); border-radius: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3);">Mở rộng</button>');

        $btnContainer.append($btn);
        $content.append($fade);
        $content.append($btnContainer);

        // Hàm kiểm tra động: Nội dung có đang bị cắt bởi max-height của CSS hay không?
        var checkHeight = function() {
            if ($content.hasClass('see-more-expanded') || $content.hasClass('see-more-released')) return;
            
            // Dùng sai số 15px để tránh những chênh lệch làm tròn pixel
            if ($content[0].scrollHeight > $content[0].clientHeight + 15) {
                $fade.css('opacity', '1');
                $btnContainer.css('opacity', '1');
            } else {
                $fade.css('opacity', '0');
                $btnContainer.css('opacity', '0');
            }
        };

        // Kích hoạt theo dõi kích thước để phát hiện ngay khi hình ảnh vừa load xong
        var observer;
        if (window.ResizeObserver) {
            observer = new ResizeObserver(checkHeight);
            observer.observe($content[0]);
        } else {
            // Fallback cho trình duyệt siêu cũ
            setTimeout(checkHeight, 300);
            setTimeout(checkHeight, 1500);
        }

        $btn.on('click', function () {
            $content.addClass('see-more-expanded');
            $fade.css('opacity', '0');
            $btnContainer.css('opacity', '0');
            
            if (observer) observer.disconnect();

            // Xóa hẳn class sau khoảng time chạy transition để bung lụa tự nhiên
            setTimeout(function () { 
                $content.removeClass('see-more-expanded').addClass('see-more-released');
                $fade.remove();
                $btnContainer.remove(); 
            }, 350);
        });
    });

    // 3. Tự động nhận diện Video Dọc (Facebook Reels, TikTok, YouTube Shorts)
    $('.weibo-post .post-content iframe, [component="post/content"] iframe').each(function () {
        var $iframe = $(this);
        var src = $iframe.attr('src') || '';
        var isVertical = false;

        // Bắt link Facebook Reels (đã decode URL hoặc chưa)
        if (src.indexOf('facebook.com') !== -1 && (src.indexOf('%2Freel%2F') !== -1 || src.indexOf('/reel/') !== -1 || src.indexOf('%2Freal%2F') !== -1 || src.indexOf('/real/') !== -1 || src.indexOf('%2Fshare%2Fr%2F') !== -1 || src.indexOf('/share/r/') !== -1)) {
            isVertical = true;
        }
        // Bắt link TiKTok
        else if (src.indexOf('tiktok.com') !== -1) {
            isVertical = true;
        }
        // Bắt Youtube Shorts
        else if (src.indexOf('youtube.com') !== -1 && (src.indexOf('%2Fshorts%2F') !== -1 || src.indexOf('/shorts/') !== -1)) {
            isVertical = true;
        }

        // Với Facebook embeds đã được phân loại ở Backend (weibo-fb-embed)
        var $fbWrapper = $iframe.closest('.weibo-fb-embed');
        if ($fbWrapper.length) {
            // Thêm hiệu ứng loading skeleton
            $fbWrapper.addClass('fb-skeleton-loading');
            $iframe.on('load', function() {
                $fbWrapper.removeClass('fb-skeleton-loading');
            });
            return; // Không can thiệp chiều cao/tỷ lệ bằng JS nữa, đã được CSS xử lý chuẩn xác
        }

        if (isVertical) {
            // Thường NodeBB hoặc plugin đặt iframe trong một div container để tạo tỷ lệ 16:9
            var $wrapper = $iframe.closest('.ratio, .iframe-container, .video-container');

            if ($wrapper.length) {
                // Xóa tỷ lệ 16:9 mặc định
                $wrapper.removeClass('ratio-16x9');
                // Ghi đè CSS ép thành khung dọc 9:16
                $wrapper.css({
                    'padding-bottom': '177.77%', // Tỷ lệ vàng của 9:16 (16 / 9 = 1.7777...)
                    'height': '0'
                });
                $wrapper.css('aspect-ratio', '9/16'); // Chuẩn hiện đại
                
                // Thêm skeleton loading
                $wrapper.addClass('fb-skeleton-loading');
                $iframe.on('load', function() {
                    $wrapper.removeClass('fb-skeleton-loading');
                });
            } else {
                // Nếu không có wrapper thì set thẳng vào iframe
                $iframe.css({
                    'aspect-ratio': '9/16',
                    'height': '600px', // Đặt 1 độ cao cố định an toàn
                    'width': '100%'
                });
                
                // Thêm skeleton loading
                $iframe.addClass('fb-skeleton-loading');
                $iframe.on('load', function() {
                    $iframe.removeClass('fb-skeleton-loading');
                });
            }
        }
    });

    // 4. Chỉ xử lý âm thanh nếu trên trang có khung audio chưa được khởi tạo
    if ($('.weibo-waveform:not(.initialized)').length === 0) return;

    var initWaves = function () {
        $('.weibo-waveform:not(.initialized)').each(function () {
            var $el = $(this);
            $el.addClass('initialized'); // Đánh dấu đã khởi tạo

            // Lấy link mp3 từ thẻ a ẩn
            var audioUrl = $el.find('.weibo-audio-url').attr('href') || $el.data('audio');

            // Tạo khung HTML: Đã bỏ nút Play, chỉ giữ lại container sóng âm.
            // Thêm cursor: pointer để hiện bàn tay khi trỏ chuột vào, báo hiệu có thể click.
            $el.html('<div class="wave-container rounded" style="cursor: pointer;" title="Nhấn để Phát / Tạm dừng"></div>');

            var $wave = $el.find('.wave-container');

            // Vẽ sóng âm
            var wavesurfer = window.WaveSurfer.create({
                container: $wave[0],
                waveColor: 'rgba(255, 255, 255, 0.25)', // Màu xám mờ/trong suốt khi chưa chạy
                progressColor: '#00d2ff',               // Màu xanh Cyan rực rỡ khi chạy qua (sáng màu lên)
                cursorColor: '#ffffff',                 // Vạch kẻ trắng sáng
                barWidth: 2,
                barRadius: 3,
                cursorWidth: 2,
                height: 80,             // Tăng chiều cao
                barGap: 3,
                hideScrollbar: true,    // Ẩn thanh cuộn ngang
                responsive: true        // Tự động co giãn vừa vặn với khung
            });

            wavesurfer.load(audioUrl);

            // Xử lý lỗi đen ngòm (width=0) do DOM của NodeBB render chưa xong (đang ẩn)
            wavesurfer.on('ready', function () {
                var attempts = 0;
                var checkWidth = setInterval(function () {
                    attempts++;
                    // Nếu thẻ div chứa sóng âm đã có chiều rộng thực tế (>0)
                    if ($wave.width() > 0) {
                        clearInterval(checkWidth);
                        // Ép WaveSurfer vẽ lại sóng
                        window.dispatchEvent(new Event('resize'));
                    }
                    // Dừng kiểm tra sau khoảng 3 giây (30 x 100ms) để tránh treo trình duyệt
                    if (attempts > 30) {
                        clearInterval(checkWidth);
                    }
                }, 100);
            });

            // Gắn sự kiện click trực tiếp vào khung sóng âm để Phát/Tạm dừng
            $wave.on('click', function () {
                wavesurfer.playPause();
            });
        });
    };

    // Cơ chế tải thư viện thông minh (lách Webpack)
    if (window.WaveSurfer) {
        // Đã tải rồi thì vẽ luôn
        initWaves();
    } else if (!window._loadingWaveSurfer) {
        // Chưa tải thì bắt đầu tải bằng jQuery
        window._loadingWaveSurfer = true;
        $.getScript('https://unpkg.com/wavesurfer.js@6.3.0/dist/wavesurfer.js', function () {
            initWaves();
        });
    } else {
        // Nếu kịch bản đang được tải dở do lướt trang nhanh, chờ 1 chút rồi vẽ
        var checkExist = setInterval(function () {
            if (window.WaveSurfer) {
                clearInterval(checkExist);
                initWaves();
            }
        }, 100);
    }
});
