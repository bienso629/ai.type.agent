package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Config holding server environment settings
type Config struct {
	SecretToken  string
	ProxyBaseURL string
	ProxyAPIKey  string
	AIModel      string
	Port         string
}

func loadConfig() Config {
	secretToken := os.Getenv("SECRET_TOKEN")
	if secretToken == "" {
		secretToken = os.Getenv("AGENT_SECRET_TOKEN")
	}
	if secretToken == "" {
		secretToken = "super_secret_token_123"
	}

	proxyBaseURL := os.Getenv("PROXY_BASE_URL")
	if proxyBaseURL == "" {
		proxyBaseURL = os.Getenv("OPENROUTER_BASE_URL")
	}
	if proxyBaseURL == "" {
		proxyBaseURL = "https://openrouter.ai/api/v1"
	}

	proxyAPIKey := os.Getenv("PROXY_API_KEY")
	if proxyAPIKey == "" {
		proxyAPIKey = os.Getenv("OPENROUTER_API_KEY")
	}

	aiModel := os.Getenv("AI_MODEL")
	if aiModel == "" {
		aiModel = "glm-5.3"
	}

	port := os.Getenv("AGENT_PORT")
	if port == "" {
		port = os.Getenv("PORT")
	}
	if port == "" {
		port = "8000"
	}

	return Config{
		SecretToken:  secretToken,
		ProxyBaseURL: strings.TrimRight(proxyBaseURL, "/"),
		ProxyAPIKey:  proxyAPIKey,
		AIModel:      aiModel,
		Port:         port,
	}
}

