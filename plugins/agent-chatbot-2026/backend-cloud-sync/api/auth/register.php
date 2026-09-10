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
$name = trim($input['name'] ?? '');

if (empty($email) || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    Response::error('Email không hợp lệ.');
}

if (strlen($password) < 6) {
    Response::error('Mật khẩu tối thiểu 6 ký tự.');
}

if (empty($name)) {
    $name = explode('@', $email)[0];
}

$db = Database::getConnection();

// Kiểm tra xem email đã tồn tại chưa
$stmt = $db->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
$stmt->execute([$email]);
if ($stmt->fetch()) {
    Response::error('Email này đã được đăng ký.');
}

// Kiểm tra xem hệ thống đã có user nào chưa. Nếu chưa -> người đăng ký đầu tiên là ADMIN!
$countStmt = $db->query('SELECT COUNT(*) FROM users');
$totalUsers = (int)$countStmt->fetchColumn();
$role = ($totalUsers === 0) ? 'admin' : 'user';

// Sinh salt và hash SHA-256 (khớp với mã nguồn UserService trong ứng dụng Flutter)
$salt = bin2hex(random_bytes(16));
$passwordHash = hash('sha256', $password . '::' . $salt);

$insertStmt = $db->prepare('INSERT INTO users (email, name, password_hash, salt, role) VALUES (?, ?, ?, ?, ?)');
$insertStmt->execute([$email, $name, $passwordHash, $salt, $role]);
$userId = (int)$db->lastInsertId();

$user = [
    'id' => $userId,
    'email' => $email,
    'name' => $name,
    'role' => $role,
];

$token = AuthMiddleware::generateToken($user);

Response::success([
    'token' => $token,
    'user' => $user,
    'is_admin' => ($role === 'admin'),
], 'Đăng ký tài khoản thành công!');
