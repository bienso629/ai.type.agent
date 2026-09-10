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

// GET: Lấy tin nhắn theo session_id
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $sessionId = $_GET['session_id'] ?? '';
    if (empty($sessionId)) {
        Response::error('Thiếu session_id.');
    }

    $stmt = $db->prepare('SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at FROM chat_messages WHERE session_id = ? AND user_id = ? ORDER BY id ASC');
    $stmt->execute([$sessionId, $userId]);
    $messages = $stmt->fetchAll();
    Response::success(['messages' => $messages]);
}

// POST: Thêm hoặc đồng bộ tin nhắn
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = Response::getJsonInput();

    // Đồng bộ danh sách nhiều tin nhắn (Sync array)
    if (isset($input['messages']) && is_array($input['messages'])) {
        $db->beginTransaction();
        $stmt = $db->prepare('INSERT INTO chat_messages (session_id, user_id, role, content, attachments_json, tool_calls_json, model, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
        foreach ($input['messages'] as $msg) {
            $stmt->execute([
                $msg['session_id'] ?? 'default',
                $userId,
                $msg['role'] ?? 'user',
                $msg['content'] ?? '',
                isset($msg['attachments_json']) ? (is_string($msg['attachments_json']) ? $msg['attachments_json'] : json_encode($msg['attachments_json'])) : null,
                isset($msg['tool_calls_json']) ? (is_string($msg['tool_calls_json']) ? $msg['tool_calls_json'] : json_encode($msg['tool_calls_json'])) : null,
                $msg['model'] ?? 'gemini-2.5-flash',
                $msg['created_at'] ?? date('Y-m-d H:i:s'),
            ]);
        }
        $db->commit();
        Response::success([], 'Đồng bộ tin nhắn thành công');
    }

    // Gửi 1 tin nhắn đơn lẻ
    if (isset($input['session_id']) && isset($input['role']) && isset($input['content'])) {
        $stmt = $db->prepare('INSERT INTO chat_messages (session_id, user_id, role, content, attachments_json, tool_calls_json, model, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([
            $input['session_id'],
            $userId,
            $input['role'],
            $input['content'],
            isset($input['attachments_json']) ? (is_string($input['attachments_json']) ? $input['attachments_json'] : json_encode($input['attachments_json'])) : null,
            isset($input['tool_calls_json']) ? (is_string($input['tool_calls_json']) ? $input['tool_calls_json'] : json_encode($input['tool_calls_json'])) : null,
            $input['model'] ?? 'gemini-2.5-flash',
            $input['created_at'] ?? date('Y-m-d H:i:s'),
        ]);
        Response::success(['message_id' => $db->lastInsertId()], 'Lưu tin nhắn thành công');
    }

    Response::error('Dữ liệu tin nhắn không hợp lệ.');
}

// DELETE: Xóa tin nhắn trong 1 phiên chat
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $sessionId = $_GET['session_id'] ?? '';
    if (empty($sessionId)) {
        Response::error('Thiếu session_id để xóa tin nhắn.');
    }
    $stmt = $db->prepare('DELETE FROM chat_messages WHERE session_id = ? AND user_id = ?');
    $stmt->execute([$sessionId, $userId]);
    Response::success([], 'Đã dọn dẹp lịch sử tin nhắn của phiên chat');
}

Response::error('Phương thức không được hỗ trợ.', 405);
