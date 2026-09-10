<?php
class Response {
    public static function json($data, int $statusCode = 200): void {
        http_response_code($statusCode);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        exit;
    }

    public static function error(string $message, int $statusCode = 400): void {
        self::json(['success' => false, 'error' => $message], $statusCode);
    }

    public static function success($data = [], string $message = 'Thành công'): void {
        self::json([
            'success' => true,
            'message' => $message,
            'data' => $data,
        ], 200);
    }

    public static function getJsonInput(): array {
        $raw = file_get_contents('php://input');
        if (empty($raw)) return [];
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }
}
