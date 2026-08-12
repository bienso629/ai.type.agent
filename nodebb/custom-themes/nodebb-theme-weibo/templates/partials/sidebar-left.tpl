<nav component="sidebar/left" class="{{{ if config.theme.openSidebars}}}open{{{ end }}} bg-body sidebar sidebar-left start-0 vh-100 d-none d-lg-flex flex-column justify-content-between sticky-top">
	<!-- IMPORT partials/header/brand.tpl -->
	<ul id="main-nav" class="list-unstyled d-flex flex-column w-100 gap-2 mt-2 overflow-y-auto">
		{{{ each navigation }}}
		{{{ if displayMenuItem(@root, @index) }}}
		<li class="nav-item mx-2 {./class}{{{ if ./dropdown }}} dropend{{{ end }}}" title="{./title}">
			<a class="nav-link navigation-link d-flex gap-2 justify-content-between align-items-center {{{ if ./dropdown }}}dropdown-toggle{{{ end }}}" {{{ if ./dropdown }}} href="#" role="button" data-bs-toggle="dropdown" aria-haspopup="true" aria-expanded="false" {{{ else }}} href="{./route}"{{{ end }}} {{{ if ./id }}}id="{./id}"{{{ end }}}{{{ if ./targetBlank }}} target="_blank"{{{ end }}} {{{ if ./text }}}aria-label="{./text}"{{{ end }}}>
				<span class="d-flex gap-2 align-items-center text-nowrap truncate-open">
					<span class="position-relative">
						{{{ if ./iconClass }}}
						<i class="fa fa-fw {./iconClass}" data-content="{./content}"></i>
						<span component="navigation/count" class="visible-closed position-absolute top-0 start-100 translate-middle badge rounded-1 bg-primary {{{ if !./content }}}hidden{{{ end }}}">{./content}</span>
						{{{ end }}}
					</span>
					{{{ if ./text }}}<span class="nav-text small visible-open fw-semibold text-truncate">{./text}</span>{{{ end }}}
				</span>
				<span component="navigation/count" class="visible-open badge rounded-1 bg-primary {{{ if !./content }}}hidden{{{ end }}}">{./content}</span>
			</a>
			{{{ if ./dropdown }}}
			<ul class="dropdown-menu p-1 shadow" role="menu">
				{./dropdownContent}
			</ul>
			{{{ end }}}
		</li>
		{{{ end }}}
		{{{ end }}}
	</ul>
	<div class="sidebar-toggle-container align-self-start">
		{{{ if !config.disableCustomUserSkins }}}
		<!-- IMPORT partials/skin-switcher.tpl -->
		{{{ end }}}


	</div>
</nav>
