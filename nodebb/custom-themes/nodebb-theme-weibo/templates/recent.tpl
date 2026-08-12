{{{ if widgets.header.length }}}
<div data-widget-area="header">
	{{{each widgets.header}}}
	{{widgets.header.html}}
	{{{end}}}
</div>
{{{ end }}}

<div class="row flex-fill">
	<div class="recent col-lg-8 col-sm-12 mx-auto">
        <!-- Quick Post Box for Weibo -->
        {{{ if config.loggedIn }}}
        <div class="quick-reply d-flex gap-3 mb-4 weibo-composer">
            <div class="icon hidden-xs">
                <a class="d-inline-block position-relative" href="{config.relative_path}/user/{loggedInUser.userslug}">
                    {{buildAvatar(loggedInUser, "48px", true, "", "user/picture")}}
                </a>
            </div>
            <form id="weibo-quick-post-form" class="flex-grow-1 d-flex flex-column gap-2">
                <div class="quickreply-message position-relative">
                    <textarea id="weibo-quick-post-content" rows="4" class="form-control hover-border" style="resize:none;" placeholder="Enter your post content here, drag and drop images"></textarea>
                </div>
                <div>
                    <div class="d-flex justify-content-end gap-2 align-items-center">
                        <div class="me-auto rounded weibo-category-selector-wrapper">
                            <!-- IMPORT partials/category/selector-dropdown-left.tpl -->
                        </div>
                        <button type="button" class="btn btn-ghost btn-sm weibo-action-btn" data-action="image" title="Tải ảnh/video"><i class="fa fa-upload"></i></button>
                        <button type="submit" id="weibo-quick-post-btn" class="btn btn-sm btn-primary web-dark-bg">Quick post</button>
                    </div>
                </div>
            </form>
        </div>
        {{{ end }}}

		<div class="category">
			{{{ if !topics.length }}}
			<div class="alert alert-info" id="category-no-topics">[[recent:no-recent-topics]]</div>
			{{{ end }}}

			{{{ if (selectedCategory.cid == "-1") }}}
			<div class="py-3">
				<h4>[[recent:uncategorized.title]]</h4>
				<p>[[recent:uncategorized.intro]]</p>
			</div>
			{{{ end }}}

			<!-- IMPORT partials/topics_list.tpl -->

			{{{ if config.usePagination }}}
			<!-- IMPORT partials/paginator.tpl -->
			{{{ end }}}
		</div>
	</div>
	<div data-widget-area="sidebar" class="col-lg-4 col-sm-12 {{{ if !widgets.sidebar.length }}}hidden{{{ end }}}">
		{{{ each widgets.sidebar }}}
		{{widgets.sidebar.html}}
		{{{ end }}}
	</div>
</div>

<div data-widget-area="footer">
	{{{each widgets.footer}}}
	{{widgets.footer.html}}
	{{{end}}}
</div>
