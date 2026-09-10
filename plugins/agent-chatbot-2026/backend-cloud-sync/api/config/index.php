<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    Response::json([], 200);
}

$currentUser = AuthMiddleware::authenticate();
$userId = (int)$currentUser['id'];
$db = Database::getConnection();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->prepare('SELECT config_json FROM user_configs WHERE user_id = ? LIMIT 1');
    $stmt->execute([$userId]);
    $row = $stmt->fetch();
    $config = $row ? json_decode($row['config_json'], true) : [];
    Response::success(['config' => $config ?: new stdClass()]);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = Response::getJsonInput();
    $configData = $input['config'] ?? $input;
    $jsonString = json_encode($configData, JSON_UNESCAPED_UNICODE);

    $stmt = $db->prepare('INSERT INTO user_configs (user_id, config_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE config_json = VALUES(config_json)');
    $stmt->execute([$userId, $jsonString]);

    Response::success([], 'Đồng bộ cấu hình lên Cloud thành công!');
}

Response::error('Phương thức không được hỗ trợ.', 405);
