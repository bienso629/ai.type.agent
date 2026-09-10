<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    Response::json([], 200);
}

$currentUser = AuthMiddleware::authenticate();
$db = Database::getConnection();

$stmt = $db->prepare('SELECT id, email, name, role, created_at FROM users WHERE id = ? LIMIT 1');
$stmt->execute([$currentUser['id']]);
$user = $stmt->fetch();

if (!$user) {
    Response::error('Người dùng không tồn tại.', 404);
}

Response::success([
    'user' => $user,
    'is_admin' => ($user['role'] === 'admin'),
]);
