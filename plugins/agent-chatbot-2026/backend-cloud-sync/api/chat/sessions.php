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
    $stmt = $db->prepare('SELECT s.id, s.title, s.is_pinned, s.created_at, s.updated_at, COUNT(m.id) as message_count FROM chat_sessions s LEFT JOIN chat_messages m ON s.id = m.session_id AND m.user_id = s.user_id WHERE s.user_id = ? GROUP BY s.id, s.title, s.is_pinned, s.created_at, s.updated_at ORDER BY s.is_pinned DESC, s.updated_at DESC');
    $stmt->execute([$userId]);
    $sessions = $stmt->fetchAll();
    Response::success(['sessions' => $sessions]);
}

// POST: Tạo hoặc đồng bộ danh sách session, hoặc pin
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = Response::getJsonInput();
    $sessionId = $_GET['id'] ?? '';
    $action = $_GET['action'] ?? '';

    // Nếu là pin action: POST /api/chat/sessions/{id}/pin
    if ($action === 'pin' || (isset($input['is_pinned']) && !isset($input['title']))) {
        $sessId = !empty($sessionId) ? $sessionId : ($input['id'] ?? '');
        if (empty($sessId)) {
            Response::error('Thiếu mã phiên chat.');
        }
        $isPinned = isset($input['is_pinned']) ? ($input['is_pinned'] ? 1 : 0) : 1;
        $stmt = $db->prepare('UPDATE chat_sessions SET is_pinned = ? WHERE id = ? AND user_id = ?');
        $stmt->execute([$isPinned, $sessId, $userId]);
        Response::success(['is_pinned' => (bool)$isPinned], 'Đã cập nhật ghim');
    }

    // Nếu gửi tạo session mới (có thể có hoặc không có id từ client)
    if (isset($input['title']) || isset($input['id'])) {
        $id = !empty($input['id']) ? $input['id'] : ('sess_' . round(microtime(true) * 1000) . '_' . bin2hex(random_bytes(3)));
        $title = $input['title'] ?? 'Cuộc hội thoại mới';
        $isPinned = !empty($input['is_pinned']) ? 1 : 0;
        $now = date('Y-m-d H:i:s');

        $stmt = $db->prepare('INSERT INTO chat_sessions (id, user_id, title, is_pinned, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE title = VALUES(title), is_pinned = VALUES(is_pinned), updated_at = VALUES(updated_at)');
        $stmt->execute([$id, $userId, $title, $isPinned, $now, $now]);

        Response::json([
            'id' => $id,
            'title' => $title,
            'is_pinned' => (bool)$isPinned,
            'created_at' => $now,
            'updated_at' => $now,
            'message_count' => 0,
            'success' => true,
        ], 200);
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

// PUT: Cập nhật tiêu đề session
if ($_SERVER['REQUEST_METHOD'] === 'PUT') {
    $input = Response::getJsonInput();
    $sessionId = $_GET['id'] ?? $input['id'] ?? '';
    $title = $input['title'] ?? '';

    if (empty($sessionId) || empty($title)) {
        Response::error('Thiếu mã phiên chat hoặc tiêu đề mới.');
    }

    $stmt = $db->prepare('UPDATE chat_sessions SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?');
    $stmt->execute([$title, $sessionId, $userId]);
    Response::success(['id' => $sessionId, 'title' => $title], 'Đổi tên phiên chat thành công');
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
