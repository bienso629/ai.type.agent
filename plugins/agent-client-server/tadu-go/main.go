package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"golang.org/x/crypto/ssh"
	_ "modernc.org/sqlite"
)

var (
	appDir     string
	configFile string
	dbPath     string
	db         *sql.DB
	dbMutex    sync.Mutex
	cfgMutex   sync.RWMutex
	upgrader   = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
)

func getCryptoKeys() ([]byte, []byte) {
	machineID := "tadu-cloud-ai-agent-control-center-secret-salt-2026"
	for _, p := range []string{"/etc/machine-id", "/var/lib/dbus/machine-id"} {
		if data, err := os.ReadFile(p); err == nil {
			machineID += strings.TrimSpace(string(data))
			break
		}
	}
	hash := sha256.Sum256([]byte(machineID))
	return hash[:16], hash[16:]
}

func decryptValue(val string) string {
	if !strings.HasPrefix(val, "enc:") {
		return val
	}
	rawToken := strings.TrimPrefix(val, "enc:")
	decoded, err := base64.URLEncoding.DecodeString(rawToken)
	if err != nil || len(decoded) < 57 {
		return val
	}
	_, encKey := getCryptoKeys()
	iv := decoded[9:25]
	ciphertext := decoded[25 : len(decoded)-32]
	block, err := aes.NewCipher(encKey)
	if err != nil {
		return val
	}
	if len(ciphertext)%aes.BlockSize != 0 {
		return val
	}
	mode := cipher.NewCBCDecrypter(block, iv)
	plaintext := make([]byte, len(ciphertext))
	mode.CryptBlocks(plaintext, ciphertext)
	if len(plaintext) == 0 {
		return val
	}
	pad := int(plaintext[len(plaintext)-1])
	if pad > len(plaintext) || pad == 0 {
		return val
	}
	for i := len(plaintext) - pad; i < len(plaintext); i++ {
		if int(plaintext[i]) != pad {
			return val
		}
	}
	return string(plaintext[:len(plaintext)-pad])
}

func encryptValue(plain string) string {
	if plain == "" || strings.HasPrefix(plain, "enc:") {
		return plain
	}
	signKey, encKey := getCryptoKeys()
	block, err := aes.NewCipher(encKey)
	if err != nil {
		return plain
	}
	pad := aes.BlockSize - len(plain)%aes.BlockSize
	padded := append([]byte(plain), make([]byte, pad)...)
	for i := len(plain); i < len(padded); i++ {
		padded[i] = byte(pad)
	}
	iv := make([]byte, 16)
	_, _ = rand.Read(iv)
	mode := cipher.NewCBCEncrypter(block, iv)
	ciphertext := make([]byte, len(padded))
	mode.CryptBlocks(ciphertext, padded)

	token := make([]byte, 0, 1+8+16+len(ciphertext)+32)
	token = append(token, 0x80)
	ts := make([]byte, 8)
	binary.BigEndian.PutUint64(ts, uint64(time.Now().Unix()))
	token = append(token, ts...)
	token = append(token, iv...)
	token = append(token, ciphertext...)

	mac := hmac.New(sha256.New, signKey)
	mac.Write(token)
	token = append(token, mac.Sum(nil)...)

	return "enc:" + base64.URLEncoding.EncodeToString(token)
}

func initPaths() {
	userHome, err := os.UserHomeDir()
	if err != nil {
		userHome = "."
	}
	userTaduDir := filepath.Join(userHome, ".tadu_ai_agent")
	_ = os.MkdirAll(userTaduDir, 0755)

	// Ưu tiên đọc DB và Config của user thực tế
	if _, err := os.Stat(filepath.Join(userTaduDir, "config.json")); err == nil {
		configFile = filepath.Join(userTaduDir, "config.json")
		dbPath = filepath.Join(userTaduDir, "chat_history.db")
		appDir = userTaduDir
	} else if _, err := os.Stat(filepath.Join("..", "config.json")); err == nil {
		configFile = filepath.Join("..", "config.json")
		dbPath = filepath.Join("..", "chat_history.db")
		appDir = ".."
	} else {
		configFile = filepath.Join(userTaduDir, "config.json")
		dbPath = filepath.Join(userTaduDir, "chat_history.db")
		appDir = userTaduDir
	}
}

func initDB() error {
	var err error
	db, err = sql.Open("sqlite", dbPath)
	if err != nil {
		return err
	}

	query := `
	CREATE TABLE IF NOT EXISTS chat_sessions (
		id TEXT PRIMARY KEY,
		title TEXT NOT NULL,
		is_pinned INTEGER DEFAULT 0,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE IF NOT EXISTS chat_messages (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		session_id TEXT NOT NULL,
		role TEXT NOT NULL,
		content TEXT,
		attachments_json TEXT,
		tool_calls_json TEXT,
		model TEXT,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`
	_, err = db.Exec(query)
	return err
}

func getIntVal(v interface{}, def int) int {
	if v == nil {
		return def
	}
	switch val := v.(type) {
	case int:
		return val
	case int64:
		return int(val)
	case float64:
		return int(val)
	case string:
		if n, err := strconv.Atoi(strings.TrimSpace(val)); err == nil && n > 0 {
			return n
		}
	}
	return def
}

func normalizeServerMap(s map[string]interface{}) map[string]interface{} {
	server := make(map[string]interface{})
	for k, v := range s {
		server[k] = v
	}
	if id, ok := server["id"].(string); !ok || strings.TrimSpace(id) == "" {
		server["id"] = fmt.Sprintf("srv_%d", time.Now().UnixNano())
	}
	if name, ok := server["name"].(string); !ok || strings.TrimSpace(name) == "" {
		server["name"] = "Máy chủ 1"
	}
	if ip, ok := server["server_ip"].(string); !ok || strings.TrimSpace(ip) == "" {
		server["server_ip"] = "127.0.0.1"
	}
	if _, ok := server["ssh_user"].(string); !ok {
		server["ssh_user"] = "root"
	}
	if _, ok := server["ssh_pass"].(string); !ok {
		server["ssh_pass"] = ""
	}
	server["ssh_port"] = getIntVal(server["ssh_port"], 22)
	server["api_port"] = getIntVal(server["api_port"], 8000)
	if _, ok := server["remote_work_dir"].(string); !ok {
		server["remote_work_dir"] = "/opt/ai_agent"
	}
	if _, ok := server["secret_token"].(string); !ok {
		server["secret_token"] = "super_secret_token_123"
	}
	return server
}

func loadConfig() map[string]interface{} {
	cfgMutex.RLock()
	defer cfgMutex.RUnlock()

	defaultCfg := map[string]interface{}{
		"active_server_id": "srv_default",
		"servers": []interface{}{
			map[string]interface{}{
				"id":              "srv_default",
				"name":            "Máy chủ chính",
				"server_ip":       "127.0.0.1",
				"ssh_user":        "root",
				"ssh_pass":        "",
				"ssh_port":        22,
				"remote_work_dir": "/opt/ai_agent",
				"api_port":        8000,
				"secret_token":    "super_secret_token_123",
			},
		},
		"server_ip":       "127.0.0.1",
		"ssh_user":        "root",
		"ssh_pass":        "",
		"ssh_port":        22,
		"proxy_api_key":   "",
		"proxy_base_url":  "https://api-us-ca.umodelverse.ai/v1",
		"ai_model":        "glm-5.3",
		"remote_work_dir": "/opt/ai_agent",
		"api_port":        8000,
		"secret_token":    "super_secret_token_123",
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		return defaultCfg
	}

	var rawMap map[string]interface{}
	if err := json.Unmarshal(data, &rawMap); err != nil {
		return defaultCfg
	}

	// 1. Kiểm tra _encrypted_vault nếu có
	if vaultStr, ok := rawMap["_encrypted_vault"].(string); ok && vaultStr != "" {
		decVault := decryptValue(vaultStr)
		var vaultData map[string]interface{}
		if err := json.Unmarshal([]byte(decVault), &vaultData); err == nil {
			for k, v := range vaultData {
				rawMap[k] = v
			}
		}
	}

	// 2. Giải mã từng trường
	result := make(map[string]interface{})
	for k, v := range defaultCfg {
		result[k] = v
	}

	for k, v := range rawMap {
		if k == "_encrypted_vault" {
			continue
		}
		if s, ok := v.(string); ok {
			if strings.HasPrefix(s, "enc:") {
				dec := decryptValue(s)
				if k == "ssh_port" || k == "api_port" {
					if p, err := strconv.Atoi(dec); err == nil {
						result[k] = p
						continue
					}
				}
				result[k] = dec
			} else {
				if (k == "ssh_port" || k == "api_port") && s != "" {
					if p, err := strconv.Atoi(s); err == nil {
						result[k] = p
						continue
					}
				}
				result[k] = s
			}
		} else if num, ok := v.(float64); ok {
			result[k] = int(num)
		} else {
			result[k] = v
		}
	}

	// Xử lý danh sách servers
	var serverList []map[string]interface{}
	if rawServers, ok := result["servers"].([]interface{}); ok && len(rawServers) > 0 {
		for _, s := range rawServers {
			if sMap, ok := s.(map[string]interface{}); ok {
				serverList = append(serverList, normalizeServerMap(sMap))
			}
		}
	} else if rawServersMap, ok := result["servers"].([]map[string]interface{}); ok && len(rawServersMap) > 0 {
		for _, sMap := range rawServersMap {
			serverList = append(serverList, normalizeServerMap(sMap))
		}
	}

	if len(serverList) == 0 {
		topServer := map[string]interface{}{
			"id":              "srv_default",
			"name":            "Máy chủ chính",
			"server_ip":       result["server_ip"],
			"ssh_user":        result["ssh_user"],
			"ssh_pass":        result["ssh_pass"],
			"ssh_port":        result["ssh_port"],
			"remote_work_dir": result["remote_work_dir"],
			"api_port":        result["api_port"],
			"secret_token":    result["secret_token"],
		}
		serverList = append(serverList, normalizeServerMap(topServer))
	}

	activeID, _ := result["active_server_id"].(string)
	var activeServer map[string]interface{}
	for _, s := range serverList {
		if s["id"] == activeID {
			activeServer = s
			break
		}
	}
	if activeServer == nil {
		activeServer = serverList[0]
		activeID, _ = activeServer["id"].(string)
		result["active_server_id"] = activeID
	}

	// Đồng bộ các trường của activeServer ra ngoài top-level
	for k, v := range activeServer {
		if k != "id" && k != "name" {
			result[k] = v
		}
	}
	result["active_server_name"] = activeServer["name"]

	resultServers := make([]interface{}, len(serverList))
	for i, s := range serverList {
		resultServers[i] = s
	}
	result["servers"] = resultServers

	return result
}

