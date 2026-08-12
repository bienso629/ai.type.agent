<ul component="category" class="topic-list list-unstyled" itemscope itemtype="http://www.schema.org/ItemList" data-nextstart="{nextStart}" data-set="{set}">
	{{{ each topics }}}
	<li component="category/topic" class="mb-3 category-item {function.generateTopicClass}" <!-- IMPORT partials/data/category.tpl -->>
		<div class="d-flex align-items-stretch position-relative">
			<div class="position-absolute top-0 start-0 translate-middle z-1">
				<i class="unread-dot fa-solid fa-circle fa-beat text-info" style="--fa-animation-duration: 2s;"></i>
			</div>

			<div class="card card-body h-100 rounded-1 border-0 ps-0" {{{ if showSelect }}}component="topic/select"{{{ end }}}>
				<link itemprop="url" content="{config.relative_path}/topic/{../slug}" />
				<meta itemprop="name" content="{function.stripTags, ../title}" />
				<meta itemprop="itemListOrder" content="descending" />
				<meta itemprop="position" content="{../index}" />
				<a id="{../index}" data-index="{../index}" component="topic/anchor"></a>

				<div class="d-flex">
					<!-- profile pic-->
					<div class="d-none d-lg-block px-3">
						<div class="d-grid">
							<a class="mb-2" href="{{{ if ./user.userslug }}}{config.relative_path}/user/{./user.userslug}{{{ else }}}#{{{ end }}}">
								{buildAvatar(./user, "64px", false, "rounded")}
							</a>

							<span class="badge text-muted fw-semibold "><i class="fa-regular fa-heart"></i> {./votes}</span>
							<span class="badge text-muted fw-semibold"><i class="fa-regular fa-message"></i> {./postcount}</span>
						</div>
					</div>

					<!-- mobile profile picture -->
					<div class="d-inline-block d-lg-none mx-2">
						<div class="d-grid">
							<a class="mb-2" href="{{{ if ./user.userslug }}}{config.relative_path}/user/{./user.userslug}{{{ else }}}#{{{ end }}}">
								{buildAvatar(./user, "24px", false, "rounded")}
							</a>

							<span class="badge text-muted fw-semibold "><i class="fa-regular fa-heart"></i> {./votes}</span>
							<span class="badge text-muted fw-semibold"><i class="fa-regular fa-message"></i> {./postcount}</span>
						</div>
					</div>

					<div class="text-wrap text-truncate flex-grow-1 d-flex align-items-top">
						<div class="w-100" component="post/header">
							<div class="d-flex flex-column w-100">
								<h5 component="topic/header" class="title">
									{{{ if !topics.noAnchor }}}
									<a href="{config.relative_path}/topic/{./slug}{{{ if topics.bookmark }}}/{./bookmark}{{{ end }}}">{./title}</a>
									{{{ else }}}
									<span>{./title}</span>
									{{{ end }}}
								</h5>

								<div class="justify-content-between align-items-between mt-1 mb-2">
									<div class="d-flex">
										{{{ if !template.category }}}
										{function.buildCategoryLabel, ./category, "a", "border"}
										{{{ end }}}

										<a href="{config.relative_path}/topic/{./slug}" class="d-flex align-items-center flex-wrap timeago badge text-muted fw-semibold" title="{./timestampISO}"></a>
									</div>
								</div>

								{{{ if ./thumbs.length }}}
								<div class="position-relative mb-0 mt-1">
									<div class="topic-thumbs rounded-1 position-relative text-decoration-none flex-shrink-0" aria-label="[[topic:thumb-image]]">
										<img class="topic-thumb bg-light" style="width:auto;max-width: 100%;height: auto;object-fit: contain;" src="{./thumbs.0.url}" alt=""/>
										<span data-numthumbs="{./thumbs.length}" class="px-1 mt-1 position-absolute top-0 start-50 translate-middle-x badge rounded text-bg-info">+{increment(./thumbs.length, "-1")}</span>
										{{{ if ./teaser.content.length }}}
										<div class="position-absolute bottom-0 start-0 text-wrap text-truncate h3 m-0 text-white bg-opacity-50 text-log w-100 px-3 bg-dark bg-opacity-50 lh-lg">{./teaser.content}</div>
										{{{ end }}}
									</div>
								</div>
								{{{ else }}}
								{{{ if ./teaser.content.length }}}
								<div class="teaser-content">{./teaser.content}</div>
								{{{ else }}}
								<div class="teaser-content">Bạn có suy nghĩ gì về bài viết này?</div>
								{{{ end }}}
								{{{ end }}}

								<div class="d-flex gap-1 align-items-start">
									<div component="topic/labels" class="d-flex gap-1 text-truncate align-items-center flex-wrap w-100">
										<span component="topic/scheduled" class="badge border border-gray-300 text-body mt-3 {{{ if !./scheduled }}}hidden{{{ end }}}">
											<i class="fa fa-clock-o"></i>
											<span>[[topic:scheduled]]</span>
										</span>
										<span component="topic/pinned" class="badge border border-gray-300 text-body mt-3 {{{ if (./scheduled || !./pinned) }}}hidden{{{ end }}}">
											<i class="fa fa-thumb-tack"></i>
											<span>{{{ if !./pinExpiry }}}[[topic:pinned]]{{{ else }}}[[topic:pinned-with-expiry, {isoTimeToLocaleString(./pinExpiryISO, config.userLang)}]]{{{ end }}}</span>
										</span>
										<span component="topic/locked" class="badge border border-gray-300 text-body mt-3 {{{ if !./locked }}}hidden{{{ end }}}">
											<i class="fa fa-lock"></i>
											<span>[[topic:locked]]</span>
										</span>
										<span class="badge border border-gray-300 text-body mt-3 {{{ if !./oldCid }}}hidden{{{ end }}}">
											<i class="fa fa-arrow-circle-right"></i>
											<span>[[topic:moved]]</span>
										</span>
										{{{each ./icons}}}<span class="lh-1">{@value}</span>{{{end}}}
									</div>
								</div>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</li>
	{{{ end }}}
</ul>
