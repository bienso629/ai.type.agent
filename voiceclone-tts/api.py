import os
import numpy as np
# Tối ưu hóa bộ nhớ cho Card đồ họa VRAM yếu (<= 8GB)
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from omnivoice import OmniVoice
import torchaudio
import torch
import tempfile
import base64
import os
import uuid 
import asyncio
import time
import gc
import threading
import ctypes
import queue
import re

# --- TỐI ƯU HOÁ ƯU TIÊN TIẾN TRÌNH TRÊN WINDOWS ---
if os.name == 'nt':
    try:
        # HIGH_PRIORITY_CLASS = 0x00000080
        ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 0x00000080)
        print("[INFO] Đã thiết lập tiến trình API chạy ở mức độ ưu tiên CAO NHẤT (HIGH_PRIORITY) trên Windows.")
    except Exception as e:
        print(f"[WARN] Không thể thiết lập mức độ ưu tiên: {e}")

app = FastAPI(title="OmniVoice TTS API (High Performance - Queue Version)")

model = None
voice_text_cache = {}
tasks_db = {}
task_queue = queue.Queue()

class GenerateAudioRequest(BaseModel):
    text: str = Field(..., description="Văn bản cần đọc")
    ref_audio_name: Optional[str] = None
    ref_audio_base64: Optional[str] = None
    ref_text: Optional[str] = None
    
    num_step: int = Field(32, description="Tăng lên 32 để đạt chất lượng giọng đọc tốt nhất")
    denoise: bool = Field(True)
    guidance_scale: float = Field(2.0)
    t_shift: float = Field(0.1)
    position_temperature: float = Field(5.0)
    class_temperature: float = Field(0.0)
    layer_penalty_factor: float = Field(5.0)
    duration: Optional[float] = None
    speed: Optional[float] = None
    preprocess_prompt: bool = Field(True)
    postprocess_output: bool = Field(True)
    audio_chunk_duration: float = Field(10.0, description="Giảm xuống 10.0 để bảo vệ VRAM 8GB")
    audio_chunk_threshold: float = Field(30.0)

# --- HÀM HỖ TRỢ ÉP DỪNG THREAD (FORCE KILL) ---
def force_kill_thread(thread: threading.Thread):
    """Ép dừng một thread bằng cách ném Exception SystemExit vào bên trong nó qua ctypes"""
    if not thread.is_alive():
        return
    tid = thread.ident
    # Ném SystemExit vào thread đang chạy model.generate()
    res = ctypes.pythonapi.PyThreadState_SetAsyncExc(ctypes.c_long(tid), ctypes.py_object(SystemExit))
    if res == 0:
        print(f"[KILL] Không tìm thấy thread ID: {tid}")
    elif res != 1:
        # Nếu có lỗi, reset lại trạng thái
        ctypes.pythonapi.PyThreadState_SetAsyncExc(ctypes.c_long(tid), None)
        print(f"[KILL] Lỗi hệ thống khi cố gắng kill thread {tid}")

@app.post("/load_model")
def load_model():
    global model
    if model is not None:
        return {"status": "success", "message": "Mô hình đã được nạp trước đó."}
    
    try:
        # Tắt benchmark để tránh lag do input có kích thước động
        torch.backends.cudnn.benchmark = False
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        
        # Cấu hình tự động fallback xuống CPU nếu không có Card rời NVIDIA
        device = "cuda:0" if torch.cuda.is_available() else "cpu"
        
        # Kiểm tra xem GPU có tương thích với phiên bản PyTorch hiện tại không (VD: GTX 1070 sm_61 bị PyTorch mới bỏ hỗ trợ)
        if device == "cuda:0":
            try:
                # Chạy thử 1 phép tính nhỏ trên GPU để test lỗi 'no kernel image' (phải có phép toán để kích hoạt kernel)
                _test = torch.zeros(1).cuda() + 1
            except RuntimeError as e:
                if "no kernel image is available for execution" in str(e).lower():
                    print("[WARN] GPU của bạn (Compute Capability cũ) không được PyTorch phiên bản này hỗ trợ. Hệ thống tự động chuyển sang chạy bằng CPU (sẽ chậm hơn).")
                    device = "cpu"
                else:
                    raise e
                    
        model_dtype = torch.float16 if device == "cuda:0" else torch.float32
        
        # Ưu tiên lấy từ biến môi trường (do Electron set), nếu không có thì lấy thư mục tương đối 'OmniVoice' cùng cấp với api.py
        default_model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "OmniVoice")
        model_path = os.environ.get("OMNIVOICE_MODEL_PATH", default_model_path)
        if not os.path.exists(model_path):
            model_path = default_model_path

        print(f"[INFO] Đang nạp mô hình OmniVoice từ: {model_path}")
        print(f"[INFO] Thiết bị xử lý: {device} | Định dạng: {model_dtype}")

        model = OmniVoice.from_pretrained(
            model_path,
            device_map=device,
            dtype=model_dtype,
            local_files_only=True
        )
        
        # Tắt compile để tránh lỗi treo 3 phút khi sinh giọng
        # model = torch.compile(model)
        return {"status": "success", "message": "Nap mo hinh thanh cong!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Loi khi nap mo hinh: {str(e)}")

