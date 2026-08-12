import http.server
import socketserver
import subprocess
import json
import os
import urllib.request
import urllib.error
import time

PORT = 8000
MINERU_PORT = 48921
MINERU_EXE = ".\\mineru_api.exe"
REMOTE_MINERU_URL = "https://advanced-eagerly-lioness.ngrok-free.app"  # Nhập URL Cloudflare vào đây, ví dụ "https://xyz.trycloudflare.com"

mineru_process = None

def is_mineru_running():
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{MINERU_PORT}/docs", method="GET")
        with urllib.request.urlopen(req, timeout=1) as response:
            return response.status == 200
    except Exception:
        return False

def start_mineru():
    global mineru_process
    if not is_mineru_running():
        print("Starting mineru_api.exe...")
        env = os.environ.copy()
        env["MINERU_MODEL_PATH"] = r"C:\Users\Wing386\apps\pdf-viewer\models--opendatalab--MinerU2.5-Pro-2604-1.2B\snapshots\d3f5e08d073c21466bbabe21c71bb1e9c2e595da"
        mineru_process = subprocess.Popen(
        ["python", "-u", r"C:\Users\Wing386\ai.type\electron\scripts\pdf.py"], 
        env=env
    )
        # Wait for it to boot up (can take 1-2 mins for 3.5GB pyinstaller extraction)
        for _ in range(180): 
            time.sleep(1)
            if is_mineru_running():
                print("mineru_api.exe is ready!")
                return True
        print("Failed to start mineru_api.exe in time.")
        return False
    return True

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/analyze_pdf':
            print(f"\n--- Received API request at {self.path} ---")
            try:
                # Lấy dữ liệu JSON từ request của Electron
                content_length = int(self.headers.get('Content-Length', 0))
                post_data = self.rfile.read(content_length)
                req_json = json.loads(post_data.decode('utf-8'))
                
                pdf_abs_path = req_json.get("file_path")
                if not pdf_abs_path or not os.path.exists(pdf_abs_path):
                    raise Exception(f"File không tồn tại: {pdf_abs_path}")
                # 1. Determine URL and start local server if needed
                if REMOTE_MINERU_URL:
                    base_url = REMOTE_MINERU_URL.rstrip('/')
                    print(f"Using remote MinerU API at: {base_url}")
                else:
                    if not start_mineru():
                        raise Exception("Could not start or connect to mineru_api.exe")
                    base_url = f"http://127.0.0.1:{MINERU_PORT}"
                
                # 2. Call /load_model
                print("Loading model...")
                req = urllib.request.Request(f"{base_url}/load_model", method="POST")
                with urllib.request.urlopen(req) as response:
                    res_data = json.loads(response.read().decode())
                    if res_data.get("status") != "success":
                        raise Exception(f"Failed to load model: {res_data}")
                
                # 3. Call /analyze
                print(f"Analyzing PDF: {pdf_abs_path} ...")
                
                # Chuyển đổi file sang base64 để hỗ trợ gửi qua mạng
                import base64
                with open(pdf_abs_path, "rb") as f:
                    file_b64 = base64.b64encode(f.read()).decode()
                
                analyze_payload = json.dumps({
                    "file_path": os.path.basename(pdf_abs_path), # Chỉ gửi tên file
                    "file_base64": file_b64
                }).encode('utf-8')
                
                req = urllib.request.Request(
                    f"{base_url}/analyze", 
                    data=analyze_payload,
                    headers={'Content-Type': 'application/json'},
                    method="POST"
                )
                
                # Analysis might take a long time, so no timeout (or a very large one)
                with urllib.request.urlopen(req, timeout=3600) as response:
                    res_data = json.loads(response.read().decode())
                    if res_data.get("status") != "success":
                        raise Exception(f"Failed to analyze PDF: {res_data}")
                    
                    # 4. Extract base64 images if present and Save to json file
                    json_output = res_data.get("data")
                    if isinstance(json_output, str):
                        # The API returns a json string inside the data field
                        try:
                            json_output = json.loads(json_output)
                        except:
                            json_output = []

                    if isinstance(json_output, list):
                        # Trích xuất hình ảnh từ base64
                        img_dir = pdf_abs_path + "_images"
                        if not os.path.exists(img_dir):
                            os.makedirs(img_dir)
                            
                        for item in json_output:
                            if 'image_base64' in item:
                                img_filename = f"page_{item.get('page_idx', 0)+1}_{item.get('type')}_{item.get('id', 'x')}.png"
                                img_path = os.path.join(img_dir, img_filename)
                                with open(img_path, "wb") as img_file:
                                    img_file.write(base64.b64decode(item['image_base64']))
                                item['image_url'] = f"{os.path.basename(img_dir)}/{img_filename}"
                                del item['image_base64']
                        
                        json_str = json.dumps(json_output, ensure_ascii=False)
                    else:
                        json_str = str(json_output)
                        
                    json_filename = f"{pdf_abs_path}.mineru.json"
                    with open(json_filename, "w", encoding="utf-8") as f:
                        f.write(json_str)
                
                # Trả JSON data trực tiếp về cho App Electron
                self.send_response(200)
                # Sửa lỗi CORS nếu gọi từ Electron
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                
                res_body = json.dumps({
                    "status": "success", 
                    "message": "Phân tích thành công",
                    "json_file": json_filename,
                    "data": json_output if isinstance(json_output, list) else json_str
                }, ensure_ascii=False)
                
                self.wfile.write(res_body.encode('utf-8'))
                print("--- Analysis complete ---")
                
            except Exception as e:
                import traceback
                print(f"Error during analysis: {e}")
                traceback.print_exc()
                self.send_response(500)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "error", "message": str(e)}).encode('utf-8'))
        else:
            self.send_error(404, "Not Found")
            
    def do_OPTIONS(self):
        # Trả lời preflight request cho CORS
        self.send_response(200, "ok")
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

if __name__ == '__main__':
    backend_process = None
    with ThreadingTCPServer(("", PORT), CustomHandler) as httpd:
        print(f"Custom Server running at http://localhost:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            if mineru_process:
                mineru_process.terminate()
            backend_process.terminate()
            print("\nShutting down server...")
