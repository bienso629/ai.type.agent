<!-- IMPORT partials/breadcrumbs-json-ld.tpl -->
{{{ if config.theme.enableBreadcrumbs }}}
<!-- IMPORT partials/breadcrumbs.tpl -->
{{{ end }}}

{{{ if widgets.header.length }}}
<div data-widget-area="header">
	{{{each widgets.header}}}
	{{widgets.header.html}}
	{{{end}}}
</div>
{{{ end }}}

<div class="row flex-fill mt-3">
	<div class="world {{{if widgets.sidebar.length }}}col-lg-9 col-sm-12{{{ else }}}col-lg-12{{{ end }}}">
		<div class="category">
			<div class="row flex-row-reverse">
				<div class="col-lg-4 col-sm-12 mt-2 pt-1 {{{ if !config.loggedIn }}}invisible{{{ end }}}">
					<ul class="categories-list ps-0 list-unstyled d-none d-md-block">
						{{{ each categories }}}
						<!-- IMPORT partials/account/category-item.tpl -->
						{{{ end }}}
					</ul>
				</div>

				<div class="col-lg-8 col-sm-12">
					<!-- IMPORT partials/topic-list-bar.tpl -->
					<!-- IMPORT partials/topic/quickreply.tpl -->

					{{{ if !config.loggedIn }}}
					<div class="alert alert-info alert-dismissible fade show">
						<p class="fw-semibold">
							[[world:onboard.title]]
						</p>
						<p>[[world:onboard.what]]</p>
						<p>[[world:onboard.why]]</p>
						<p>[[world:onboard.how]]</p>
						<a href="{config.relative_path}/register" class="fw-semibold btn btn-sm btn-warning">[[global:register]]</a>
						<a href="{config.relative_path}/login" class="fw-semibold btn btn-sm btn-info">[[global:login]]</a>
						<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
					</div>
					{{{ end }}}

					<ul class="list-unstyled" id="world-feed">
						{{{ each posts }}}
						<!-- IMPORT partials/feed/item.tpl -->
						{{{ end }}}
					</ul>

					{{{ if config.usePagination }}}
					<!-- IMPORT partials/paginator.tpl -->
					{{{ end }}}
				</div>
			</div>
		</div>
	</div>
	<div data-widget-area="sidebar" class="col-lg-3 col-sm-12 {{{ if !widgets.sidebar.length }}}hidden{{{ end }}}">
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