@app.post("/unload_model")
def unload_model():
    global model
    if model is not None:
        print("[INFO] Đang giải phóng toàn bộ mô hình khỏi RAM/VRAM...")
        del model
        model = None
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print("[SUCCESS] Đã giải phóng RAM/VRAM thành công!")
        return {"status": "success", "message": "Đã giải phóng toàn bộ RAM/VRAM của mô hình."}
    return {"status": "success", "message": "Mô hình đã được giải phóng trước đó."}

# Vòng lặp dọn rác ngầm
async def cleanup_tasks_loop():
    while True:
        await asyncio.sleep(15) # Rút ngắn thời gian kiểm tra xuống mỗi 15 giây
        try:
            now = time.time()
            to_delete = []
            
            # Sử dụng list() để tránh lỗi dictionary changed size during iteration
            for tid, tinfo in list(tasks_db.items()):
                status = tinfo.get("status")
                
                # Hủy những task đang xử lý / chờ xử lý mà không thấy ai hỏi thăm quá 30 giây (App đã crash/mất mạng)
                if status in ["queued", "processing"]:
                    last_polled = tinfo.get("last_polled", tinfo.get("created_at", now))
                    if now - last_polled > 30:
                        print(f"[HEARTBEAT] Task {tid} bị bỏ rơi do client ngắt kết nối quá 30s. Đang tiến hành hủy...")
                        worker_thread = tinfo.get("thread")
                        if worker_thread and worker_thread.is_alive():
                            force_kill_thread(worker_thread)
                        tinfo["status"] = "cancelled"
                
                # Xóa hẳn task khỏi bộ nhớ nếu đã tồn tại quá 300 giây (5 phút)
                if now - tinfo.get("created_at", now) > 300:
                    to_delete.append(tid)
                    
            for tid in to_delete:
                tinfo = tasks_db.pop(tid, {})
                if "file_path" in tinfo and os.path.exists(tinfo["file_path"]):
                    try:
                        os.remove(tinfo["file_path"])
                    except Exception as e:
                        print(f"[CLEANUP] Loi khi xoa file {tinfo['file_path']}: {e}")
                print(f"[CLEANUP] Da don dep task {tid} khoi Ram va o cung do qua han.")
        except Exception as e:
            print(f"[CLEANUP ERROR] Lỗi trong vòng lặp dọn rác: {e}")

@app.on_event("startup")
def startup_event():
    print("[INFO] Dang tu dong nap mo hinh OmniVoice vao GPU...")
    # Luôn bật Auto-Cleanup và Queue Worker ngay cả khi nạp model lỗi
    asyncio.create_task(cleanup_tasks_loop())
    for _ in range(3):
        threading.Thread(target=queue_worker_loop, daemon=True).start()
    print("[INFO] Da bat he thong Auto-Cleanup (Don rac moi 60s) va Queue Worker.")
    try:
        load_model()
        print("[SUCCESS] Da nap mo hinh thanh cong! API da san sang nhan request.")
    except Exception as e:
        print(f"[ERROR] Loi khi tu dong nap mo hinh: {e}")

