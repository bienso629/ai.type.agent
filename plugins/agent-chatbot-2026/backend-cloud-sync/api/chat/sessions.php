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

// GET: Lấy danh sách session
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->prepare('SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions WHERE user_id = ? ORDER BY is_pinned DESC, updated_at DESC');
    $stmt->execute([$userId]);
    $sessions = $stmt->fetchAll();
    Response::success(['sessions' => $sessions]);
}

// POST: Tạo hoặc đồng bộ danh sách session
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = Response::getJsonInput();

    // Nếu gửi 1 session đơn lẻ
    if (isset($input['id']) && isset($input['title'])) {
        $id = $input['id'];
        $title = $input['title'];
        $isPinned = !empty($input['is_pinned']) ? 1 : 0;

        $stmt = $db->prepare('INSERT INTO chat_sessions (id, user_id, title, is_pinned) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE title = VALUES(title), is_pinned = VALUES(is_pinned)');
        $stmt->execute([$id, $userId, $title, $isPinned]);
        Response::success(['session_id' => $id], 'Lưu phiên chat thành công');
    }

    // Nếu gửi 1 mảng các session để sync hàng loạt
    if (isset($input['sessions']) && is_array($input['sessions'])) {
        $db->beginTransaction();
        $stmt = $db->prepare('INSERT INTO chat_sessions (id, user_id, title, is_pinned) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE title = VALUES(title), is_pinned = VALUES(is_pinned)');
        foreach ($input['sessions'] as $sess) {
            $stmt->execute([
                $sess['id'],
                $userId,
                $sess['title'] ?? 'Cuộc hội thoại',
                !empty($sess['is_pinned']) ? 1 : 0
            ]);
        }
        $db->commit();
        Response::success([], 'Đồng bộ danh sách phiên chat thành công');
    }

    Response::error('Dữ liệu phiên chat không hợp lệ.');
}

// DELETE: Xóa session
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $input = Response::getJsonInput();
    $sessionId = $_GET['id'] ?? $input['id'] ?? '';
    if (empty($sessionId)) {
        Response::error('Thiếu mã phiên chat.');
    }
    $stmt = $db->prepare('DELETE FROM chat_sessions WHERE id = ? AND user_id = ?');
    $stmt->execute([$sessionId, $userId]);
    Response::success([], 'Đã xóa phiên chat');
}

Response::error('Phương thức không được hỗ trợ.', 405);
