<?php
/**
 * AI Type Redis Cache Driver
 * 
 * Helper class quản lý kết nối Redis cho Full Page Cache.
 * Hỗ trợ fallback về file cache nếu Redis không available.
 * 
 * Cấu hình trong wp-config.php:
 *   define('AITYPE_REDIS_HOST', '127.0.0.1');
 *   define('AITYPE_REDIS_PORT', 6379);
 *   define('AITYPE_REDIS_PASSWORD', '');       // Tùy chọn
 *   define('AITYPE_REDIS_DB', 0);              // Tùy chọn (0-15)
 *   define('AITYPE_REDIS_PREFIX', 'ait_fpc:'); // Tùy chọn
 */

if (!defined('ABSPATH') && !defined('AITYPE_REDIS_STANDALONE')) exit;

class CLBNTB_Redis {

    private static $instance = null;
    private $redis = null;
    private $connected = false;
    private $prefix = 'ait_fpc:';

    /**
     * Singleton
     */
    public static function instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        $this->prefix = defined('AITYPE_REDIS_PREFIX') ? AITYPE_REDIS_PREFIX : 'ait_fpc:';
        $this->connect();
    }

    /**
     * Kết nối Redis
     */
    private function connect() {
        if ($this->connected) return true;

        // Kiểm tra extension php-redis
        if (!class_exists('Redis')) {
            return false;
        }

        $host = defined('AITYPE_REDIS_HOST') ? AITYPE_REDIS_HOST : '127.0.0.1';
        $port = defined('AITYPE_REDIS_PORT') ? AITYPE_REDIS_PORT : 6379;
        $password = defined('AITYPE_REDIS_PASSWORD') ? AITYPE_REDIS_PASSWORD : '';
        $db = defined('AITYPE_REDIS_DB') ? (int)AITYPE_REDIS_DB : 0;
        $timeout = 1; // 1 giây timeout, tránh block request

        try {
            $this->redis = new Redis();
            $this->connected = $this->redis->connect($host, $port, $timeout);
            
            if ($this->connected && !empty($password)) {
                $this->connected = $this->redis->auth($password);
            }
            
            if ($this->connected && $db > 0) {
                $this->redis->select($db);
            }

            if ($this->connected) {
                // Serializer PHP cho lưu data phức tạp
                $this->redis->setOption(Redis::OPT_SERIALIZER, Redis::SERIALIZER_NONE);
            }
        } catch (Exception $e) {
            $this->connected = false;
            $this->redis = null;
        }

        return $this->connected;
    }

    /**
     * Kiểm tra Redis có sẵn không
     */
    public function is_available() {
        return $this->connected && $this->redis !== null;
    }

    /**
     * Lấy cache theo key
     * 
     * @param string $key Cache key (chưa có prefix)
     * @return string|false Nội dung cache hoặc false nếu miss
     */
    public function get($key) {
        if (!$this->is_available()) return false;
        
        try {
            $result = $this->redis->get($this->prefix . $key);
            return ($result !== false) ? $result : false;
        } catch (Exception $e) {
            return false;
        }
    }

    /**
     * Lưu cache
     * 
     * @param string $key Cache key (chưa có prefix)
     * @param string $value Nội dung HTML
     * @param int $ttl Thời gian sống (giây). 0 = không hết hạn
     */
    public function set($key, $value, $ttl = 86400) {
        if (!$this->is_available()) return false;
        
        try {
            if ($ttl > 0) {
                return $this->redis->setex($this->prefix . $key, $ttl, $value);
            } else {
                return $this->redis->set($this->prefix . $key, $value);
            }
        } catch (Exception $e) {
            return false;
        }
    }

    /**
     * Xóa cache theo key
     */
    public function delete($key) {
        if (!$this->is_available()) return false;
        
        try {
            return $this->redis->del($this->prefix . $key);
        } catch (Exception $e) {
            return false;
        }
    }

    /**
     * Xóa cache theo pattern (dùng cho targeted invalidation)
     * Ví dụ: delete_pattern('abc123*') xóa tất cả key bắt đầu bằng abc123
     * 
     * @param string $pattern Pattern glob (vd: 'abc*')
     */
    public function delete_pattern($pattern) {
        if (!$this->is_available()) return false;
        
        try {
            $iterator = null;
            $full_pattern = $this->prefix . $pattern;
            $deleted = 0;
            
            // Dùng SCAN thay vì KEYS để tránh block Redis server
            while (($keys = $this->redis->scan($iterator, $full_pattern, 100)) !== false) {
                if (!empty($keys)) {
                    $deleted += $this->redis->del($keys);
                }
            }
            
            return $deleted;
        } catch (Exception $e) {
            return false;
        }
    }

    /**
     * Xóa toàn bộ FPC cache (chỉ xóa key có prefix)
     */
    public function flush_all() {
        return $this->delete_pattern('*');
    }

    /**
     * Kiểm tra key có tồn tại không
     */
    public function exists($key) {
        if (!$this->is_available()) return false;
        
        try {
            return $this->redis->exists($this->prefix . $key);
        } catch (Exception $e) {
            return false;
        }
    }

    /**
     * Lấy thông tin Redis (dùng cho admin dashboard)
     */
    public function info() {
        if (!$this->is_available()) return false;
        
        try {
            $info = $this->redis->info();
            
            // Đếm số key FPC
            $iterator = null;
            $fpc_count = 0;
            while (($keys = $this->redis->scan($iterator, $this->prefix . '*', 100)) !== false) {
                $fpc_count += count($keys);
            }
            
            return [
                'connected' => true,
                'version' => $info['redis_version'] ?? 'unknown',
                'used_memory_human' => $info['used_memory_human'] ?? 'unknown',
                'total_keys' => $info['db0'] ?? 'unknown',
                'fpc_keys' => $fpc_count,
                'uptime_days' => isset($info['uptime_in_days']) ? $info['uptime_in_days'] : 0,
                'hit_rate' => isset($info['keyspace_hits'], $info['keyspace_misses']) 
                    ? round($info['keyspace_hits'] / max(1, $info['keyspace_hits'] + $info['keyspace_misses']) * 100, 1) . '%'
                    : 'N/A',
            ];
        } catch (Exception $e) {
            return ['connected' => false, 'error' => $e->getMessage()];
        }
    }

    /**
     * Ping Redis
     */
    public function ping() {
        if (!$this->is_available()) return false;
        try {
            return $this->redis->ping();
        } catch (Exception $e) {
            return false;
        }
    }
}
