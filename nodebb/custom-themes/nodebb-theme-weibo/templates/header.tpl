<!DOCTYPE html>
<html lang="{localeToHTML(userLang, defaultLang)}" {{{if languageDirection}}}data-dir="{languageDirection}" style="direction: {languageDirection};"{{{end}}}>
<head>
	<title>{browserTitle}</title>
	{{{each metaTags}}}{{buildMetaTag(@value)}}{{{end}}}
	<link rel="stylesheet" type="text/css" href="{relative_path}/assets/client{{{if bootswatchSkin}}}-{bootswatchSkin}{{{end}}}{{{ if (languageDirection=="rtl") }}}-rtl{{{ end }}}.css?{config.cache-buster}" />
	{{{each linkTags}}}{{buildLinkTag(@value)}}{{{end}}}

	<script>
		var config = JSON.parse('{{configJSON}}');
		var app = {
			user: JSON.parse('{{userJSON}}')
		};
		document.documentElement.style.setProperty('--panel-offset', `0px`);
	</script>

	{{{if useCustomHTML}}}
	{{customHTML}}
	{{{end}}}
	{{{if useCustomCSS}}}
	<style>{{customCSS}}</style>
	{{{end}}}
</head>

<body class="{bodyClass} skin-{{{if bootswatchSkin}}}{bootswatchSkin}{{{else}}}noskin{{{end}}}">
	<a class="visually-hidden-focusable position-absolute top-0 start-0 p-3 m-3 bg-body" style="z-index: 1021;" href="#content">[[global:skip-to-content]]</a>

	{{{ if config.theme.topMobilebar }}}
	<!-- IMPORT partials/mobile-header.tpl -->
	{{{ end }}}

	<div class="layout-container d-flex justify-content-between pb-4 pb-md-0">
		<!-- IMPORT partials/sidebar-left.tpl -->

		<main id="panel" class="d-flex flex-column gap-2 flex-grow-1" style="min-width: 0;">
			<div class="weibo-top-tabs px-3 px-md-4 py-3 d-flex justify-content-center gap-4 w-100">
				<a href="{config.relative_path}/" class="text-decoration-none fs-6 fw-bold {{{ if isFriendsFeed }}}text-muted pb-2{{{ else }}}{{{ if (template.name == "recent") }}}text-body border-bottom border-primary border-3 pb-2{{{ else }}}text-muted pb-2{{{ end }}}{{{ end }}}">Thế giới</a>
				
				{{{ if config.loggedIn }}}
				<a href="{config.relative_path}/friends" class="text-decoration-none fs-6 fw-bold {{{ if isFriendsFeed }}}text-body border-bottom border-primary border-3 pb-2{{{ else }}}text-muted pb-2{{{ end }}}">Những người bạn</a>
				{{{ end }}}
			</div>

			<div class="container-lg px-md-4 d-flex flex-column gap-3 h-100 mb-5 mb-lg-0 pt-2" id="content">
			<!-- IMPORT partials/noscript/warning.tpl -->
			<!-- IMPORT partials/noscript/message.tpl -->