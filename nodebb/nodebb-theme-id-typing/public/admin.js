
'use strict';

define('admin/plugins/ai-typing', ['settings'], function (Settings) {
	const ACP = {};

	ACP.init = function () {
		Settings.load('ai-typing', $('.ai-typing-settings'));

		$('#save').on('click', function () {
			Settings.save('ai-typing', $('.ai-typing-settings'));
		});
	};

	return ACP;
});