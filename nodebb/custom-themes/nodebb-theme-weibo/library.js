'use strict';

const plugin = {};
const NodeBB = require.main;
const posts = NodeBB.require('./src/posts');
const plugins = NodeBB.require('./src/plugins');
const harmony = require('../../node_modules/nodebb-theme-harmony/library');

const db = NodeBB.require('./src/database');
const privileges = NodeBB.require('./src/privileges');
const pagination = NodeBB.require('./src/pagination');
const meta = NodeBB.require('./src/meta');
const topics = NodeBB.require('./src/topics');

plugin.init = async function (params) {
    await harmony.init(params);

    const { router, middleware } = params;
    
    const renderFriendsFeed = async (req, res, next) => {
        if (!req.uid) return res.redirect('/login');

        const page = parseInt(req.query.page, 10) || 1;
        const itemsPerPage = meta.config.topicsPerPage || 20;
        const start = Math.max(0, (page - 1) * itemsPerPage);
        const stop = start + itemsPerPage - 1;

        // Lấy danh sách UID bạn bè (following)
        const followingUids = await db.getSortedSetRevRange('following:' + req.uid, 0, -1);
        
        let tids = [];

        if (followingUids && followingUids.length) {
            const sets = followingUids.map(u => 'uid:' + u + ':topics');
            
            tids = await db.getSortedSetRevUnion({
                sets: sets,
                start: start,
                stop: stop,
                aggregate: 'MAX'
            });
        }

        const allowedTids = await privileges.topics.filterTids('topics:read', tids, req.uid);
        let topicData = await topics.getTopicsByTids(allowedTids, req.uid);
        
        // Tạo biến phân trang
        const pageCount = tids.length === itemsPerPage ? page + 1 : page; 
        const paginationData = pagination.create(page, pageCount, req.query);

        const data = {
            title: 'Những người bạn',
            isFriendsFeed: true,
            template: { name: 'friends' },
            breadcrumbs: [{ text: 'Những người bạn' }],
            topics: topicData,
            nextStart: tids.length === itemsPerPage ? stop + 1 : 0,
            pagination: paginationData
        };

        res.render('recent', data);
    };

    router.get('/friends', middleware.buildHeader, renderFriendsFeed);
    router.get('/api/friends', renderFriendsFeed);
};

plugin.addAdminNavigation = harmony.addAdminNavigation;
plugin.defineWidgetAreas = harmony.defineWidgetAreas;
plugin.getThemeConfig = harmony.getThemeConfig;
plugin.getAdminSettings = harmony.getAdminSettings;
plugin.saveUserSettings = harmony.saveUserSettings;
plugin.addProfileItem = harmony.addProfileItem;
plugin.filterMiddlewareRenderHeader = harmony.filterMiddlewareRenderHeader;

// Pre-process: chuyển <audio> HTML tags thành markdown links TRƯỚC khi
// markdown-it parse (vì markdown-it html:false sẽ escape <audio> thành
// &lt;audio&gt; và linkify URL bên trong, phá hủy format hoàn toàn).
function normalizeAudioTags(content) {
    if (!content || typeof content !== 'string') return content;
    // Match <audio> tags with src attribute (any attribute order)
    return content.replace(/<audio[^>]*\bsrc="([^"]+)"[^>]*>.*?<\/audio>/ig, function (match, url) {
        // Use angle bracket syntax <url> so markdown-it handles spaces/special chars
        return '[🎵 Audio](<' + url + '>)';
    });
}

// Pre-process: encode các khoảng trắng trong link audio thô (chưa nằm trong tag) thành %20
// để markdown-it nhận dạng đúng URL có dấu cách (ví dụ thư viện Archive.org)
function encodeSpacedAudioUrls(content) {
    if (!content || typeof content !== 'string') return content;
    // Tìm các cụm URL kết thúc bằng .mp3/.wav... có thể chứa khoảng trắng
    // Regex lấy từ http(s) tới đuôi audio đầu tiên, bỏ qua dấu ngoặc vuông / kép
    return content.replace(/(https?:\/\/[^\n\]>"']*?\.(?:mp3|wav|m4a|ogg)(?:\?[^\s\]>"']*)?)/gi, function(match) {
        return match.replace(/ /g, '%20');
    });
}

