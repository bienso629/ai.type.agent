<nav component="sidebar/right" class="{{{ if config.theme.openSidebars}}}open{{{ end }}} bg-body sidebar sidebar-right end-0 vh-100 d-none d-lg-flex flex-column justify-content-center sticky-top">
	{{{ if config.loggedIn }}}
	<ul id="logged-in-menu" class="list-unstyled d-flex flex-column w-100 gap-2" role="menu">
	<!-- IMPORT partials/sidebar/logged-in-menu.tpl -->
	</ul>
	{{{ else }}}
	<ul id="logged-out-menu" class="list-unstyled d-flex flex-column w-100 gap-2" role="menu">
	<!-- IMPORT partials/sidebar/logged-out-menu.tpl -->
	</ul>
	{{{ end }}}

	<div class="visible-open small text-secondary" data-widget-area="sidebar-footer">
		{{{each widgets.sidebar-footer}}}
		{{./html}}
		{{{end}}}
	</div>
</nav>
