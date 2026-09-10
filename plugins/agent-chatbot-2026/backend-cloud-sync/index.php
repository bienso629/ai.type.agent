<?php
require_once __DIR__ . '/src/Response.php';

Response::json([
    'service' => 'Agent Chatbot 2026 Cloud Sync Server',
    'status' => 'online',
    'version' => '1.0.0',
    'endpoints' => [
        'POST /api/auth/register.php' => 'Đăng ký tài khoản mới (User đầu tiên là Admin)',
        'POST /api/auth/login.php' => 'Đăng nhập và lấy Bearer Token',
        'GET /api/auth/me.php' => 'Lấy thông tin tài khoản hiện tại',
        'GET|POST /api/config/index.php' => 'Đồng bộ cấu hình ứng dụng',
        'GET|POST|DELETE /api/chat/sessions.php' => 'Đồng bộ danh sách phiên chat',
        'GET|POST|DELETE /api/chat/messages.php' => 'Đồng bộ tin nhắn hội thoại',
    ],
    'timestamp' => date('Y-m-d H:i:s'),
]);
