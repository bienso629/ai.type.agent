<?php
require_once __DIR__ . '/Database.php';
require_once __DIR__ . '/Response.php';

class AuthMiddleware {
    private static string $jwtSecret = 'AgentChatbotSecretKey2026!CloudSync';

    private static function base64UrlEncode(string $data): string {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $data): string {
        return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', (4 - strlen($data) % 4) % 4));
    }

    public static function generateToken(array $user): string {
        $header = self::base64UrlEncode(json_encode(['typ' => 'JWT', 'alg' => 'HS256']));
        $payload = self::base64UrlEncode(json_encode([
            'id' => $user['id'],
            'email' => $user['email'],
            'role' => $user['role'] ?? 'user',
            'iat' => time(),
            'exp' => time() + (86400 * 30), // 30 ngày
        ]));
        $signature = self::base64UrlEncode(hash_hmac('sha256', "$header.$payload", self::$jwtSecret, true));
        return "$header.$payload.$signature";
    }

    public static function authenticate(): array {
        $authHeader = '';
        if (function_exists('getallheaders')) {
            $headers = getallheaders();
            $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
        if (empty($authHeader) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
            $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
        }

        if (!preg_match('/Bearer\s(\S+)/i', $authHeader, $matches)) {
            Response::error('Yêu cầu cung cấp Bearer Token xác thực.', 401);
        }

        $token = $matches[1];
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            Response::error('Token không đúng định dạng.', 401);
        }

        [$header, $payload, $signature] = $parts;
        $expectedSig = self::base64UrlEncode(hash_hmac('sha256', "$header.$payload", self::$jwtSecret, true));
        if (!hash_equals($expectedSig, $signature)) {
            Response::error('Token không hợp lệ hoặc đã bị thay đổi.', 401);
        }

        $data = json_decode(self::base64UrlDecode($payload), true);
        if (!$data || ($data['exp'] ?? 0) < time()) {
            Response::error('Token đã hết hạn. Vui lòng đăng nhập lại.', 401);
        }

        return $data;
    }
}
