<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    Response::json([], 200);
}

$currentUser = AuthMiddleware::tryAuthenticate();
$userId = $currentUser ? (int)$currentUser['id'] : 0;
$db = Database::getConnection();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    if ($userId > 0) {
        $stmt = $db->prepare('SELECT config_json FROM user_configs WHERE user_id = ? LIMIT 1');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        $config = $row ? json_decode($row['config_json'], true) : [];
        Response::success(['config' => $config ?: new stdClass()]);
    } else {
        // Cấu hình mặc định cho khách / người dùng chưa đăng nhập
        Response::success([
            'config' => [
                'ai_model' => 'gemini-2.5-flash',
                'proxy_base_url' => 'https://api-vn-sg.mitom.ai/v1',
                'app_title' => 'AI Agent Chatbot',
                'brand_title' => 'AI Agent',
                'brand_subtitle' => 'AI AGENT CHATBOT',
            ]
        ]);
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!$currentUser) {
        $currentUser = AuthMiddleware::authenticate();
        $userId = (int)$currentUser['id'];
    }
    $input = Response::getJsonInput();
    $configData = $input['config'] ?? $input;
    $jsonString = json_encode($configData, JSON_UNESCAPED_UNICODE);

    $stmt = $db->prepare('INSERT INTO user_configs (user_id, config_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE config_json = VALUES(config_json)');
    $stmt->execute([$userId, $jsonString]);

    Response::success([], 'Đồng bộ cấu hình lên Cloud thành công!');
}

Response::error('Phương thức không được hỗ trợ.', 405);