// Post-process: chuyển <a> links audio/video thành embedded players
// (chạy SAU markdown-it đã parse markdown → HTML)
function embedVideos(content) {
    if (!content || typeof content !== 'string') return content;

    let youtubeCount = 0;

    // Đổi .*? thành [\s\S]*? để bắt được cả trường hợp thẻ <a> bị rớt dòng
    content = content.replace(/<a[^>]*href="([^"]+)"[^>]*>[\s\S]*?<\/a>/ig, function (match, url) {
        let ytMatch = url.match(/(?:youtube\.com\/(?:[^\/\n\s]+\/\S+\/|(?:v|e(?:mbed)?|shorts)\/|\S*?[?&]v=)|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
        if (ytMatch && ytMatch[1]) {
            if (youtubeCount === 0) {
                youtubeCount++;
                return '<div class="ratio ratio-16x9 my-2 weibo-yt-embed"><iframe src="https://www.youtube.com/embed/' + ytMatch[1] + '" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen style="width: 100%; aspect-ratio: 16/9; border-radius: 8px;"></iframe></div>';
            }
            return match;
        }

        // Facebook Video / Reel
        let fbMatch = url.match(/facebook\.com\/(?:reel|real|watch|.*\/videos|share\/[vr])\/?[\w-]*|fb\.watch\/[\w-]*/i);
        if (fbMatch) {
            if (youtubeCount === 0) {
                youtubeCount++;
                let encodedUrl = encodeURIComponent(url);
                let lowerUrl = url.toLowerCase();
                // Phân biệt chế độ hiển thị: Có từ "reel" hoặc "real" -> dọc (TikTok), còn lại / watch -> ngang
                let isReel = lowerUrl.includes('reel') || lowerUrl.includes('real') || lowerUrl.includes('/share/r/');
                let embedClass = isReel ? 'weibo-fb-embed fb-vertical' : 'weibo-fb-embed fb-horizontal';
                return '<div class="my-2 ' + embedClass + '"><iframe src="https://www.facebook.com/plugins/video.php?href=' + encodedUrl + '&show_text=false" style="border:none;overflow:hidden;width:100%;border-radius:8px;" scrolling="no" frameborder="0" allowfullscreen="true" allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share"></iframe></div>';
            }
            return match;
        }

        // Audio Wavesurfer (.mp3, .wav, .m4a, .ogg)
        let audioMatch = url.match(/\.(mp3|wav|m4a|ogg)(?:\?.*)?$/i);
        if (audioMatch) {
            let safeUrl = url.replace(/"/g, '&quot;');
            // Thêm một thẻ a ẩn (d-none) bên trong div để lưu link an toàn, đề phòng NodeBB Sanitizer xóa mất data-audio
            return '<div class="weibo-waveform my-3" data-audio="' + safeUrl + '"><a href="' + safeUrl + '" class="d-none weibo-audio-url"></a></div>';
        }

        return match;
    });

    return content;
}

// Priority 1: Chạy TRƯỚC markdown-it (priority 5)
// Chuyển <audio> HTML → markdown links để markdown-it xử lý đúng
plugin.preParsePost = async function (hookData) {
    if (hookData && hookData.postData && hookData.postData.content) {
        hookData.postData.content = encodeSpacedAudioUrls(hookData.postData.content);
        hookData.postData.content = normalizeAudioTags(hookData.postData.content);
    }
    return hookData;
};

plugin.preParseRaw = async function (hookData) {
    if (typeof hookData === 'string') {
        hookData = encodeSpacedAudioUrls(hookData);
        return normalizeAudioTags(hookData);
    } else if (hookData && hookData.hasOwnProperty('input')) {
        hookData.input = encodeSpacedAudioUrls(hookData.input);
        hookData.input = normalizeAudioTags(hookData.input);
    }
    return hookData;
};

// Priority 10 (default): Chạy SAU markdown-it (priority 5)
// Chuyển <a> links audio/video → embedded waveform/iframe
plugin.parsePost = async function (hookData) {
    if (hookData && hookData.postData && hookData.postData.content) {
        hookData.postData.content = embedVideos(hookData.postData.content);
    }
    return hookData;
};

plugin.parseRaw = async function (hookData) {
    if (typeof hookData === 'string') {
        return embedVideos(hookData);
    } else if (hookData && hookData.hasOwnProperty('input')) {
        hookData.input = embedVideos(hookData.input);
    }
    return hookData;
};

plugin.filterTopicsGet = async function (hookData) {
    if (!hookData || !hookData.topics || !hookData.topics.length) {
        return hookData;
    }

    const mainPids = hookData.topics.map(t => t.mainPid);
    const postData = await posts.getPostsFields(mainPids, ['content', 'uid', 'timestamp', 'deleted']);

    for (let i = 0; i < hookData.topics.length; i++) {
        if (postData[i] && postData[i].content) {
            // filter:parse.raw pipeline handles everything:
            // 1. preParseRaw (p1): <audio> → markdown links
            // 2. markdown-it (p5): markdown → HTML (<a> tags)
            // 3. parseRaw (p10): <a> audio links → waveform divs
            // 4. core sanitizer (p10): sanitize HTML
            const parsed = await plugins.hooks.fire('filter:parse.raw', postData[i].content);
            const htmlContent = typeof parsed === 'string' ? parsed : (parsed.html || parsed);
            hookData.topics[i].weiboContent = htmlContent;

            // Tự động trích xuất ảnh đầu tiên làm thumbnail nếu bài viết không có set thumbnail
            if (!hookData.topics[i].thumb && (!hookData.topics[i].thumbs || !hookData.topics[i].thumbs.length)) {
                const imgMatch = htmlContent.match(/<img[^>]+src="([^">]+)"/);
                if (imgMatch && imgMatch[1] && !imgMatch[1].includes('emoji') && !imgMatch[1].includes('avatar')) {
                    hookData.topics[i].thumb = imgMatch[1];
                }
            }
        }
    }

    return hookData;
};

module.exports = plugin;