def process_audio_background(task_id: str, request: GenerateAudioRequest):
    global model, voice_text_cache
    
    if model is None:
        tasks_db[task_id].update({"status": "error", "message": "Chưa nạp model."})
        return

    final_ref_path = None
    temp_ref_path = None
    audio_tensors = None 
    
    try:
        if request.ref_audio_base64:
            audio_bytes = base64.b64decode(request.ref_audio_base64)
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
                temp_file.write(audio_bytes)
                temp_ref_path = temp_file.name
            final_ref_path = temp_ref_path
        elif request.ref_audio_name:
            final_ref_path = os.path.join("voices", request.ref_audio_name)
        else:
            final_ref_path = None

        final_ref_text = request.ref_text
        if not final_ref_text and request.ref_audio_name:
            if request.ref_audio_name in voice_text_cache:
                final_ref_text = voice_text_cache[request.ref_audio_name]

        # Tách câu bằng regex (chấm, chấm hỏi, chấm than, xuống dòng)
        raw_text = request.text
        splits = re.split(r'(?<=[.?!])\s+|\n+', raw_text.strip())
        sentences = [s.strip() for s in splits if s.strip()]
        if not sentences:
            sentences = [raw_text]

        print(f"[{task_id}] Tách đoạn văn thành {len(sentences)} câu để xử lý.")

        # Quá trình generate có thể bị ngắt ngang bởi Exception SystemExit từ bên ngoài
        # Sử dụng torch.inference_mode() để tắt tính toán đạo hàm, giúp tăng tốc tối đa và giảm VRAM
        import time
        with torch.inference_mode():
            audio_tensors = []
            for i, sentence in enumerate(sentences):
                if tasks_db.get(task_id, {}).get("status") == "cancelled":
                    print(f"[{task_id}] Nhận cờ huỷ, dừng sinh audio sớm ở câu {i+1}.")
                    break

                s_time = time.time()
                print(f"[{task_id}] Đang xử lý câu {i+1}/{len(sentences)}: {sentence[:30]}...")
                
                t = model.generate(
                    text=sentence,
                    ref_audio=final_ref_path,
                    ref_text=final_ref_text,
                    num_step=request.num_step,
                    denoise=request.denoise,
                    guidance_scale=request.guidance_scale,
                    t_shift=request.t_shift,
                    position_temperature=request.position_temperature,
                    class_temperature=request.class_temperature,
                    layer_penalty_factor=request.layer_penalty_factor,
                    duration=request.duration,
                    speed=request.speed,
                    preprocess_prompt=request.preprocess_prompt,
                    postprocess_output=request.postprocess_output,
                    audio_chunk_duration=request.audio_chunk_duration,
                    audio_chunk_threshold=request.audio_chunk_threshold
                )
                
                print(f"[{task_id}] -> Câu {i+1} chạy xong trong {time.time() - s_time:.2f} giây.")
                
                # Trích xuất tensor từ tuple/list/ndarray
                if isinstance(t, (list, tuple)):
                    t = t[0]
                if isinstance(t, np.ndarray):
                    t = torch.from_numpy(t)
                if t.dim() == 1:
                    t = t.unsqueeze(0)
                
                audio_tensors.append(t)

        # Ghép các câu lại thành 1 file âm thanh hoàn chỉnh
        if len(audio_tensors) > 1:
            final_audio = torch.cat(audio_tensors, dim=1)
        elif len(audio_tensors) == 1:
            final_audio = audio_tensors[0]
        else:
            raise ValueError("Không có dữ liệu âm thanh nào được tạo ra.")
            
        if final_audio.dim() == 1:
            final_audio = final_audio.unsqueeze(0)

        # Tạo thư mục outputs nếu chưa có
        os.makedirs("outputs", exist_ok=True)
        out_path = os.path.join("outputs", f"output_{task_id}.wav")
        torchaudio.save(out_path, final_audio.cpu(), 24000)

        if task_id in tasks_db and tasks_db[task_id].get("status") != "cancelled":
            tasks_db[task_id].update({
                "status": "done",
                "file_path": out_path
            })

    except SystemExit:
        # Bắt tín hiệu Cancel (Force Kill) từ user hoặc timeout
        print(f"[FORCE KILL] Đã ép dừng task {task_id} thành công, giải phóng tài nguyên!")
        if task_id in tasks_db:
            tasks_db[task_id].update({"status": "cancelled", "message": "Task bị ép dừng"})
            
    except Exception as e:
        if tasks_db.get(task_id, {}).get("status") != "cancelled":
            if task_id in tasks_db:
                tasks_db[task_id].update({"status": "error", "message": str(e)})
    finally:
        # TẤT CẢ TÀI NGUYÊN SẼ ĐƯỢC GIẢI PHÓNG TẠI ĐÂY KỂ CẢ KHI BỊ FORCE KILL
        if temp_ref_path and os.path.exists(temp_ref_path):
            os.remove(temp_ref_path)
            
        if audio_tensors is not None:
            del audio_tensors
            
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            print(f"[VRAM] Đã dọn dẹp bộ nhớ GPU cho task {task_id}.")

