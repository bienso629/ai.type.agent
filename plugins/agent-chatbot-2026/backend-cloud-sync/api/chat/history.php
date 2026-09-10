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

// GET: Lấy lịch sử tin nhắn của session
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $sessionId = $_GET['session_id'] ?? '';
    $limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
    $beforeId = isset($_GET['before_id']) ? (int)$_GET['before_id'] : null;

    if (empty($sessionId)) {
        Response::error('Thiếu session_id.');
    }

    if ($limit < 1) $limit = 50;
    if ($limit > 100) $limit = 100;

    $params = [$sessionId, $userId];
    $sql = 'SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at FROM chat_messages WHERE session_id = ? AND user_id = ?';

    if ($beforeId !== null && $beforeId > 0) {
        $sql .= ' AND id < ?';
        $params[] = $beforeId;
    }

    $sql .= ' ORDER BY id DESC LIMIT ' . ($limit + 1);
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    $hasMore = false;
    if (count($rows) > $limit) {
        $hasMore = true;
        array_pop($rows);
    }

    // Đảo ngược lại thứ tự cũ trước mới sau (ASC) để hiển thị trong UI
    $rows = array_reverse($rows);

    $oldestId = 0;
    $messages = [];
    foreach ($rows as $row) {
        if ($oldestId === 0 || (int)$row['id'] < $oldestId) {
            $oldestId = (int)$row['id'];
        }
        $toolCalls = [];
        if (!empty($row['tool_calls_json'])) {
            $toolCalls = json_decode($row['tool_calls_json'], true) ?: [];
        }
        $attachments = [];
        if (!empty($row['attachments_json'])) {
            $attachments = json_decode($row['attachments_json'], true) ?: [];
        }

        $messages[] = [
            'id' => (int)$row['id'],
            'session_id' => $row['session_id'],
            'role' => $row['role'],
            'content' => $row['content'],
            'model' => $row['model'] ?? 'gemini-2.5-flash',
            'created_at' => $row['created_at'],
            'tool_calls' => $toolCalls,
            'attachments' => $attachments,
        ];
    }

    Response::json([
        'success' => true,
        'messages' => $messages,
        'has_more' => $hasMore,
        'oldest_id' => $oldestId,
    ], 200);
}

Response::error('Phương thức không được hỗ trợ.', 405);
