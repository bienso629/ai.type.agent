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

$input = Response::getJsonInput();
$email = strtolower(trim($input['email'] ?? ''));
$password = $input['password'] ?? '';

if (empty($email) || empty($password)) {
    Response::error('Vui lòng nhập đầy đủ Email và Mật khẩu.');
}

$db = Database::getConnection();
$stmt = $db->prepare('SELECT id, email, name, password_hash, salt, role FROM users WHERE email = ? LIMIT 1');
$stmt->execute([$email]);
$user = $stmt->fetch();

if (!$user) {
    Response::error('Tài khoản hoặc mật khẩu không chính xác.', 401);
}

$testHash = hash('sha256', $password . '::' . $user['salt']);
if (!hash_equals($user['password_hash'], $testHash)) {
    Response::error('Tài khoản hoặc mật khẩu không chính xác.', 401);
}

$token = AuthMiddleware::generateToken($user);

$firstUserStmt = $db->query('SELECT id FROM users ORDER BY id ASC LIMIT 1');
$firstUserId = (int)$firstUserStmt->fetchColumn();
$isAdmin = ($user['role'] === 'admin') || ((int)$user['id'] === $firstUserId);

Response::success([
    'token' => $token,
    'user' => [
        'id' => $user['id'],
        'email' => $user['email'],
        'name' => $user['name'],
        'role' => $user['role'],
    ],
    'is_admin' => $isAdmin,
], 'Đăng nhập thành công!');
