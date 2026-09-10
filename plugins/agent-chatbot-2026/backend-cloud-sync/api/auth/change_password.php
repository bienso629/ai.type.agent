<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    Response::json([], 200);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    Response::error('Phương thức không được hỗ trợ.', 405);
}

$currentUser = AuthMiddleware::authenticate();
$userId = (int)$currentUser['id'];

$input = Response::getJsonInput();
$currentPassword = $input['current_password'] ?? '';
$newPassword = $input['new_password'] ?? '';

if (empty($currentPassword) || empty($newPassword)) {
    Response::error('Vui lòng nhập đầy đủ mật khẩu hiện tại và mật khẩu mới.');
}

if (strlen($newPassword) < 6) {
    Response::error('Mật khẩu mới phải có tối thiểu 6 ký tự.');
}

$db = Database::getConnection();
$stmt = $db->prepare('SELECT id, password_hash, salt FROM users WHERE id = ? LIMIT 1');
$stmt->execute([$userId]);
$user = $stmt->fetch();

if (!$user) {
    Response::error('Không tìm thấy thông tin người dùng.', 404);
}

$currentHash = hash('sha256', $currentPassword . '::' . $user['salt']);
if (!hash_equals($user['password_hash'], $currentHash)) {
    Response::error('Mật khẩu hiện tại không chính xác.', 400);
}

// Sinh salt mới và hash mật khẩu mới
$newSalt = bin2hex(random_bytes(16));
$newPasswordHash = hash('sha256', $newPassword . '::' . $newSalt);

$updateStmt = $db->prepare('UPDATE users SET password_hash = ?, salt = ? WHERE id = ?');
$updateStmt->execute([$newPasswordHash, $newSalt, $userId]);

Response::success([], 'Đổi mật khẩu thành công!');
