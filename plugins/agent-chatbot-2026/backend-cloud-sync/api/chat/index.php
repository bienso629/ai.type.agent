<?php
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Response.php';
require_once __DIR__ . '/../../src/AuthMiddleware.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Secret-Token, X-User-Email, X-User-Name');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    Response::error('Phương thức không được hỗ trợ.', 405);
}

$currentUser = AuthMiddleware::authenticate();
$userId = (int)$currentUser['id'];
$db = Database::getConnection();

$input = Response::getJsonInput();
$sessionId = $input['session_id'] ?? '';
$userMessage = trim($input['message'] ?? '');
$model = $input['model'] ?? '';
$attachments = $input['attachments'] ?? [];
$history = $input['history'] ?? [];

if (empty($sessionId)) {
    Response::error('Thiếu session_id.', 400);
}

// 1. Kiem tra hoac tao session
$sessStmt = $db->prepare('SELECT id FROM chat_sessions WHERE id = ? AND user_id = ? LIMIT 1');
$sessStmt->execute([$sessionId, $userId]);
if (!$sessStmt->fetch()) {
    $title = !empty($userMessage) ? mb_substr($userMessage, 0, 50, 'UTF-8') : 'Cuộc hội thoại';
    $now = date('Y-m-d H:i:s');
    $insSess = $db->prepare('INSERT INTO chat_sessions (id, user_id, title, is_pinned, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)');
    $insSess->execute([$sessionId, $userId, $title, $now, $now]);
}

// 2. Lay config
$cfgStmt = $db->prepare('SELECT config_json FROM user_configs WHERE user_id = ? LIMIT 1');
$cfgStmt->execute([$userId]);
$cfgRow = $cfgStmt->fetch();
$userConfig = $cfgRow ? json_decode($cfgRow['config_json'], true) : [];

$baseUrl = $userConfig['proxy_base_url'] ?? 'https://api-vn-sg.mitom.ai/v1';
$apiKey = $userConfig['proxy_api_key'] ?? '';
$targetModel = !empty($model) ? $model : ($userConfig['ai_model'] ?? 'gemini-2.5-flash');

// 3. Luu User Message
$attachmentsJson = !empty($attachments) ? json_encode($attachments, JSON_UNESCAPED_UNICODE) : null;
$insUserMsg = $db->prepare('INSERT INTO chat_messages (session_id, user_id, role, content, attachments_json, model, created_at) VALUES (?, ?, "user", ?, ?, ?, ?)');
$insUserMsg->execute([$sessionId, $userId, $userMessage, $attachmentsJson, $targetModel, date('Y-m-d H:i:s')]);

$db->prepare('UPDATE chat_sessions SET updated_at = ? WHERE id = ? AND user_id = ?')->execute([date('Y-m-d H:i:s'), $sessionId, $userId]);

// 4. Chuan bi context
$apiMessages = [];
$apiMessages[] = [
    'role' => 'system',
    'content' => 'Bạn là AI Agent Chatbot thông minh, hỗ trợ bằng tiếng Việt chuẩn mực, chi tiết và chính xác.'
];

if (!empty($history) && is_array($history)) {
    foreach ($history as $h) {
        if (isset($h['role'], $h['content']) && in_array($h['role'], ['user', 'assistant', 'system'])) {
            $apiMessages[] = [
                'role' => $h['role'],
                'content' => (string)$h['content']
            ];
        }
    }
} else {
    $histStmt = $db->prepare('SELECT role, content FROM chat_messages WHERE session_id = ? AND user_id = ? ORDER BY id ASC LIMIT 20');
    $histStmt->execute([$sessionId, $userId]);
    $dbMsgs = $histStmt->fetchAll();
    foreach ($dbMsgs as $dm) {
        $apiMessages[] = [
            'role' => $dm['role'],
            'content' => $dm['content']
        ];
    }
}

$lastMsg = end($apiMessages);
if (!$lastMsg || $lastMsg['role'] !== 'user' || $lastMsg['content'] !== $userMessage) {
    $apiMessages[] = [
        'role' => 'user',
        'content' => $userMessage
    ];
}

// 5. Stream SSE ve client
if (function_exists('apache_setenv')) {
    @apache_setenv('no-gzip', '1');
}
@ini_set('zlib.output_compression', '0');
@ini_set('implicit_flush', '1');
while (ob_get_level() > 0) {
    ob_end_clean();
}

header('Content-Type: text/event-stream; charset=utf-8');
header('Cache-Control: no-cache, no-transform');
header('Connection: keep-alive');
header('X-Accel-Buffering: no');

$payload = [
    'model' => $targetModel,
    'messages' => $apiMessages,
    'stream' => true,
];

$targetEndpoint = rtrim($baseUrl, '/') . '/chat/completions';

$ch = curl_init($targetEndpoint);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 120);

$reqHeaders = [
    'Content-Type: application/json',
    'Accept: text/event-stream'
];
if (!empty($apiKey)) {
    $reqHeaders[] = 'Authorization: Bearer ' . $apiKey;
}
curl_setopt($ch, CURLOPT_HTTPHEADER, $reqHeaders);

$accumulatedReply = '';
$rawBuffer = '';

curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($ch, $data) use (&$accumulatedReply, &$rawBuffer) {
    $rawBuffer .= $data;
    while (($pos = strpos($rawBuffer, "
")) !== false) {
        $line = substr($rawBuffer, 0, $pos);
        $rawBuffer = substr($rawBuffer, $pos + 1);
        $line = trim($line);

        if (empty($line)) continue;

        if (strpos($line, 'data:') === 0) {
            $jsonStr = trim(substr($line, 5));
            if ($jsonStr === '[DONE]') {
                echo "data: [DONE]

";
                if (ob_get_level() > 0) ob_flush();
                flush();
                continue;
            }

            $chunk = json_decode($jsonStr, true);
            if ($chunk && isset($chunk['choices'][0]['delta']['content'])) {
                $delta = $chunk['choices'][0]['delta']['content'];
                $accumulatedReply .= $delta;
                
                $out = json_encode(['type' => 'token', 'delta' => $delta], JSON_UNESCAPED_UNICODE);
                echo "data: $out

";
                if (ob_get_level() > 0) ob_flush();
                flush();
            }
        }
    }
    return strlen($data);
});

curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr = curl_error($ch);
curl_close($ch);

if ($httpCode >= 400 || !empty($curlErr)) {
    if ($httpCode === 401) {
        $errMsg = 'Chưa cấu hình API Key cho Mitom AI hoặc API Key không hợp lệ. Vui lòng vào Cài đặt -> AI & Proxy để nhập Proxy API Key.';
    } else {
        $errMsg = !empty($curlErr) ? $curlErr : "Lỗi từ AI Provider (HTTP $httpCode)";
    }
    if (empty($accumulatedReply)) {
        $out = json_encode(['type' => 'error', 'message' => $errMsg], JSON_UNESCAPED_UNICODE);
        echo "data: $out

";
    }
}

if (!empty($accumulatedReply)) {
    $insAssistant = $db->prepare('INSERT INTO chat_messages (session_id, user_id, role, content, model, created_at) VALUES (?, ?, "assistant", ?, ?, ?)');
    $insAssistant->execute([$sessionId, $userId, $accumulatedReply, $targetModel, date('Y-m-d H:i:s')]);
    $db->prepare('UPDATE chat_sessions SET updated_at = ? WHERE id = ? AND user_id = ?')->execute([date('Y-m-d H:i:s'), $sessionId, $userId]);
}

echo "data: [DONE]

";
if (ob_get_level() > 0) ob_flush();
flush();