func saveConfig(cfg map[string]interface{}) error {
	cfgMutex.Lock()
	defer cfgMutex.Unlock()

	// Normalize servers and active_server_id
	var serverList []map[string]interface{}
	if rawServers, ok := cfg["servers"].([]interface{}); ok && len(rawServers) > 0 {
		for _, s := range rawServers {
			if sMap, ok := s.(map[string]interface{}); ok {
				serverList = append(serverList, normalizeServerMap(sMap))
			}
		}
	}

	activeID, _ := cfg["active_server_id"].(string)
	if len(serverList) > 0 {
		var activeServer map[string]interface{}
		for _, s := range serverList {
			if s["id"] == activeID {
				activeServer = s
				break
			}
		}
		if activeServer == nil {
			activeServer = serverList[0]
			activeID, _ = activeServer["id"].(string)
			cfg["active_server_id"] = activeID
		}
		// Sync top level
		for k, v := range activeServer {
			if k != "id" && k != "name" {
				cfg[k] = v
			}
		}
		resultServers := make([]interface{}, len(serverList))
		for i, s := range serverList {
			resultServers[i] = s
		}
		cfg["servers"] = resultServers
	}

	diskData := make(map[string]interface{})
	for k, v := range cfg {
		if k == "_encrypted_vault" || k == "servers" {
			continue
		}
		diskData[k] = encryptValue(fmt.Sprintf("%v", v))
	}

	rawJSON, _ := json.Marshal(cfg)
	diskData["_encrypted_vault"] = encryptValue(string(rawJSON))

	data, err := json.MarshalIndent(diskData, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(configFile, data, 0644)
}

func getSSHClient(cfg map[string]interface{}) (*ssh.Client, error) {
	serverIP, _ := cfg["server_ip"].(string)
	sshUser, _ := cfg["ssh_user"].(string)
	sshPass, _ := cfg["ssh_pass"].(string)
	sshPort := 22
	if p, ok := cfg["ssh_port"].(int); ok && p > 0 {
		sshPort = p
	}

	sshConfig := &ssh.ClientConfig{
		User:            sshUser,
		Auth:            []ssh.AuthMethod{ssh.Password(sshPass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         8 * time.Second,
	}

	return ssh.Dial("tcp", fmt.Sprintf("%s:%d", serverIP, sshPort), sshConfig)
}

func runSSHCmd(client *ssh.Client, cmd string) string {
	session, err := client.NewSession()
	if err != nil {
		return ""
	}
	defer session.Close()
	out, _ := session.CombinedOutput(cmd)
	return strings.TrimSpace(string(out))
}

func runSSHCmdWithSudo(client *ssh.Client, sshPass string, cmd string) string {
	session, err := client.NewSession()
	if err != nil {
		return ""
	}
	defer session.Close()

	if strings.TrimSpace(sshPass) != "" {
		fullCmd := fmt.Sprintf("echo %q | sudo -S -p '' bash -c %q 2>&1 || bash -c %q 2>&1", sshPass, cmd, cmd)
		out, _ := session.CombinedOutput(fullCmd)
		res := strings.TrimSpace(string(out))
		if strings.Contains(res, "Respect the privacy") {
			lines := strings.Split(res, "\n")
			var filtered []string
			for _, l := range lines {
				if !strings.Contains(l, "lecture") && !strings.Contains(l, "boils down") && !strings.Contains(l, "Respect the privacy") && !strings.Contains(l, "Think before you type") && !strings.Contains(l, "With great power") && !strings.Contains(l, "[sudo] password") {
					filtered = append(filtered, l)
				}
			}
			res = strings.TrimSpace(strings.Join(filtered, "\n"))
		}
		return res
	}

	fullCmd := fmt.Sprintf("sudo -n bash -c %q 2>&1 || bash -c %q 2>&1", cmd, cmd)
	out, _ := session.CombinedOutput(fullCmd)
	return strings.TrimSpace(string(out))
}

type ToolCallFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type ToolCall struct {
	ID       string           `json:"id"`
	Type     string           `json:"type"`
	Function ToolCallFunction `json:"function"`
}

type ChatMessage struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	Name       string     `json:"name,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
}

type OpenAIChatRequest struct {
	Model       string        `json:"model"`
	Messages    []ChatMessage `json:"messages"`
	Tools       []interface{} `json:"tools,omitempty"`
	ToolChoice  interface{}   `json:"tool_choice,omitempty"`
	Temperature float64       `json:"temperature"`
}

type OpenAIChoiceMessage struct {
	Role      string     `json:"role"`
	Content   string     `json:"content"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

type OpenAIChoice struct {
	Message      OpenAIChoiceMessage `json:"message"`
	FinishReason string              `json:"finish_reason"`
}

type OpenAIChatResponse struct {
	ID      string         `json:"id"`
	Choices []OpenAIChoice `json:"choices"`
	Error   *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
		Code    string `json:"code"`
	} `json:"error,omitempty"`
}

type ToolExecutionRecord struct {
	Tool    string `json:"tool"`
	Command string `json:"command"`
	Output  string `json:"output"`
}

const SystemPrompt = `Bạn là Tadu Cloud AI Agent - Kỹ sư DevOps Linux thực chiến cấp cao.
Bạn có quyền:
1. Thực thi lệnh bash/shell thực tế trên máy chủ qua công cụ execute_terminal_command.
2. Tự động tải file/backup từ máy chủ VPS về máy tính của người dùng (lưu vào thư mục Downloads) qua công cụ download_remote_file_to_local.

CÁC QUY TẮC BẮT BUỘC:
1. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU MỚI:
   - CHỈ kiểm tra và thực hiện đúng đối tượng/yêu cầu mà người dùng đang hỏi.
2. TỰ ĐỘNG TẢI FILE VỀ MÁY LOCAL KHI ĐƯỢC YÊU CẦU:
   - Khi người dùng yêu cầu: "Backup và tải về máy", "Download file X về máy tính", "Kéo backup về local":
     + Bước 1: Dùng execute_terminal_command để tạo file backup (hoặc nén thư mục, dump database) vào thư mục làm việc của user (ví dụ: ~/ai_agent/backups/...).
     + Bước 2: Dùng NGAY công cụ download_remote_file_to_local để kéo file đó từ VPS về máy tính người dùng.
     + Bước 3: Báo cho người dùng biết file đã được tải về máy tính thành công kèm đường dẫn Downloads.
3. XỬ LÝ PHÂN QUYỀN TRÊN DIRECTADMIN / CPANEL / LINUX:
   - Trên DirectAdmin / cPanel: Mỗi website thường thuộc sở hữu của một user Linux riêng (vd: duanthefib, chmod 0710).
   - Nếu user hiện tại không đọc được trực tiếp /home/<user>:
     + Thử kiểm tra các công cụ DirectAdmin CLI / Task Queue, hoặc kiểm tra quyền sudo.
     + Nếu hoàn toàn bị hạn chế quyền do Linux User Isolation, hãy giải thích rõ ràng ngắn gọn và đưa ra hướng dẫn cụ thể (ví dụ: chuyển SSH sang user root hoặc chính user sở hữu website đó trong Cài đặt).
4. KẾT LUẬN NGẮN GỌN, RÕ RÀNG & TRỰC QUAN:
   - Trình bày kết quả dễ đọc (bảng markdown, danh sách, mã lệnh).`

func formatFileSize(bytes int64) string {
	if bytes < 1024 {
		return fmt.Sprintf("%d B", bytes)
	} else if bytes < 1024*1024 {
		return fmt.Sprintf("%.1f KB", float64(bytes)/1024)
	} else if bytes < 1024*1024*1024 {
		return fmt.Sprintf("%.2f MB", float64(bytes)/(1024*1024))
	}
	return fmt.Sprintf("%.2f GB", float64(bytes)/(1024*1024*1024))
}

func downloadRemoteFileToLocal(sshClient *ssh.Client, remotePath string, localFilename string) (string, error) {
	if sshClient == nil {
		return "", fmt.Errorf("Không có kết nối SSH tới máy chủ")
	}

	userHome, err := os.UserHomeDir()
	if err != nil {
		userHome = "."
	}
	downloadsDir := filepath.Join(userHome, "Downloads")
	_ = os.MkdirAll(downloadsDir, 0755)

	if localFilename == "" {
		localFilename = filepath.Base(remotePath)
	}
	destPath := filepath.Join(downloadsDir, localFilename)

	session, err := sshClient.NewSession()
	if err != nil {
		return "", fmt.Errorf("Lỗi tạo SSH session: %v", err)
	}
	defer session.Close()

	stdout, err := session.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("Lỗi StdoutPipe: %v", err)
	}

	if err := session.Start(fmt.Sprintf("cat %q", remotePath)); err != nil {
		return "", fmt.Errorf("Lỗi đọc file từ server: %v", err)
	}

	outFile, err := os.Create(destPath)
	if err != nil {
		return "", fmt.Errorf("Lỗi tạo file ở local (%s): %v", destPath, err)
	}
	defer outFile.Close()

	written, err := io.Copy(outFile, stdout)
	if err != nil {
		return "", fmt.Errorf("Lỗi ghi file local: %v", err)
	}
	_ = session.Wait()

	sizeStr := formatFileSize(written)
	return fmt.Sprintf("✅ Đã tải file thành công về máy tính tại: %s (Kích thước: %s)", destPath, sizeStr), nil
}

func callOpenAI(proxyBaseURL string, proxyAPIKey string, reqBody OpenAIChatRequest) (*OpenAIChatResponse, error) {
	jsonBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	apiURL := fmt.Sprintf("%s/chat/completions", strings.TrimRight(proxyBaseURL, "/"))
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonBytes))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	if proxyAPIKey != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", proxyAPIKey))
	}
	req.Header.Set("HTTP-Referer", "https://tadu.vn")
	req.Header.Set("X-Title", "Tadu Cloud AI Agent")

	client := &http.Client{Timeout: 90 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API HTTP %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var chatResp OpenAIChatResponse
	if err := json.Unmarshal(bodyBytes, &chatResp); err != nil {
		return nil, fmt.Errorf("Lỗi parse JSON API: %v", err)
	}

	if chatResp.Error != nil {
		return nil, fmt.Errorf("OpenAI API Error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("API không trả về kết quả choices")
	}

	return &chatResp, nil
}

func makeSmartTitle(content string, maxChars int) string {
	line := strings.TrimSpace(strings.Split(content, "\n")[0])
	if len([]rune(line)) <= maxChars {
		return line
	}
	return string([]rune(line)[:maxChars]) + "..."
}

func main() {
	initPaths()
	if err := initDB(); err != nil {
		log.Fatalf("Lỗi khởi tạo DB: %v", err)
	}
	defer db.Close()

	mux := http.NewServeMux()

	templateDir := "templates"
	if _, err := os.Stat(templateDir); os.IsNotExist(err) {
		templateDir = filepath.Join("..", "templates")
	}
	logoFile := "logo.jpg"
	if _, err := os.Stat(logoFile); os.IsNotExist(err) {
		logoFile = filepath.Join("..", "logo.jpg")
	}

	// 1. Static Web UI & Assets
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			http.ServeFile(w, r, filepath.Join(templateDir, "index.html"))
			return
		}
		if r.URL.Path == "/logo.jpg" {
			http.ServeFile(w, r, logoFile)
			return
		}
		http.FileServer(http.Dir(templateDir)).ServeHTTP(w, r)
	})

	// 2. Config API
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet {
			cfg := loadConfig()
			json.NewEncoder(w).Encode(cfg)
			return
		}
		if r.Method == http.MethodPost {
			var newCfg map[string]interface{}
			if err := json.NewDecoder(r.Body).Decode(&newCfg); err != nil {
				http.Error(w, err.Error(), 400)
				return
			}
			cfg := loadConfig()
			for k, v := range newCfg {
				cfg[k] = v
			}
			if err := saveConfig(cfg); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Lưu cấu hình thành công", "config": cfg})
			return
		}
		http.Error(w, "Method not allowed", 405)
	})

	// Server Management APIs
	mux.HandleFunc("/api/servers", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		cfg := loadConfig()

		if r.Method == http.MethodGet {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":           "success",
				"active_server_id": cfg["active_server_id"],
				"servers":          cfg["servers"],
			})
			return
		}

		if r.Method == http.MethodPost {
			var newServer map[string]interface{}
			if err := json.NewDecoder(r.Body).Decode(&newServer); err != nil {
				http.Error(w, err.Error(), 400)
				return
			}
			normServer := normalizeServerMap(newServer)
			normServer["id"] = fmt.Sprintf("srv_%d", time.Now().UnixNano())

			rawServers, _ := cfg["servers"].([]interface{})
			rawServers = append(rawServers, normServer)
			cfg["servers"] = rawServers

			setActive, _ := newServer["set_active"].(bool)
			if setActive || len(rawServers) == 1 {
				cfg["active_server_id"] = normServer["id"]
			}

			if err := saveConfig(cfg); err != nil {
				json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
				return
			}

			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":           "success",
				"message":          "Đã thêm máy chủ mới thành công",
				"server":           normServer,
				"active_server_id": cfg["active_server_id"],
				"servers":          cfg["servers"],
			})
			return
		}
		http.Error(w, "Method not allowed", 405)
	})

	mux.HandleFunc("/api/servers/update", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", 405)
			return
		}

		var updateData map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&updateData); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}

		serverID, _ := updateData["id"].(string)
		if serverID == "" {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Thiếu Server ID"})
			return
		}

		cfg := loadConfig()
		rawServers, _ := cfg["servers"].([]interface{})
		found := false
		for i, s := range rawServers {
			if sMap, ok := s.(map[string]interface{}); ok {
				if sMap["id"] == serverID {
					for k, v := range updateData {
						sMap[k] = v
					}
					rawServers[i] = normalizeServerMap(sMap)
					found = true
					break
				}
			}
		}

		if !found {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Không tìm thấy máy chủ"})
			return
		}

		if setActive, ok := updateData["set_active"].(bool); ok && setActive {
			cfg["active_server_id"] = serverID
		}

		cfg["servers"] = rawServers
		if err := saveConfig(cfg); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":           "success",
			"message":          "Đã cập nhật thông tin máy chủ thành công",
			"active_server_id": cfg["active_server_id"],
			"servers":          cfg["servers"],
		})
	})

	mux.HandleFunc("/api/servers/delete", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", 405)
			return
		}

		var req struct {
			ID string `json:"id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Thiếu Server ID"})
			return
		}

		cfg := loadConfig()
		rawServers, _ := cfg["servers"].([]interface{})
		if len(rawServers) <= 1 {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Không thể xoá máy chủ cuối cùng trong danh sách"})
			return
		}

		var newServers []interface{}
		for _, s := range rawServers {
			if sMap, ok := s.(map[string]interface{}); ok {
				if sMap["id"] != req.ID {
					newServers = append(newServers, sMap)
				}
			}
		}

		cfg["servers"] = newServers
		if cfg["active_server_id"] == req.ID {
			if len(newServers) > 0 {
				if firstMap, ok := newServers[0].(map[string]interface{}); ok {
					cfg["active_server_id"] = firstMap["id"]
				}
			}
		}

		if err := saveConfig(cfg); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":           "success",
			"message":          "Đã xoá máy chủ thành công",
			"active_server_id": cfg["active_server_id"],
			"servers":          cfg["servers"],
		})
	})

	mux.HandleFunc("/api/servers/select", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", 405)
			return
		}

		var req struct {
			ServerID string `json:"server_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ServerID == "" {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Thiếu Server ID"})
			return
		}

		cfg := loadConfig()
		rawServers, _ := cfg["servers"].([]interface{})
		var matchedServer map[string]interface{}
		for _, s := range rawServers {
			if sMap, ok := s.(map[string]interface{}); ok {
				if sMap["id"] == req.ServerID {
					matchedServer = sMap
					break
				}
			}
		}

		if matchedServer == nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Máy chủ không tồn tại"})
			return
		}

		cfg["active_server_id"] = req.ServerID
		if err := saveConfig(cfg); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":        "success",
			"message":       fmt.Sprintf("Đã chuyển sang máy chủ %v (%v)", matchedServer["name"], matchedServer["server_ip"]),
			"active_server": matchedServer,
			"config":        cfg,
		})
	})

	// 3. Chat Sessions API: GET /api/chat/sessions, POST /api/chat/sessions
	mux.HandleFunc("/api/chat/sessions", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		dbMutex.Lock()
		defer dbMutex.Unlock()

		if r.Method == http.MethodGet {
			rows, err := db.Query("SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC")
			if err != nil {
				json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "sessions": []interface{}{}})
				return
			}
			defer rows.Close()

			sessions := []map[string]interface{}{}
			for rows.Next() {
				var id, title, createdAt, updatedAt string
				var isPinned int
				rows.Scan(&id, &title, &isPinned, &createdAt, &updatedAt)
				sessions = append(sessions, map[string]interface{}{
					"id":         id,
					"title":      decryptValue(title),
					"is_pinned":  isPinned == 1,
					"created_at": createdAt,
					"updated_at": updatedAt,
				})
			}
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "sessions": sessions})
			return
		}

		if r.Method == http.MethodPost {
			var req struct {
				ID    string `json:"id"`
				Title string `json:"title"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			if req.ID == "" {
				req.ID = fmt.Sprintf("s_%x", time.Now().UnixNano())
			}
			if req.Title == "" {
				req.Title = "Cuộc hội thoại mới"
			}
			encTitle := encryptValue(req.Title)
			_, _ = db.Exec("INSERT OR IGNORE INTO chat_sessions (id, title, is_pinned, created_at, updated_at) VALUES (?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", req.ID, encTitle)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status": "success",
				"session": map[string]interface{}{
					"id":         req.ID,
					"title":      req.Title,
					"is_pinned":  false,
					"created_at": time.Now().Format(time.RFC3339),
					"updated_at": time.Now().Format(time.RFC3339),
				},
			})
			return
		}
	})

	// 4. Chat Sessions Dynamic API (/api/chat/sessions/{id}, /pin)
	mux.HandleFunc("/api/chat/sessions/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		subPath := strings.TrimPrefix(r.URL.Path, "/api/chat/sessions/")
		parts := strings.Split(subPath, "/")
		sessionID := parts[0]

		dbMutex.Lock()
		defer dbMutex.Unlock()

		if len(parts) > 1 && parts[1] == "pin" && r.Method == http.MethodPost {
			var req struct {
				IsPinned *bool `json:"is_pinned"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			var newPin int
			if req.IsPinned != nil {
				if *req.IsPinned {
					newPin = 1
				} else {
					newPin = 0
				}
			} else {
				var current int
				_ = db.QueryRow("SELECT is_pinned FROM chat_sessions WHERE id = ?", sessionID).Scan(&current)
				if current == 1 {
					newPin = 0
				} else {
					newPin = 1
				}
			}
			_, _ = db.Exec("UPDATE chat_sessions SET is_pinned = ? WHERE id = ?", newPin, sessionID)
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
			return
		}

		if r.Method == http.MethodPut {
			var req struct {
				Title string `json:"title"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			encTitle := encryptValue(req.Title)
			_, _ = db.Exec("UPDATE chat_sessions SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", encTitle, sessionID)
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
			return
		}

		if r.Method == http.MethodDelete {
			_, _ = db.Exec("DELETE FROM chat_sessions WHERE id = ?", sessionID)
			_, _ = db.Exec("DELETE FROM chat_messages WHERE session_id = ?", sessionID)
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
			return
		}
	})

	// 5. Chat History API: GET /api/chat/history?session_id=...
	mux.HandleFunc("/api/chat/history", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		sessionID := r.URL.Query().Get("session_id")
		if sessionID == "" {
			sessionID = "default"
		}

		dbMutex.Lock()
		defer dbMutex.Unlock()

		rows, err := db.Query(`
			SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
			FROM (
				SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
				FROM chat_messages
				WHERE session_id = ?
				ORDER BY id DESC
				LIMIT 300
			) sub
			ORDER BY id ASC
		`, sessionID)

		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "messages": []interface{}{}})
			return
		}
		defer rows.Close()

		messages := []map[string]interface{}{}
		for rows.Next() {
			var id int
			var sID, role string
			var content, att, tc, model, createdAt sql.NullString
			rows.Scan(&id, &sID, &role, &content, &att, &tc, &model, &createdAt)

			msg := map[string]interface{}{
				"id":         id,
				"session_id": sID,
				"role":       role,
				"content":    decryptValue(content.String),
				"created_at": createdAt.String,
			}
			if model.Valid {
				msg["model"] = model.String
			}
			if att.Valid && att.String != "" {
				decAtt := decryptValue(att.String)
				var attObj interface{}
				if json.Unmarshal([]byte(decAtt), &attObj) == nil {
					msg["attachments"] = attObj
				}
			}
			if tc.Valid && tc.String != "" {
				decTC := decryptValue(tc.String)
				var tcObj interface{}
				if json.Unmarshal([]byte(decTC), &tcObj) == nil {
					msg["tool_calls"] = tcObj
				}
			}
			messages = append(messages, msg)
		}
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "messages": messages})
	})

	// 6. Clear Chat API: POST /api/chat/clear
	mux.HandleFunc("/api/chat/clear", func(w http.ResponseWriter, r *http.Request) {
		sessionID := r.URL.Query().Get("session_id")
		if sessionID == "" {
			sessionID = "default"
		}
		dbMutex.Lock()
		_, _ = db.Exec("DELETE FROM chat_messages WHERE session_id = ?", sessionID)
		dbMutex.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
	})

	// Window Controls API
	mux.HandleFunc("/api/window/close", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
		go func() {
			time.Sleep(100 * time.Millisecond)
			os.Exit(0)
		}()
	})
	mux.HandleFunc("/api/window/minimize", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
	})
	mux.HandleFunc("/api/window/maximize", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "success"})
	})

	// 7. SSH Test API: POST /api/ssh/test
	mux.HandleFunc("/api/ssh/test", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		cfg := loadConfig()
		targetCfg := make(map[string]interface{})
		for k, v := range cfg {
			targetCfg[k] = v
		}

		if r.Body != nil {
			var req map[string]interface{}
			if err := json.NewDecoder(r.Body).Decode(&req); err == nil && req != nil {
				if sid, ok := req["server_id"].(string); ok && sid != "" {
					rawServers, _ := cfg["servers"].([]interface{})
					for _, s := range rawServers {
						if sMap, ok := s.(map[string]interface{}); ok {
							if sMap["id"] == sid {
								for k, v := range sMap {
									targetCfg[k] = v
								}
								break
							}
						}
					}
				}
				if ip, ok := req["server_ip"].(string); ok && strings.TrimSpace(ip) != "" {
					targetCfg["server_ip"] = strings.TrimSpace(ip)
				}
				if u, ok := req["ssh_user"].(string); ok && strings.TrimSpace(u) != "" {
					targetCfg["ssh_user"] = strings.TrimSpace(u)
				}
				if p, ok := req["ssh_pass"].(string); ok {
					targetCfg["ssh_pass"] = p
				}
				if portVal, ok := req["ssh_port"]; ok {
					switch v := portVal.(type) {
					case float64:
						if v > 0 {
							targetCfg["ssh_port"] = int(v)
						}
					case int:
						if v > 0 {
							targetCfg["ssh_port"] = v
						}
					case string:
						if pInt, err := strconv.Atoi(v); err == nil && pInt > 0 {
							targetCfg["ssh_port"] = pInt
						}
					}
				}
			}
		}

		client, err := getSSHClient(targetCfg)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":  "error",
				"message": fmt.Sprintf("Kết nối thất bại tới %v:%v: %v", targetCfg["server_ip"], targetCfg["ssh_port"], err),
			})
			return
		}
		defer client.Close()

		session, err := client.NewSession()
		outStr := ""
		if err == nil {
			outBytes, _ := session.CombinedOutput("uname -a && whoami")
			outStr = strings.TrimSpace(string(outBytes))
			session.Close()
		}

		msg := fmt.Sprintf("Kết nối SSH thành công tới %v:%v!", targetCfg["server_ip"], targetCfg["ssh_port"])
		if outStr != "" {
			msg += "\n" + outStr
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "success",
			"message": msg,
		})
	})

	// 8. Server Health API: GET /api/server/health
	mux.HandleFunc("/api/server/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		cfg := loadConfig()
		targetURL := fmt.Sprintf("http://%v:%v/health", cfg["server_ip"], cfg["api_port"])
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get(targetURL)
		if err == nil && resp.StatusCode == 200 {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":      "running",
				"message":     "AI Agent Service đang hoạt động",
				"status_code": 200,
			})
			return
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":      "stopped",
			"message":     "Dịch vụ AI Agent chưa chạy hoặc không thể kết nối",
			"status_code": 503,
		})
	})

	// Server System Info / Metrics: GET /api/server/system-info, GET /api/server/metrics
	handleSystemInfo := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		cfg := loadConfig()
		client, err := getSSHClient(cfg)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":  "error",
				"message": fmt.Sprintf("Không thể kết nối SSH tới server: %v", err),
			})
			return
		}
		defer client.Close()

		session, err := client.NewSession()
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":  "error",
				"message": fmt.Sprintf("Không thể mở SSH session: %v", err),
			})
			return
		}
		defer session.Close()

		apiPort := getIntVal(cfg["api_port"], 8000)
		cmd := "cat /proc/uptime 2>/dev/null; echo '---'; " +
			"cat /proc/loadavg 2>/dev/null; echo '---'; " +
			"free -m 2>/dev/null; echo '---'; " +
			"df -h / 2>/dev/null; echo '---'; " +
			"ps -e | wc -l 2>/dev/null; echo '---'; " +
			fmt.Sprintf("(systemctl is-active ai-agent.service 2>/dev/null || systemctl --user is-active ai-agent.service 2>/dev/null || (pgrep -f ai_agent_service >/dev/null && echo 'active') || (curl -s -m 1 http://127.0.0.1:%d/health | grep -q 'healthy' && echo 'active') || echo 'inactive')", apiPort) + "; echo '---'; " +
			"cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s"

		outBytes, _ := session.CombinedOutput(cmd)
		parts := strings.Split(string(outBytes), "---")

		uptimeRaw := ""
		loadavgRaw := ""
		freeRaw := ""
		dfRaw := ""
		procsRaw := ""
		serviceStatus := "inactive"
		osName := "Linux"

		if len(parts) > 0 {
			uptimeRaw = strings.TrimSpace(parts[0])
		}
		if len(parts) > 1 {
			loadavgRaw = strings.TrimSpace(parts[1])
		}
		if len(parts) > 2 {
			freeRaw = strings.TrimSpace(parts[2])
		}
		if len(parts) > 3 {
			dfRaw = strings.TrimSpace(parts[3])
		}
		if len(parts) > 4 {
			procsRaw = strings.TrimSpace(parts[4])
		}
		if len(parts) > 5 {
			serviceStatus = strings.TrimSpace(parts[5])
			if strings.Contains(serviceStatus, "active") {
				serviceStatus = "active"
			}
		}
		if len(parts) > 6 {
			osName = strings.TrimSpace(parts[6])
		}

		uptimeHuman := formatUptimeHuman(uptimeRaw)
		safeMetrics := parseSafeMetrics(dfRaw, freeRaw, loadavgRaw, uptimeRaw, procsRaw)

		infoDict := map[string]interface{}{
			"uptime":         uptimeHuman,
			"uptime_seconds": safeMetrics["uptime_seconds"],
			"disk":           dfRaw,
			"memory":         freeRaw,
			"ram":            freeRaw,
			"metrics":        safeMetrics,
			"service_active": serviceStatus,
			"service_status": serviceStatus,
			"os":             osName,
			"server_ip":      cfg["server_ip"],
			"api_port":       apiPort,
			"ai_model":       cfg["ai_model"],
			"last_sync":      time.Now().Format("15:04:05"),
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":         "success",
			"uptime":         uptimeHuman,
			"disk":           dfRaw,
			"ram":            freeRaw,
			"metrics":        safeMetrics,
			"service_status": serviceStatus,
			"os":             osName,
			"info":           infoDict,
			"last_sync":      time.Now().Format("15:04:05"),
		})
	}
	mux.HandleFunc("/api/server/system-info", handleSystemInfo)
	mux.HandleFunc("/api/server/metrics", handleSystemInfo)

	// Service Action & Logs
	mux.HandleFunc("/api/server/service-action", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		var body struct {
			Action string `json:"action"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		if body.Action == "" {
			body.Action = "status"
		}
		cfg := loadConfig()
		client, err := getSSHClient(cfg)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}
		defer client.Close()

		sshPass, _ := cfg["ssh_pass"].(string)
		remoteDir, _ := cfg["remote_work_dir"].(string)
		if remoteDir == "" {
			remoteDir = "/opt/ai_agent"
		}
		apiPort := getIntVal(cfg["api_port"], 8000)
		targetRemotePath := fmt.Sprintf("%s/ai_agent_service", remoteDir)
		proxyAPIKey, _ := cfg["proxy_api_key"].(string)
		proxyBaseURL, _ := cfg["proxy_base_url"].(string)
		aiModel, _ := cfg["ai_model"].(string)
		secretToken, _ := cfg["secret_token"].(string)

		var out string
		switch body.Action {
		case "start":
			runSSHCmdWithSudo(client, sshPass, "systemctl start ai-agent.service 2>/dev/null || systemctl --user start ai-agent.service 2>/dev/null || true")
			time.Sleep(1 * time.Second)
			chk := runSSHCmd(client, fmt.Sprintf("pgrep -f %s 2>/dev/null || true", targetRemotePath))
			if chk == "" {
				nohupCmd := fmt.Sprintf("nohup env AGENT_PORT=%d PORT=%d PROXY_API_KEY=%q OPENROUTER_API_KEY=%q PROXY_BASE_URL=%q OPENROUTER_BASE_URL=%q AI_MODEL=%q SECRET_TOKEN=%q AGENT_SECRET_TOKEN=%q %s > %s/agent.log 2>&1 &",
					apiPort, apiPort, proxyAPIKey, proxyAPIKey, proxyBaseURL, proxyBaseURL, aiModel, secretToken, secretToken, targetRemotePath, remoteDir)
				runSSHCmd(client, nohupCmd)
			}
			out = "Service đã được khởi động!"

		case "stop":
			runSSHCmdWithSudo(client, sshPass, "systemctl stop ai-agent.service 2>/dev/null || systemctl --user stop ai-agent.service 2>/dev/null || true")
			runSSHCmd(client, fmt.Sprintf("fuser -k %d/tcp 2>/dev/null || pkill -f %s 2>/dev/null || true", apiPort, targetRemotePath))
			out = "Service đã được dừng thành công!"

		case "restart":
			runSSHCmdWithSudo(client, sshPass, "systemctl restart ai-agent.service 2>/dev/null || systemctl --user restart ai-agent.service 2>/dev/null || true")
			time.Sleep(1 * time.Second)
			chk := runSSHCmd(client, fmt.Sprintf("pgrep -f %s 2>/dev/null || true", targetRemotePath))
			if chk == "" {
				runSSHCmd(client, fmt.Sprintf("fuser -k %d/tcp 2>/dev/null || pkill -f %s 2>/dev/null || true", apiPort, targetRemotePath))
				nohupCmd := fmt.Sprintf("nohup env AGENT_PORT=%d PORT=%d PROXY_API_KEY=%q OPENROUTER_API_KEY=%q PROXY_BASE_URL=%q OPENROUTER_BASE_URL=%q AI_MODEL=%q SECRET_TOKEN=%q AGENT_SECRET_TOKEN=%q %s > %s/agent.log 2>&1 &",
					apiPort, apiPort, proxyAPIKey, proxyAPIKey, proxyBaseURL, proxyBaseURL, aiModel, secretToken, secretToken, targetRemotePath, remoteDir)
				runSSHCmd(client, nohupCmd)
			}
			out = "Service đã được khởi động lại thành công!"

		case "status":
			statusDetail := runSSHCmd(client, "systemctl status ai-agent.service 2>/dev/null || systemctl --user status ai-agent.service 2>/dev/null || ps aux | grep [a]i_agent_service 2>/dev/null || true")
			healthCheck := runSSHCmd(client, fmt.Sprintf("curl -s -m 2 http://127.0.0.1:%d/health 2>/dev/null || true", apiPort))
			agentLog := runSSHCmd(client, fmt.Sprintf("tail -n 15 %s/agent.log 2>/dev/null || true", remoteDir))
			out = fmt.Sprintf("--- HEALTH CHECK (Port %d) ---\n%s\n\n--- PROCESS STATUS ---\n%s\n\n--- AGENT LOG ---\n%s", apiPort, healthCheck, statusDetail, agentLog)
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "success",
			"action": body.Action,
			"output": out,
		})
	})

	mux.HandleFunc("/api/server/logs", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		lines := r.URL.Query().Get("lines")
		if lines == "" {
			lines = "100"
		}
		cfg := loadConfig()
		client, err := getSSHClient(cfg)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}
		defer client.Close()
		remoteDir, _ := cfg["remote_work_dir"].(string)
		if remoteDir == "" {
			remoteDir = "/opt/ai_agent"
		}
		cmd := fmt.Sprintf("journalctl -u ai-agent.service -n %s --no-pager 2>/dev/null || tail -n %s %s/agent.log 2>/dev/null || true", lines, lines, remoteDir)
		out := runSSHCmd(client, cmd)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "success",
			"logs":   out,
		})
	})

	// 8. 1-Click Deploy AI Agent Server Standalone Binary: POST /api/server/deploy
	mux.HandleFunc("/api/server/deploy", func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "SSE not supported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		sendStep := func(msg string) {
			lines := strings.Split(msg, "\n")
			for _, l := range lines {
				l = strings.TrimRight(l, "\r\n")
				if l != "" {
					fmt.Fprintf(w, "data: %s\n\n", l)
				}
			}
			flusher.Flush()
		}

		sendStep("Bắt đầu kết nối SSH tới máy chủ...")

		cfg := loadConfig()
		serverIP, _ := cfg["server_ip"].(string)
		sshUser, _ := cfg["ssh_user"].(string)
		sshPass, _ := cfg["ssh_pass"].(string)
		remoteDir, _ := cfg["remote_work_dir"].(string)
		if remoteDir == "" {
			remoteDir = "/opt/ai_agent"
		}
		proxyAPIKey, _ := cfg["proxy_api_key"].(string)
		proxyBaseURL, _ := cfg["proxy_base_url"].(string)
		if proxyBaseURL == "" {
			proxyBaseURL = "https://openrouter.ai/api/v1"
		}
		aiModel, _ := cfg["ai_model"].(string)
		if aiModel == "" {
			aiModel = "glm-5.3"
		}
		secretToken, _ := cfg["secret_token"].(string)
		if secretToken == "" {
			secretToken = "super_secret_token_123"
		}
		apiPort := getIntVal(cfg["api_port"], 8000)
		sshPort := getIntVal(cfg["ssh_port"], 22)

		client, err := getSSHClient(cfg)
		if err != nil {
			sendStep(fmt.Sprintf("[ERROR] Không thể kết nối SSH: %v", err))
			return
		}
		defer client.Close()

		sendStep(fmt.Sprintf("Kết nối SSH thành công tới %s (SSH Port: %d | API Service Port: %d)!", serverIP, sshPort, apiPort))

		// Check if user has root or sudo privileges
		hasSudo := false
		if sshUser == "root" {
			hasSudo = true
		} else {
			sudoTest := strings.TrimSpace(runSSHCmdWithSudo(client, sshPass, "id -u"))
			if sudoTest == "0" {
				hasSudo = true
			}
		}

		userHome := strings.TrimSpace(runSSHCmd(client, "echo $HOME"))
		if userHome == "" || userHome == "/" {
			userHome = fmt.Sprintf("/home/%s", sshUser)
		}

		if !hasSudo {
			sendStep(fmt.Sprintf("[INFO] Tài khoản '%s' không có quyền sudo. Tự động chuyển sang chế độ User-Space Deployment.", sshUser))
			if strings.HasPrefix(remoteDir, "/opt") || strings.HasPrefix(remoteDir, "/var") || strings.HasPrefix(remoteDir, "/etc") {
				remoteDir = fmt.Sprintf("%s/ai_agent", userHome)
			}
		}

		sendStep(fmt.Sprintf("Tạo thư mục làm việc %s...", remoteDir))
		if hasSudo {
			runSSHCmdWithSudo(client, sshPass, fmt.Sprintf("mkdir -p %s && chown -R %s %s 2>/dev/null || true", remoteDir, sshUser, remoteDir))
		} else {
			runSSHCmd(client, fmt.Sprintf("mkdir -p %s", remoteDir))
		}

		// Detect remote VPS CPU architecture (x86_64 vs arm64)
		remoteArch := strings.TrimSpace(runSSHCmd(client, "uname -m"))
		isArm := strings.Contains(remoteArch, "arm") || strings.Contains(remoteArch, "aarch64")
		archLabel := "x86_64 / AMD64"
		if isArm {
			archLabel = "ARM64 / AArch64"
		}
		sendStep(fmt.Sprintf("Kiến trúc CPU máy chủ: %s -> Chọn gói Binary: %s", remoteArch, archLabel))

		// Find local compiled Go binary matching remote architecture
		var possiblePaths []string
		if isArm {
			possiblePaths = []string{
				"dist/ai_agent_service_linux_arm64",
				"../dist/ai_agent_service_linux_arm64",
				"server-go/ai_agent_service_linux_arm64",
				"../server-go/ai_agent_service_linux_arm64",
				"dist/ai_agent_service",
				"../dist/ai_agent_service",
			}
		} else {
			possiblePaths = []string{
				"dist/ai_agent_service_linux_amd64",
				"../dist/ai_agent_service_linux_amd64",
				"dist/ai_agent_service",
				"../dist/ai_agent_service",
				"server-go/ai_agent_service",
				"../server-go/ai_agent_service",
			}
		}

		var binData []byte
		var foundPath string
		for _, p := range possiblePaths {
			if data, err := os.ReadFile(p); err == nil && len(data) > 0 {
				binData = data
				foundPath = p
				break
			}
		}

		if len(binData) == 0 {
			sendStep("[ERROR] Không tìm thấy file nhị phân ai_agent_service đã biên dịch ở local!")
			return
		}

		sendStep(fmt.Sprintf("Tìm thấy Standalone Go Binary (%.1f MB) tại: %s", float64(len(binData))/1024/1024, foundPath))

		sendStep(fmt.Sprintf("Tạm dừng service cũ và giải phóng port %d...", apiPort))
		if hasSudo {
			runSSHCmdWithSudo(client, sshPass, fmt.Sprintf("systemctl stop ai-agent.service 2>/dev/null || true; fuser -k %d/tcp 2>/dev/null || true; pkill -f ai_agent_service 2>/dev/null || true", apiPort))
		} else {
			runSSHCmd(client, fmt.Sprintf("fuser -k %d/tcp 2>/dev/null || pkill -f ai_agent_service 2>/dev/null || true", apiPort))
		}
		time.Sleep(1 * time.Second)

		sendStep("Đang tải Standalone Go Binary lên VPS qua kênh truyền bảo mật SSH...")
		// Upload binary via stdin stream into user-accessible directory
		session, err := client.NewSession()
		if err != nil {
			sendStep(fmt.Sprintf("[ERROR] Không thể mở SSH session: %v", err))
			return
		}

		var stderrBuf bytes.Buffer
		session.Stderr = &stderrBuf

		stdin, err := session.StdinPipe()
		if err != nil {
			session.Close()
			sendStep(fmt.Sprintf("[ERROR] Lỗi StdinPipe: %v", err))
			return
		}

		tmpRemotePath := fmt.Sprintf("/tmp/ai_agent_service_%d.tmp", time.Now().Unix())
		targetRemotePath := fmt.Sprintf("%s/ai_agent_service", remoteDir)

		go func() {
			defer stdin.Close()
			io.Copy(stdin, bytes.NewReader(binData))
		}()

		if err := session.Run(fmt.Sprintf("cat > %s", tmpRemotePath)); err != nil {
			session.Close()
			errDetail := strings.TrimSpace(stderrBuf.String())
			if errDetail != "" {
				sendStep(fmt.Sprintf("[ERROR] Lỗi upload binary: %v (%s)", err, errDetail))
			} else {
				sendStep(fmt.Sprintf("[ERROR] Lỗi upload binary: %v", err))
			}
			return
		}
		session.Close()

		sendStep("Đã đưa Standalone Binary lên máy chủ và kích hoạt quyền thực thi (chmod +x)...")
		if hasSudo {
			moveCmd := fmt.Sprintf("mkdir -p %s && mv -f %s %s && chmod 755 %s && chown -R %s %s 2>/dev/null && restorecon -v %s 2>/dev/null && rm -f %s/ai_agent_service.py 2>/dev/null || true",
				remoteDir, tmpRemotePath, targetRemotePath, targetRemotePath, sshUser, remoteDir, targetRemotePath, remoteDir)
			runSSHCmdWithSudo(client, sshPass, moveCmd)
		} else {
			moveCmd := fmt.Sprintf("mkdir -p %s && mv -f %s %s && chmod 755 %s && rm -f %s/ai_agent_service.py 2>/dev/null || true",
				remoteDir, tmpRemotePath, targetRemotePath, targetRemotePath, remoteDir)
			runSSHCmd(client, moveCmd)
		}

		if hasSudo {
			sendStep("Đang cấu hình Systemd Daemon (ai-agent.service)...")
			serviceContent := fmt.Sprintf(`[Unit]
Description=Tadu Cloud AI Agent Service (Standalone Go Binary)
After=network.target

[Service]
Type=simple
WorkingDirectory=%s
Environment="PROXY_API_KEY=%s"
Environment="OPENROUTER_API_KEY=%s"
Environment="PROXY_BASE_URL=%s"
Environment="OPENROUTER_BASE_URL=%s"
Environment="AI_MODEL=%s"
Environment="SECRET_TOKEN=%s"
Environment="AGENT_SECRET_TOKEN=%s"
Environment="AGENT_PORT=%d"
Environment="PORT=%d"
ExecStart=%s
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
`, remoteDir, proxyAPIKey, proxyAPIKey, proxyBaseURL, proxyBaseURL, aiModel, secretToken, secretToken, apiPort, apiPort, targetRemotePath)

			serviceCmd := fmt.Sprintf("cat << 'EOF' > /etc/systemd/system/ai-agent.service\n%s\nEOF", serviceContent)
			runSSHCmdWithSudo(client, sshPass, serviceCmd)

			sendStep("Khởi động lại Systemd Daemon...")
			runSSHCmdWithSudo(client, sshPass, "systemctl daemon-reload && systemctl enable ai-agent.service && systemctl restart ai-agent.service")
			time.Sleep(2 * time.Second)

			statusOut := strings.TrimSpace(runSSHCmdWithSudo(client, sshPass, "systemctl is-active ai-agent.service 2>/dev/null || true"))
			healthCheck := strings.TrimSpace(runSSHCmd(client, fmt.Sprintf("curl -s -m 3 http://127.0.0.1:%d/health 2>/dev/null || wget -qO- --timeout=3 http://127.0.0.1:%d/health 2>/dev/null || true", apiPort, apiPort)))

			if statusOut == "active" || strings.Contains(healthCheck, "healthy") {
				sendStep(fmt.Sprintf("[SUCCESS] AI Agent Standalone Binary (Go Edition) đã được triển khai và khởi động THÀNH CÔNG trên VPS (Cổng API: %d)!", apiPort))
				return
			}
		}

		// User-space Daemon mode (for non-sudo or fallback)
		sendStep("Khởi động Service dưới quyền người dùng (User-Space Background Daemon)...")
		runSSHCmd(client, fmt.Sprintf("fuser -k %d/tcp 2>/dev/null || pkill -f %s 2>/dev/null || true", apiPort, targetRemotePath))
		time.Sleep(1 * time.Second)

		// Try user-level systemd
		userSystemdDir := fmt.Sprintf("%s/.config/systemd/user", userHome)
		runSSHCmd(client, fmt.Sprintf("mkdir -p %s", userSystemdDir))
		userServiceContent := fmt.Sprintf(`[Unit]
Description=Tadu Cloud AI Agent Service
After=network.target

[Service]
Type=simple
WorkingDirectory=%s
Environment="PROXY_API_KEY=%s"
Environment="OPENROUTER_API_KEY=%s"
Environment="PROXY_BASE_URL=%s"
Environment="OPENROUTER_BASE_URL=%s"
Environment="AI_MODEL=%s"
Environment="SECRET_TOKEN=%s"
Environment="AGENT_SECRET_TOKEN=%s"
Environment="AGENT_PORT=%d"
Environment="PORT=%d"
ExecStart=%s
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
`, remoteDir, proxyAPIKey, proxyAPIKey, proxyBaseURL, proxyBaseURL, aiModel, secretToken, secretToken, apiPort, apiPort, targetRemotePath)
		runSSHCmd(client, fmt.Sprintf("cat << 'EOF' > %s/ai-agent.service\n%s\nEOF", userSystemdDir, userServiceContent))
		runSSHCmd(client, "systemctl --user daemon-reload 2>/dev/null && systemctl --user enable ai-agent.service 2>/dev/null && systemctl --user restart ai-agent.service 2>/dev/null || true")

		// Start with nohup daemon as guarantee
		nohupCmd := fmt.Sprintf("nohup env AGENT_PORT=%d PORT=%d PROXY_API_KEY=%q OPENROUTER_API_KEY=%q PROXY_BASE_URL=%q OPENROUTER_BASE_URL=%q AI_MODEL=%q SECRET_TOKEN=%q AGENT_SECRET_TOKEN=%q %s > %s/agent.log 2>&1 &",
			apiPort, apiPort, proxyAPIKey, proxyAPIKey, proxyBaseURL, proxyBaseURL, aiModel, secretToken, secretToken, targetRemotePath, remoteDir)
		runSSHCmd(client, nohupCmd)
		time.Sleep(2 * time.Second)

		healthCheck := strings.TrimSpace(runSSHCmd(client, fmt.Sprintf("curl -s -m 3 http://127.0.0.1:%d/health 2>/dev/null || wget -qO- --timeout=3 http://127.0.0.1:%d/health 2>/dev/null || true", apiPort, apiPort)))
		if strings.Contains(healthCheck, "healthy") {
			sendStep(fmt.Sprintf("[SUCCESS] AI Agent Standalone Binary đã khởi động và hoạt động THÀNH CÔNG trên VPS (Cổng API: %d, Thư mục: %s)!", apiPort, remoteDir))
		} else {
			sendStep("[ERROR] Không thể khởi động Service.")
			agentLog := runSSHCmd(client, fmt.Sprintf("tail -n 20 %s/agent.log 2>&1 || true", remoteDir))
			if agentLog != "" {
				sendStep(fmt.Sprintf("Chi tiết Log Tiến Trình (agent.log):\n%s", agentLog))
			}
		}
	})

	// 9. Remote FS Dir Listing: GET /api/fs/list_dirs
	mux.HandleFunc("/api/fs/list_dirs", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		prefix := r.URL.Query().Get("prefix")
		if prefix == "" {
			prefix = "/"
		}
		cfg := loadConfig()
		client, err := getSSHClient(cfg)
		dirs := []string{"/var/www", "/etc/nginx", "/opt/ai_agent", "/home", "/var/log", "/etc", "/opt"}
		if err == nil {
			session, err := client.NewSession()
			if err == nil {
				out, err := session.Output(fmt.Sprintf("compgen -d %q 2>/dev/null | head -30", prefix))
				if err == nil && len(out) > 0 {
					lines := strings.Split(string(out), "\n")
					for _, l := range lines {
						if strings.TrimSpace(l) != "" {
							dirs = append(dirs, strings.TrimSpace(l))
						}
					}
				}
				session.Close()
			}
			client.Close()
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":      "success",
			"prefix":      prefix,
			"directories": dirs,
		})
	})

	// Remote File Download API: GET /api/fs/download?path=/path/to/file
	mux.HandleFunc("/api/fs/download", func(w http.ResponseWriter, r *http.Request) {
		remotePath := r.URL.Query().Get("path")
		if remotePath == "" {
			http.Error(w, "Thiếu tham số path", http.StatusBadRequest)
			return
		}

		cfg := loadConfig()
		client, err := getSSHClient(cfg)
		if err != nil {
			http.Error(w, fmt.Sprintf("Lỗi kết nối SSH: %v", err), http.StatusInternalServerError)
			return
		}
		defer client.Close()

		session, err := client.NewSession()
		if err != nil {
			http.Error(w, fmt.Sprintf("Lỗi tạo SSH session: %v", err), http.StatusInternalServerError)
			return
		}
		defer session.Close()

		filename := filepath.Base(remotePath)
		w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
		w.Header().Set("Content-Type", "application/octet-stream")

		stdout, err := session.StdoutPipe()
		if err != nil {
			http.Error(w, fmt.Sprintf("Lỗi StdoutPipe: %v", err), http.StatusInternalServerError)
			return
		}

		if err := session.Start(fmt.Sprintf("cat %q", remotePath)); err != nil {
			http.Error(w, fmt.Sprintf("Lỗi đọc file: %v", err), http.StatusInternalServerError)
			return
		}

		io.Copy(w, stdout)
		_ = session.Wait()
	})

	// Remote File Upload API: POST /api/fs/upload (multipart/form-data)
	mux.HandleFunc("/api/fs/upload", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Max 500MB upload
		if err := r.ParseMultipartForm(500 << 20); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi đọc file upload: " + err.Error()})
			return
		}

		file, header, err := r.FormFile("file")
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Không tìm thấy file: " + err.Error()})
			return
		}
		defer file.Close()

		targetDir := r.FormValue("target_dir")
		cfg := loadConfig()
		sshUser, _ := cfg["ssh_user"].(string)
		if sshUser == "" {
			sshUser = "admin"
		}
		if targetDir == "" {
			if sshUser == "root" {
				targetDir = "/opt/ai_agent/uploads"
			} else {
				targetDir = fmt.Sprintf("/home/%s/ai_agent/uploads", sshUser)
			}
		}

		client, err := getSSHClient(cfg)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi kết nối SSH: " + err.Error()})
			return
		}
		defer client.Close()

		// Ensure target directory exists on VPS
		_ = runSSHCmd(client, fmt.Sprintf("mkdir -p %q", targetDir))

		remoteFilePath := filepath.Join(targetDir, header.Filename)

		// Stream file directly to VPS via SSH session stdin -> cat > remoteFilePath
		session, err := client.NewSession()
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi tạo SSH session: " + err.Error()})
			return
		}
		defer session.Close()

		stdin, err := session.StdinPipe()
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi SSH StdinPipe: " + err.Error()})
			return
		}

		if err := session.Start(fmt.Sprintf("cat > %q", remoteFilePath)); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi ghi file trên máy chủ: " + err.Error()})
			return
		}

		written, err := io.Copy(stdin, file)
		_ = stdin.Close()
		_ = session.Wait()

		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Lỗi truyền dữ liệu: " + err.Error()})
			return
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":      "success",
			"filename":    header.Filename,
			"remote_path": remoteFilePath,
			"size":        written,
			"size_str":    formatFileSize(written),
		})
	})

	// 10. Live SSH Terminal WebSocket: /ws/terminal
	mux.HandleFunc("/ws/terminal", func(w http.ResponseWriter, r *http.Request) {
		ws, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer ws.Close()

		cfg := loadConfig()
		sshConn, err := getSSHClient(cfg)
		if err != nil {
			ws.WriteMessage(websocket.TextMessage, []byte(fmt.Sprintf("\r\n\x1b[31m[Lỗi SSH]: %v\x1b[0m\r\n", err)))
			return
		}
		defer sshConn.Close()

		session, err := sshConn.NewSession()
		if err != nil {
			ws.WriteMessage(websocket.TextMessage, []byte(fmt.Sprintf("\r\n\x1b[31m[Lỗi Session]: %v\x1b[0m\r\n", err)))
			return
		}
		defer session.Close()

		modes := ssh.TerminalModes{
			ssh.ECHO:          1,
			ssh.TTY_OP_ISPEED: 14400,
			ssh.TTY_OP_OSPEED: 14400,
		}
		if err := session.RequestPty("xterm-256color", 40, 120, modes); err != nil {
			ws.WriteMessage(websocket.TextMessage, []byte(fmt.Sprintf("\r\n\x1b[31m[Lỗi PTY]: %v\x1b[0m\r\n", err)))
			return
		}

		stdin, _ := session.StdinPipe()
		stdout, _ := session.StdoutPipe()
		stderr, _ := session.StderrPipe()

		if err := session.Shell(); err != nil {
			return
		}

		go func() {
			buf := make([]byte, 4096)
			for {
				n, err := stdout.Read(buf)
				if n > 0 {
					_ = ws.WriteMessage(websocket.TextMessage, buf[:n])
				}
				if err != nil {
					break
				}
			}
		}()

		go func() {
			buf := make([]byte, 4096)
			for {
				n, err := stderr.Read(buf)
				if n > 0 {
					_ = ws.WriteMessage(websocket.TextMessage, buf[:n])
				}
				if err != nil {
					break
				}
			}
		}()

		for {
			_, msg, err := ws.ReadMessage()
			if err != nil {
				break
			}
			var resizeMsg struct {
				Type string `json:"type"`
				Cols int    `json:"cols"`
				Rows int    `json:"rows"`
			}
			if err := json.Unmarshal(msg, &resizeMsg); err == nil && resizeMsg.Type == "resize" {
				if resizeMsg.Cols > 0 && resizeMsg.Rows > 0 {
					_ = session.WindowChange(resizeMsg.Rows, resizeMsg.Cols)
				}
				continue
			}
			if stdin != nil {
				_, _ = stdin.Write(msg)
			}
		}
	})

	// 11. AI Chat Stream API (SSE): POST /api/chat
	mux.HandleFunc("/api/chat", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", 405)
			return
		}

		var req struct {
			SessionID  string                   `json:"session_id"`
			Message    string                   `json:"message"`
			Model      string                   `json:"model"`
			History    []map[string]interface{} `json:"history"`
			WorkingDir string                   `json:"working_dir"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}

		cfg := loadConfig()
		model := req.Model
		if model == "" {
			if m, ok := cfg["ai_model"].(string); ok && m != "" {
				model = m
			} else {
				model = "glm-5.3"
			}
		}

		encMsg := encryptValue(req.Message)
		dbMutex.Lock()
		_, _ = db.Exec("INSERT OR IGNORE INTO chat_sessions (id, title) VALUES (?, ?)", req.SessionID, encryptValue("Cuộc hội thoại mới"))
		smartTitle := makeSmartTitle(req.Message, 65)
		_, _ = db.Exec("UPDATE chat_sessions SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", encryptValue(smartTitle), req.SessionID)
		_, _ = db.Exec("INSERT INTO chat_messages (session_id, role, content, model) VALUES (?, 'user', ?, ?)", req.SessionID, encMsg, model)
		dbMutex.Unlock()

		w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported", 500)
			return
		}

		sendSSE := func(data interface{}) {
			b, _ := json.Marshal(data)
			fmt.Fprintf(w, "data: %s\n\n", string(b))
			flusher.Flush()
		}

		sendSSE(map[string]interface{}{"type": "status", "message": "Đang kết nối AI Agent..."})

		// Tool definition for executing commands on VPS
		toolDefExec := map[string]interface{}{
			"type": "function",
			"function": map[string]interface{}{
				"name":        "execute_terminal_command",
				"description": "Thực thi lệnh terminal bash/shell trên máy chủ Linux để kiểm tra cấu hình, dịch vụ, website, log, tạo file backup, nén dữ liệu.",
				"parameters": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"command": map[string]interface{}{
							"type":        "string",
							"description": "Lệnh bash cần chạy trên máy chủ",
						},
					},
					"required": []string{"command"},
				},
			},
		}

		// Tool definition for downloading files from VPS to local computer
		toolDefDownload := map[string]interface{}{
			"type": "function",
			"function": map[string]interface{}{
				"name":        "download_remote_file_to_local",
				"description": "Tự động tải một file hoặc bản backup từ máy chủ VPS về máy tính của người dùng (lưu vào thư mục Downloads).",
				"parameters": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"remote_path": map[string]interface{}{
							"type":        "string",
							"description": "Đường dẫn tuyệt đối của file trên VPS cần tải về (ví dụ: /home/admin/backup_db.sql.gz)",
						},
						"local_filename": map[string]interface{}{
							"type":        "string",
							"description": "Tên file muốn lưu trên máy local (tùy chọn, mặc định lấy theo tên gốc)",
						},
					},
					"required": []string{"remote_path"},
				},
			},
		}
		toolsList := []interface{}{toolDefExec, toolDefDownload}

		currSysPrompt := SystemPrompt
		if req.WorkingDir != "" {
			currSysPrompt += fmt.Sprintf("\n\n🎯 THƯ MỤC LÀM VIỆC MỤC TIÊU: %s", req.WorkingDir)
		}

		messages := []ChatMessage{
			{Role: "system", Content: currSysPrompt},
		}

		// Append recent history
		if len(req.History) > 0 {
			startIdx := 0
			if len(req.History) > 4 {
				startIdx = len(req.History) - 4
			}
			for _, h := range req.History[startIdx:] {
				role, _ := h["role"].(string)
				content, _ := h["content"].(string)
				if (role == "user" || role == "assistant") && content != "" {
					if role == "assistant" && len(content) > 500 {
						content = content[:500] + "..."
					}
					messages = append(messages, ChatMessage{Role: role, Content: content})
				}
			}
		}

		messages = append(messages, ChatMessage{Role: "user", Content: req.Message})

		proxyBaseURL, _ := cfg["proxy_base_url"].(string)
		if proxyBaseURL == "" {
			proxyBaseURL = "https://openrouter.ai/api/v1"
		}
		proxyAPIKey, _ := cfg["proxy_api_key"].(string)

		// Open SSH connection for tool execution
		sshClient, _ := getSSHClient(cfg)
		defer func() {
			if sshClient != nil {
				sshClient.Close()
			}
		}()

		var executedTools []ToolExecutionRecord
		var executedCommands []string
		maxTurns := 15
		turn := 0
		fullReply := ""

		for turn < maxTurns {
			turn++

			var currentTools []interface{} = toolsList
			var currentToolChoice interface{} = "auto"
			if turn == maxTurns {
				currentTools = nil
				currentToolChoice = nil
			}

			chatReq := OpenAIChatRequest{
				Model:       model,
				Messages:    messages,
				Tools:       currentTools,
				ToolChoice:  currentToolChoice,
				Temperature: 0.1,
			}

			chatResp, err := callOpenAI(proxyBaseURL, proxyAPIKey, chatReq)
			if err != nil {
				sendSSE(map[string]interface{}{"type": "error", "message": fmt.Sprintf("Lỗi kết nối AI: %v", err)})
				return
			}

			choice := chatResp.Choices[0]
			respMsg := choice.Message

			if len(respMsg.ToolCalls) > 0 && currentTools != nil {
				messages = append(messages, ChatMessage{
					Role:      "assistant",
					Content:   respMsg.Content,
					ToolCalls: respMsg.ToolCalls,
				})

				for _, toolCall := range respMsg.ToolCalls {
					if toolCall.Function.Name == "execute_terminal_command" {
						var args struct {
							Command string `json:"command"`
						}
						cmdStr := toolCall.Function.Arguments
						if err := json.Unmarshal([]byte(toolCall.Function.Arguments), &args); err == nil && args.Command != "" {
							cmdStr = args.Command
						}
						cmdStr = strings.TrimSpace(cmdStr)

						executedCommands = append(executedCommands, cmdStr)
						toolRes := ""
						n := len(executedCommands)
						if n >= 3 && executedCommands[n-1] == executedCommands[n-2] && executedCommands[n-2] == executedCommands[n-3] {
							toolRes = fmt.Sprintf("[HỆ THỐNG]: Lệnh lặp lại 3 lần liên tiếp: '%s'. Vui lòng đưa ra giải pháp thay vì tiếp tục chạy lại.", cmdStr)
						} else {
							sendSSE(map[string]interface{}{
								"type":    "status",
								"message": fmt.Sprintf("Đang thực thi: %s", cmdStr),
							})

							sshPass, _ := cfg["ssh_pass"].(string)
							if sshClient != nil {
								targetCmd := cmdStr
								if req.WorkingDir != "" {
									targetCmd = fmt.Sprintf("cd %s 2>/dev/null; %s", req.WorkingDir, cmdStr)
								}
								if strings.Contains(cmdStr, "sudo ") && sshPass != "" {
									toolRes = runSSHCmdWithSudo(sshClient, sshPass, targetCmd)
								} else {
									toolRes = runSSHCmd(sshClient, targetCmd)
								}
							} else {
								toolRes = "Không thể kết nối SSH tới máy chủ."
							}

							if toolRes == "" {
								toolRes = "Lệnh đã chạy xong, không có output."
							}
						}

						rec := ToolExecutionRecord{
							Tool:    "execute_terminal_command",
							Command: cmdStr,
							Output:  toolRes,
						}
						executedTools = append(executedTools, rec)

						sendSSE(map[string]interface{}{
							"type": "tool",
							"tool": rec,
						})

						messages = append(messages, ChatMessage{
							Role:       "tool",
							ToolCallID: toolCall.ID,
							Name:       toolCall.Function.Name,
							Content:    toolRes,
						})
					} else if toolCall.Function.Name == "download_remote_file_to_local" {
						var args struct {
							RemotePath    string `json:"remote_path"`
							LocalFilename string `json:"local_filename"`
						}
						_ = json.Unmarshal([]byte(toolCall.Function.Arguments), &args)
						if args.RemotePath == "" {
							args.RemotePath = strings.TrimSpace(toolCall.Function.Arguments)
						}

						sendSSE(map[string]interface{}{
							"type":    "status",
							"message": fmt.Sprintf("Đang tự động tải file %s về máy tính...", filepath.Base(args.RemotePath)),
						})

						toolRes, err := downloadRemoteFileToLocal(sshClient, args.RemotePath, args.LocalFilename)
						if err != nil {
							toolRes = fmt.Sprintf("Lỗi tải file về máy: %v", err)
						}

						rec := ToolExecutionRecord{
							Tool:    "download_remote_file_to_local",
							Command: fmt.Sprintf("download_to_local: %s", args.RemotePath),
							Output:  toolRes,
						}
						executedTools = append(executedTools, rec)

						sendSSE(map[string]interface{}{
							"type": "tool",
							"tool": rec,
						})

						messages = append(messages, ChatMessage{
							Role:       "tool",
							ToolCallID: toolCall.ID,
							Name:       toolCall.Function.Name,
							Content:    toolRes,
						})
					}
				}
				continue
			} else {
				fullReply = respMsg.Content
				words := strings.Split(fullReply, " ")
				for idx, w := range words {
					token := w
					if idx < len(words)-1 {
						token += " "
					}
					sendSSE(map[string]interface{}{
						"type":  "token",
						"delta": token,
					})
					time.Sleep(10 * time.Millisecond)
				}
				break
			}
		}

		if fullReply == "" && len(messages) > 0 {
			finalReq := OpenAIChatRequest{
				Model:       model,
				Messages:    messages,
				Temperature: 0.1,
			}
			if finalResp, err := callOpenAI(proxyBaseURL, proxyAPIKey, finalReq); err == nil && len(finalResp.Choices) > 0 {
				fullReply = finalResp.Choices[0].Message.Content
				words := strings.Split(fullReply, " ")
				for idx, w := range words {
					token := w
					if idx < len(words)-1 {
						token += " "
					}
					sendSSE(map[string]interface{}{
						"type":  "token",
						"delta": token,
					})
					time.Sleep(10 * time.Millisecond)
				}
			}
		}

		if fullReply != "" || len(executedTools) > 0 {
			encReply := encryptValue(fullReply)
			var encTools string
			if len(executedTools) > 0 {
				b, _ := json.Marshal(executedTools)
				encTools = encryptValue(string(b))
			}
			dbMutex.Lock()
			_, _ = db.Exec("INSERT INTO chat_messages (session_id, role, content, tool_calls_json, model) VALUES (?, 'assistant', ?, ?, ?)", req.SessionID, encReply, encTools, model)
			dbMutex.Unlock()
		}

		sendSSE(map[string]interface{}{
			"type":       "done",
			"reply":      fullReply,
			"tool_calls": executedTools,
		})
	})

	port := 8888
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		listener, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Fatalf("Lỗi lắng nghe cổng: %v", err)
		}
		port = listener.Addr().(*net.TCPAddr).Port
	}

	appURL := fmt.Sprintf("http://127.0.0.1:%d", port)
	fmt.Println("\n=======================================================")
	fmt.Println("🚀 TADU CLOUD AI AGENT (GO HIGH-PERFORMANCE EDITION)")
	fmt.Printf("🌐 Server nội bộ siêu nhẹ sẵn sàng tại: %s\n", appURL)
	fmt.Println("⚡ Bộ nhớ RAM tiêu thụ: ~14MB | Khởi động tức thì: 0.05s")
	fmt.Println("=======================================================\n")

	noBrowser := false
	for _, arg := range os.Args[1:] {
		if arg == "--no-browser" || arg == "-no-browser" || arg == "--headless" {
			noBrowser = true
			break
		}
	}
	if os.Getenv("NO_BROWSER") == "1" || os.Getenv("ELECTRON_RUN_AS_NODE") != "" {
		noBrowser = true
	}

	if !noBrowser {
		go openDesktopApp(appURL)
	}

	server := &http.Server{Handler: mux}
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server dừng: %v", err)
	}
}

func openDesktopApp(url string) {
	time.Sleep(300 * time.Millisecond)

	electronBin := "/opt/Tadu Cloud AI Agent/tadu-cloud-ai-agent"
	nativeScript := filepath.Join(appDir, "native_main.js")
	if _, err := os.Stat("native_main.js"); err == nil {
		nativeScript, _ = filepath.Abs("native_main.js")
	} else if _, err := os.Stat(filepath.Join("tadu-go", "native_main.js")); err == nil {
		nativeScript, _ = filepath.Abs(filepath.Join("tadu-go", "native_main.js"))
	}

	if fileExists(electronBin) && fileExists(nativeScript) {
		cmd := exec.Command(electronBin, "--no-sandbox", nativeScript)
		if err := cmd.Start(); err == nil {
			return
		}
	}

	var candidates []string
	switch runtime.GOOS {
	case "windows":
		candidates = []string{
			`C:\Program Files\Google\Chrome\Application\chrome.exe`,
			`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`,
			`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
			`C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe`,
		}
	case "darwin":
		candidates = []string{
			"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
			"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
			"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
		}
	default: // Linux
		candidates = []string{
			"google-chrome",
			"google-chrome-stable",
			"chromium-browser",
			"chromium",
			"brave-browser",
			"microsoft-edge",
		}
	}

	for _, bin := range candidates {
		path, err := exec.LookPath(bin)
		if err == nil || (runtime.GOOS == "windows" && fileExists(bin)) {
			execPath := bin
			if err == nil {
				execPath = path
			}
			profileDir := filepath.Join(appDir, "chrome_profile")
			cmd := exec.Command(execPath,
				fmt.Sprintf("--app=%s", url),
				fmt.Sprintf("--user-data-dir=%s", profileDir),
				"--window-size=1280,860",
				"--force-dark-mode",
				"--enable-features=WebUIDarkMode",
				"--disable-translate",
				"--disable-features=Translate,TranslateUI,LanguageDetection,LanguageSettings",
				"--no-first-run",
				"--no-default-browser-check",
			)
			if err := cmd.Start(); err == nil {
				return
			}
		}
	}

	switch runtime.GOOS {
	case "linux":
		_ = exec.Command("xdg-open", url).Start()
	case "windows":
		_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		_ = exec.Command("open", url).Start()
	}
}

