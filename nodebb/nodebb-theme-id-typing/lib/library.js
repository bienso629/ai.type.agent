'use strict';

const _ = require.main.require('lodash');
const meta = require.main.require('./src/meta');
const user = require.main.require('./src/user');

const library = module.exports;

library.init = async function (params) {
	const { router } = params;
	const routeHelpers = require.main.require('./src/routes/helpers');
	routeHelpers.setupAdminPageRoute(router, '/admin/plugins/ai-typing', function (req, res, next) {
		res.render('admin/plugins/ai-typing', {
			title: 'ai-typing Theme',
		});
	});
};

library.defineWidgetAreas = async function (areas) {
	const locations = ['header', 'sidebar', 'footer'];
	const templates = [
		'categories.tpl', 'category.tpl', 'topic.tpl', 'users.tpl',
		'unread.tpl', 'recent.tpl', 'popular.tpl', 'top.tpl', 'tags.tpl', 'tag.tpl',
		'login.tpl', 'register.tpl',
	];
	function capitalizeFirst(str) {
		return str.charAt(0).toUpperCase() + str.slice(1);
	}
	templates.forEach((template) => {
		locations.forEach((location) => {
			areas.push({
				name: `${capitalizeFirst(template.split('.')[0])} ${capitalizeFirst(location)}`,
				template: template,
				location: location,
			});
		});
	});

	areas = areas.concat([
		{
			name: 'Account Header',
			template: 'account/profile.tpl',
			location: 'header',
		},
	]);
	return areas;
};

library.filterConfigGet = async function (config) {
	const settings = await meta.settings.get('ai-typing');
	config.enableQuickReply = settings.enableQuickReply === 'on';
	return config;
};

library.addAdminNavigation = async function (header) {
	header.plugins.push({
		route: '/plugins/ai-typing',
		icon: 'fa-paint-brush',
		name: 'ai-typing Theme'
	});
	return header;
};

library.filterMiddlewareRenderHeader = async function (hookData) {
	hookData.templateData.bootswatchSkinOptions = await meta.css.getSkinSwitcherOptions(hookData.req.uid);
	return hookData;
};
