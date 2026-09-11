<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Secret-Token, X-User-Email, X-User-Name');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$currentUser = AuthMiddleware::authenticate();
$userId = (int)$currentUser['id'];
$db = Database::getConnection();

// GET: Lay danh sach tai lieu
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->prepare('SELECT id, name, extension, size, path, content, is_enabled, created_at FROM knowledge_documents WHERE user_id = ? ORDER BY id DESC');
    $stmt->execute([$userId]);
    $docs = $stmt->fetchAll();
    Response::success(['documents' => $docs]);
}

// POST: Them tai lieu hoac toggle
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = Response::getJsonInput();
    $action = $_GET['action'] ?? '';

    if ($action === 'toggle' || isset($input['is_enabled']) && count($input) <= 2) {
        $id = (int)($input['id'] ?? $_GET['id'] ?? 0);
        $isEnabled = !empty($input['is_enabled']) ? 1 : 0;
        $stmt = $db->prepare('UPDATE knowledge_documents SET is_enabled = ? WHERE id = ? AND user_id = ?');
        $stmt->execute([$isEnabled, $id, $userId]);
        Response::success([], 'Cap nhat trang thai thanh cong');
    }

    if (isset($input['name']) && isset($input['content'])) {
        $name = $input['name'];
        $ext = $input['extension'] ?? pathinfo($name, PATHINFO_EXTENSION);
        $size = (int)($input['size'] ?? 0);
        $path = $input['path'] ?? $name;
        $content = $input['content'];
        $isEnabled = isset($input['is_enabled']) ? ($input['is_enabled'] ? 1 : 0) : 1;

        $stmt = $db->prepare('INSERT INTO knowledge_documents (user_id, name, extension, size, path, content, is_enabled, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())');
        $stmt->execute([$userId, $name, $ext, $size, $path, $content, $isEnabled]);
        Response::success(['id' => $db->lastInsertId()], 'Luu tai lieu thanh cong');
    }

    Response::error('Du lieu khong hop le');
}

// DELETE: Xoa tai lieu
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $id = (int)($_GET['id'] ?? Response::getJsonInput()['id'] ?? 0);
    $stmt = $db->prepare('DELETE FROM knowledge_documents WHERE id = ? AND user_id = ?');
    $stmt->execute([$id, $userId]);
    Response::success([], 'Xoa tai lieu thanh cong');
}

Response::error('Phuong thuc khong hop le', 405);