<ul component="category" class="topic-list list-unstyled" itemscope itemtype="http://www.schema.org/ItemList" data-nextstart="{nextStart}" data-set="{set}">
	{{{ each topics }}}
	<li component="category/topic" class="card py-3 my-3 weibo-post" style="background-color: transparent !important; border: none !important; box-shadow: none !important;" data-tid="{./tid}" data-index="{./index}" data-cid="{./cid}">
		<link itemprop="url" content="{config.relative_path}/topic/{./slug}" />
		<div class="card-body" style="background-color: transparent !important;">
            <div class="d-flex mb-2 align-items-center">
                <a href="{config.relative_path}/user/{./user.userslug}" class="text-decoration-none me-3">
                    {{buildAvatar(./user, "48px", true)}}
                </a>
                <div>
                    <h5 class="m-0"><a href="{config.relative_path}/user/{./user.userslug}" class="text-reset text-decoration-none">{./user.displayname}</a></h5>
                    <small class="text-muted"><a href="{config.relative_path}/topic/{./slug}" class="text-reset text-decoration-none timeago" title="{./timestampISO}"></a></small>
                </div>
            </div>
            
            {{{ if ./thumb }}}
            <div class="mb-3 weibo-post-thumbnail">
                <a href="{config.relative_path}/topic/{./slug}">
                    <img src="{./thumb}" class="img-fluid rounded w-100" alt="{./title}" />
                </a>
            </div>
            {{{ else }}}
                {{{ if ./thumbs.length }}}
                <div class="mb-3 weibo-post-thumbnail">
                    <a href="{config.relative_path}/topic/{./slug}">
                        <img src="{./thumbs.0.url}" class="img-fluid rounded w-100" alt="{./title}" />
                    </a>
                </div>
                {{{ end }}}
            {{{ end }}}
            
            <div class="post-content mb-3" style="font-size: 1.1rem; line-height: 1.5; color: var(--bs-body-color);">
                <!-- Fallback to title if no content available -->
                {{{ if ./weiboContent }}}
                    {{./weiboContent}}
                {{{ else }}}
                    {./title}
                {{{ end }}}
            </div>

            <div class="post-actions d-flex gap-4 text-muted pt-3 mt-2">
                <span class="d-flex align-items-center gap-2">
                    <span class="cursor-pointer weibo-reply-action" data-tid="{./tid}" data-title="{./title}" title="Bình luận nhanh">
                        <i class="fa fa-reply"></i>
                    </span>
                    <a href="{config.relative_path}/topic/{./slug}" class="text-reset text-decoration-none" title="Xem bài viết">
                        <span class="reply-count">{humanReadableNumber(./postcount, 0)}</span> Phản hồi
                    </a>
                </span>
                <span class="cursor-pointer weibo-like-action {{{ if ./upvoted }}}upvoted text-danger{{{ end }}}" data-pid="{./mainPid}">
                    <i class="fa fa-heart"></i> <span class="vote-count">{humanReadableNumber(./votes, 0)}</span> Yêu thích
                </span>
                <span class="cursor-pointer">
                    <i class="fa fa-eye"></i> <span class="view-count">{humanReadableNumber(./viewcount, 0)}</span> Đã xem
                </span>
            </div>
		</div>
	</li>
	{{{end}}}
</ul>