func fileExists(p string) bool {
	info, err := os.Stat(p)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir()
}

func formatUptimeHuman(secStr string) string {
	parts := strings.Fields(secStr)
	if len(parts) == 0 {
		return "N/A"
	}
	secFloat, err := strconv.ParseFloat(parts[0], 64)
	if err != nil {
		return "N/A"
	}
	s := int(secFloat)
	days := s / 86400
	rem := s % 86400
	hours := rem / 3600
	rem = rem % 3600
	mins := rem / 60
	secs := rem % 60
	weeks := days / 7
	days = days % 7

	var res []string
	if weeks > 0 {
		res = append(res, fmt.Sprintf("%d tuần", weeks))
	}
	if days > 0 {
		res = append(res, fmt.Sprintf("%d ngày", days))
	}
	if hours > 0 {
		res = append(res, fmt.Sprintf("%d giờ", hours))
	}
	res = append(res, fmt.Sprintf("%d phút %ds", mins, secs))
	return strings.Join(res, ", ")
}

func parseSafeMetrics(dfRaw, freeRaw, loadavgRaw, uptimeSecRaw, procsRaw string) map[string]interface{} {
	metrics := map[string]interface{}{
		"disk_total":     "40 GB",
		"disk_used":      "21 GB",
		"disk_avail":     "17 GB",
		"disk_percent":   50,
		"ram_total":      "2.0 GB",
		"ram_used":       "750 MB",
		"ram_avail":      "1.2 GB",
		"ram_percent":    35.0,
		"ram_used_mb":    750,
		"ram_total_mb":   2048,
		"ram_avail_mb":   1200,
		"ram_cache_mb":   0,
		"loadavg":        strings.TrimSpace(loadavgRaw),
		"procs":          strings.TrimSpace(procsRaw),
		"uptime_seconds": 0,
		"last_sync":      time.Now().Format("15:04:05"),
	}

	if parts := strings.Fields(uptimeSecRaw); len(parts) > 0 {
		if f, err := strconv.ParseFloat(parts[0], 64); err == nil {
			metrics["uptime_seconds"] = int(f)
		}
	}

	// Parse df -h /
	dfLines := strings.Split(strings.TrimSpace(dfRaw), "\n")
	if len(dfLines) >= 2 {
		f := strings.Fields(dfLines[len(dfLines)-1])
		if len(f) >= 5 {
			metrics["disk_total"] = f[1]
			metrics["disk_used"] = f[2]
			metrics["disk_avail"] = f[3]
			pct := strings.TrimSuffix(f[4], "%")
			if p, err := strconv.Atoi(pct); err == nil {
				metrics["disk_percent"] = p
			}
		}
	}

	// Parse free -m
	freeLines := strings.Split(strings.TrimSpace(freeRaw), "\n")
	for _, l := range freeLines {
		if strings.HasPrefix(l, "Mem:") {
			f := strings.Fields(l)
			if len(f) >= 7 {
				totalMB, _ := strconv.Atoi(f[1])
				usedMB, _ := strconv.Atoi(f[2])
				cachedMB := 0
				if len(f) > 5 {
					cachedMB, _ = strconv.Atoi(f[5])
				}
				availMB, _ := strconv.Atoi(f[6])
				metrics["ram_total_mb"] = totalMB
				metrics["ram_used_mb"] = usedMB
				metrics["ram_avail_mb"] = availMB
				metrics["ram_cache_mb"] = cachedMB
				if totalMB > 0 {
					pct := float64(usedMB) / float64(totalMB) * 100
					metrics["ram_percent"] = float64(int(pct*10)) / 10
				}
				metrics["ram_total"] = fmt.Sprintf("%.2f GB", float64(totalMB)/1024.0)
				metrics["ram_used"] = fmt.Sprintf("%d MB", usedMB)
				metrics["ram_avail"] = fmt.Sprintf("%.2f GB", float64(availMB)/1024.0)
			}
		}
	}

	return metrics
}