// Request & Response structs
type PromptRequest struct {
	Message    string                   `json:"message"`
	History    []map[string]interface{} `json:"history,omitempty"`
	WorkingDir string                   `json:"working_dir,omitempty"`
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
Bạn có quyền thực thi lệnh bash/shell thực tế trên máy chủ qua công cụ execute_terminal_command.

CÁC QUY TẮC BẮT BUỘC (VI PHẠM LÀ LỖI NGHIÊM TRỌNG):

1. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU MỚI (STRICT SCOPE):
   - CHỈ kiểm tra và trả lời ĐÚNG DUY NHẤT đối tượng/domain/dịch vụ mà người dùng đang hỏi trong tin nhắn mới nhất.
   - TUYỆT ĐỐI KHÔNG kiểm tra lại hoặc liệt kê lại các domain, website, service khác đã hoàn thành ở các lượt trước (ví dụ: WordPress, SSL Blog, N8N...) trừ khi người dùng đích danh yêu cầu.
   - Lịch sử trò chuyện (history) CHỈ dùng để hiểu các đại từ liên hệ (như "nó", "cài đặt đi", "sửa lỗi đó"). CẤM tóm tắt lại toàn bộ lịch sử trò chuyện.

2. HÀNH ĐỘNG TIẾP NỐI - KHÔNG LÀM LẠI TỪ ĐẦU (CONTINUATION ACTION):
   - Khi người dùng ra lệnh tiếp nối ("Cài đặt đi", "Làm luôn đi", "Sửa đi", "Restart lại"): Dựa vào thông tin đã chẩn đoán ở lượt trước và BẮT TAY NGAY VÀO BƯỚC THỰC THI/CÀI ĐẶT. TUYỆT ĐỐI KHÔNG chạy lại quy trình kiểm tra ban đầu từ con số 0.

3. KẾT LUẬN NGẮN GỌN, LOGIC & ĐÚNG BẢN CHẤT (ZERO FLUFF):
   - Đi thẳng vào câu trả lời cốt lõi trong 1-3 câu ngắn gọn.
   - Cấu trúc: [Câu trả lời/Trạng thái trực tiếp] -> [Nguyên nhân kỹ thuật gốc rễ (nếu có lỗi)] -> [Hành động/Giải pháp cụ thể].
   - CẤM: Không chào hỏi, không cảm ơn, không văn mẫu xã giao, không liệt kê lại các bảng thông tin thừa thãi không được hỏi.`

func executeTerminalCommand(command string, workingDir string) string {
	log.Printf("[AI ĐANG CHẠY LỆNH]: %s (cwd=%s)", command, workingDir)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "/bin/bash", "-c", command)

	// Set full standard PATH
	currentPath := os.Getenv("PATH")
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/root/.local/bin:"+currentPath)

	if workingDir != "" {
		if fi, err := os.Stat(workingDir); err == nil && fi.IsDir() {
			cmd.Dir = workingDir
		}
	}

	out, err := cmd.CombinedOutput()
	outStr := strings.TrimSpace(string(out))

	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return "Lỗi thực thi: Quá thời gian quy định (Timeout 60s)"
		}
		if outStr != "" {
			return fmt.Sprintf("Mã thoát lỗi: %s", outStr)
		}
		return fmt.Sprintf("Lỗi thực thi: %v", err)
	}

	if outStr == "" {
		return "Lệnh chạy thành công, không có output."
	}
	return outStr
}

func callOpenAI(cfg Config, reqBody OpenAIChatRequest) (*OpenAIChatResponse, error) {
	jsonBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	apiURL := fmt.Sprintf("%s/chat/completions", cfg.ProxyBaseURL)
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonBytes))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	if cfg.ProxyAPIKey != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", cfg.ProxyAPIKey))
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

func handleAgentStream(w http.ResponseWriter, r *http.Request, cfg Config, req PromptRequest) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	sendSSE := func(eventType string, data interface{}) {
		b, _ := json.Marshal(data)
		fmt.Fprintf(w, "data: %s\n\n", string(b))
		flusher.Flush()
	}

	// 1. Build tool definition
	toolDef := map[string]interface{}{
		"type": "function",
		"function": map[string]interface{}{
			"name":        "execute_terminal_command",
			"description": "Thực thi lệnh terminal bash/shell trên server Linux.",
			"parameters": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"command": map[string]interface{}{
						"type":        "string",
						"description": "Lệnh bash cần chạy",
					},
				},
				"required": []string{"command"},
			},
		},
	}
	toolsList := []interface{}{toolDef}

	// 2. Build system prompt
	currSysPrompt := SystemPrompt
	if req.WorkingDir != "" {
		currSysPrompt += fmt.Sprintf(`

🎯 PHẠM VI LÀM VIỆC ĐƯỢC GIỚI HẠN (WORKING DIRECTORY SCOPE):
- Thư mục làm việc mục tiêu: %s
- QUY TẮC BẢO VỆ PHẠM VI:
  1. Mọi lệnh bash, thao tác file và sửa đổi code/cấu hình PHẢI THỰC HIỆN TẠI HOẶC BÊN TRONG %s.
  2. Mọi lệnh terminal phải tự động chạy với tiền tố cd %s && ... hoặc trỏ trực tiếp đến các file bên trong thư mục này.
  3. TUYỆT ĐỐI KHÔNG can thiệp, sửa đổi hoặc xoá các file/service nằm ngoài phạm vi %s nếu không được yêu cầu cụ thể.`,
			req.WorkingDir, req.WorkingDir, req.WorkingDir, req.WorkingDir)
	}

	messages := []ChatMessage{
		{Role: "system", Content: currSysPrompt},
	}

	// Append up to 4 recent history items
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
					content = content[:500] + "... [nội dung trước]"
				}
				messages = append(messages, ChatMessage{Role: role, Content: content})
			}
		}
	}

	messages = append(messages, ChatMessage{Role: "user", Content: req.Message})

	var executedTools []ToolExecutionRecord
	var executedCommands []string
	maxTurns := 25
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
			Model:       cfg.AIModel,
			Messages:    messages,
			Tools:       currentTools,
			ToolChoice:  currentToolChoice,
			Temperature: 0.1,
		}

		chatResp, err := callOpenAI(cfg, chatReq)
		if err != nil {
			log.Printf("[Lỗi OpenAI API]: %v", err)
			sendSSE("error", map[string]interface{}{"type": "error", "message": fmt.Sprintf("Lỗi Agent: %v", err)})
			return
		}

		choice := chatResp.Choices[0]
		respMsg := choice.Message

		// If AI wants to call tools
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

					// Infinite loop detection: 3 repeated calls
					executedCommands = append(executedCommands, cmdStr)
					toolRes := ""
					n := len(executedCommands)
					if n >= 3 && executedCommands[n-1] == executedCommands[n-2] && executedCommands[n-2] == executedCommands[n-3] {
						toolRes = fmt.Sprintf("[HỆ THỐNG]: Đã phát hiện lệnh lặp lại 3 lần liên tiếp: '%s'. Vui lòng phân tích lỗi và đưa ra giải pháp thay vì chạy lại lệnh cũ.", cmdStr)
					} else {
						sendSSE("status", map[string]interface{}{
							"type":    "status",
							"message": fmt.Sprintf("Đang thực thi: %s", cmdStr),
						})
						toolRes = executeTerminalCommand(cmdStr, req.WorkingDir)
					}

					rec := ToolExecutionRecord{
						Tool:    "execute_terminal_command",
						Command: cmdStr,
						Output:  toolRes,
					}
					executedTools = append(executedTools, rec)

					sendSSE("tool", map[string]interface{}{
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
			// Final response message
			fullReply = respMsg.Content
			words := strings.Split(fullReply, " ")
			for idx, w := range words {
				token := w
				if idx < len(words)-1 {
					token += " "
				}
				sendSSE("token", map[string]interface{}{
					"type":  "token",
					"delta": token,
				})
				time.Sleep(12 * time.Millisecond)
			}
			break
		}
	}

	// Fallback if fullReply is empty after loop
	if fullReply == "" {
		finalReq := OpenAIChatRequest{
			Model:       cfg.AIModel,
			Messages:    messages,
			Temperature: 0.1,
		}
		if finalResp, err := callOpenAI(cfg, finalReq); err == nil && len(finalResp.Choices) > 0 {
			fullReply = finalResp.Choices[0].Message.Content
			words := strings.Split(fullReply, " ")
			for idx, w := range words {
				token := w
				if idx < len(words)-1 {
					token += " "
				}
				sendSSE("token", map[string]interface{}{
					"type":  "token",
					"delta": token,
				})
				time.Sleep(12 * time.Millisecond)
			}
		}
	}

	sendSSE("done", map[string]interface{}{
		"type":       "done",
		"reply":      fullReply,
		"tool_calls": executedTools,
	})
}

func main() {
	cfg := loadConfig()

	mux := http.NewServeMux()

	// 1. Health check
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":         "healthy",
			"model":          cfg.AIModel,
			"proxy_base_url": cfg.ProxyBaseURL,
			"runtime":        "go-native-standalone",
		})
	})

	// 2. Main AI Agent Multi-step endpoint
	mux.HandleFunc("/ai_agent", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		token := r.Header.Get("X-Api-Token")
		if token == "" {
			token = r.Header.Get("x-api-token")
		}

		if token != cfg.SecretToken {
			http.Error(w, "Token không hợp lệ!", http.StatusUnauthorized)
			return
		}

		var req PromptRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
			return
		}

		handleAgentStream(w, r, cfg, req)
	})

	addr := fmt.Sprintf("0.0.0.0:%s", cfg.Port)
	log.Printf("=======================================================")
	log.Printf("🚀 TADU AI AGENT SERVER (STANDALONE GO LINUX BINARY)")
	log.Printf("🌐 Lắng nghe tại: %s", addr)
	log.Printf("🤖 Model AI: %s | Proxy: %s", cfg.AIModel, cfg.ProxyBaseURL)
	log.Printf("⚡ Bộ nhớ RAM tiêu thụ: ~8MB | 0 phụ thuộc Python/Pip")
	log.Printf("=======================================================")

	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