def queue_worker_loop():
    """Luồng worker ngầm, liên tục lấy task từ queue ra xử lý từng cái một trên DUY NHẤT 1 LUỒNG (tránh crash CUDA)"""
    while True:
        try:
            task_id, request = task_queue.get()
            
            # Nếu task đã bị hủy trước khi tới lượt, bỏ qua luôn
            if tasks_db.get(task_id, {}).get("status") == "cancelled":
                task_queue.task_done()
                continue
                
            if task_id in tasks_db:
                tasks_db[task_id]["status"] = "processing"
                tasks_db[task_id]["thread"] = threading.current_thread()
                
            # Chạy trực tiếp hàm xử lý trên luồng này, KHÔNG tạo thread mới để tránh xung đột VRAM Card
            process_audio_background(task_id, request)
            
        except BaseException as e:
            print(f"[QUEUE ERROR] Lỗi nghiêm trọng hoặc bị ép dừng ngoài dự kiến: {type(e).__name__} - {e}")
        finally:
            task_queue.task_done()

@app.post("/generate_audio_async")
async def generate_audio_async(request: GenerateAudioRequest):
    task_id = str(uuid.uuid4())
    
    tasks_db[task_id] = {
        "status": "queued",
        "created_at": time.time(),
        "thread": None 
    }
    
    task_queue.put((task_id, request))
    
    return {"status": "success", "task_id": task_id, "message": "Đã thêm vào hàng đợi..."}

@app.get("/status/{task_id}")
async def check_status(task_id: str):
    task = tasks_db.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Không tìm thấy task này")
    
    # Cập nhật thời gian được hỏi thăm lần cuối (Heartbeat)
    task["last_polled"] = time.time()
    
    if task["status"] == "done":
        return {"status": "done", "download_url": f"/download_audio/{task_id}"}
    elif task["status"] == "error":
        return {"status": "error", "message": task["message"]}
    elif task["status"] == "cancelled":
        return {"status": "cancelled", "message": "Task đã bị hủy hoàn toàn"}
    elif task["status"] == "queued":
        return {"status": "queued", "message": "Đang xếp hàng chờ xử lý"}
    else:
        return {"status": "processing"}
    
@app.post("/cancel_task/{task_id}")
async def cancel_task(task_id: str):
    task = tasks_db.get(task_id)
    if not task:
        return {"status": "error", "message": "Không tìm thấy task"}
        
    if task["status"] in ["processing", "queued"]:
        worker_thread = task.get("thread")
        if worker_thread and worker_thread.is_alive():
            # Đặt cờ huỷ trước để vòng lặp sinh audio tự dừng giữa các câu
            task["status"] = "cancelled"
            # Thực thi Force Kill ngay lập tức
            force_kill_thread(worker_thread)
            return {"status": "success", "message": "Đã gửi tín hiệu ép dừng và giải phóng VRAM"}
        else:
            task["status"] = "cancelled"
            return {"status": "success", "message": "Đã cập nhật trạng thái hủy"}
            
    return {"status": "error", "message": f"Không thể hủy task ở trạng thái: {task['status']}"}

@app.get("/download_audio/{task_id}")
async def download_audio(task_id: str):
    task = tasks_db.get(task_id)
    if not task or task["status"] != "done":
        raise HTTPException(status_code=404, detail="File chưa sẵn sàng hoặc không tồn tại")
    
    return FileResponse(task["file_path"], media_type="audio/wav", filename=f"output_{task_id}.wav")