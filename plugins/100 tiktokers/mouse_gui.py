import os
import json
import time
import threading
import ctypes
from datetime import datetime
import tkinter.messagebox as mbox

import customtkinter as ctk
import pyautogui

# ================== CẤU HÌNH ==================
HOLD_SECONDS = 3.0                  # thời gian giữ chuột trái để bật form
JSON_PATH = os.path.join(os.path.dirname(__file__), "mouse_coords.json")
ALPHA = 0.85                        # độ trong suốt overlay
CORNER_RADIUS = 15                  # bo góc overlay
LABEL_FONT = ("Segoe UI", 12)
TITLE_FONT = ("Segoe UI", 16, "bold")

# Kích thước form & lề an toàn khỏi mép màn hình
FORM_W, FORM_H = 560, 380
FORM_MARGIN = 32                    # luôn cách mép ít nhất 32px
INNER_PAD = 16                      # <-- padding bên trong khung chính (mới)

ctk.set_appearance_mode("light")
ctk.set_default_color_theme("blue")

# VK code cho chuột trái trên Windows
VK_LBUTTON = 0x01

# Lock để ghi/đọc JSON an toàn giữa các thread
_JSON_LOCK = threading.Lock()


# ============== HÀM TIỆN ÍCH LƯU/TRÍCH JSON ==============
def _ensure_json_file():
    if not os.path.exists(JSON_PATH):
        data = {"sites": {}}
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

def _load_json():
    _ensure_json_file()
    with _JSON_LOCK:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)

def _save_json(data):
    with _JSON_LOCK:
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)


# ============== THÔNG TIN MÀN HÌNH (HỖ TRỢ ĐA MÀN HÌNH) ==============
def _get_virtual_screen_rect():
    user32 = ctypes.windll.user32
    SM_XVIRTUALSCREEN = 76
    SM_YVIRTUALSCREEN = 77
    SM_CXVIRTUALSCREEN = 78
    SM_CYVIRTUALSCREEN = 79
    vx = user32.GetSystemMetrics(SM_XVIRTUALSCREEN)
    vy = user32.GetSystemMetrics(SM_YVIRTUALSCREEN)
    vw = user32.GetSystemMetrics(SM_CXVIRTUALSCREEN)
    vh = user32.GetSystemMetrics(SM_CYVIRTUALSCREEN)
    return vx, vy, vw, vh

def _clamp_with_margin(cx, cy, w, h, margin=FORM_MARGIN):
    vx, vy, vw, vh = _get_virtual_screen_rect()
    min_x = vx + margin
    min_y = vy + margin
    max_x = vx + vw - w - margin
    max_y = vy + vh - h - margin
    x = max(min_x, min(cx, max_x))
    y = max(min_y, min(cy, max_y))
    return x, y


# ================== FORM NHẬP DỮ LIỆU ==================
class CaptureForm(ctk.CTkToplevel):
    def __init__(self, master, x, y, default_site="", on_save=None):
        super().__init__(master)
        self.title("Lưu tọa độ")
        self.attributes("-topmost", True)
        self.geometry(self._calc_geometry_near_cursor())
        self.resizable(True, True)
        self.minsize(520, 340)

        self.on_save = on_save

        # Khung chính (bo góc) + khoảng cách với mép cửa sổ
        outer = ctk.CTkFrame(self, corner_radius=12)
        outer.pack(fill="both", expand=True, padx=16, pady=16)

        # Khung "nội dung" để tạo INNER PAD giữa viền và các control
        content = ctk.CTkFrame(outer, fg_color="transparent")
        content.pack(fill="both", expand=True, padx=INNER_PAD, pady=INNER_PAD)

        content.grid_columnconfigure(1, weight=1)

        header = ctk.CTkLabel(content, text="Ghi tọa độ cho website", font=TITLE_FONT)
        header.grid(row=0, column=0, columnspan=2, pady=(0, 10), sticky="w")

        ctk.CTkLabel(content, text="Website (A/B/C... hoặc domain):", anchor="w").grid(row=1, column=0, sticky="w", pady=6)
        self.site_entry = ctk.CTkEntry(content, width=380)
        self.site_entry.insert(0, default_site)
        self.site_entry.grid(row=1, column=1, sticky="ew", pady=6)

        ctk.CTkLabel(content, text="Title:", anchor="w").grid(row=2, column=0, sticky="w", pady=6)
        self.title_entry = ctk.CTkEntry(content, width=380, placeholder_text="ví dụ: Nút Đăng nhập")
        self.title_entry.grid(row=2, column=1, sticky="ew", pady=6)

        ctk.CTkLabel(content, text="screenX:", anchor="w").grid(row=3, column=0, sticky="w", pady=6)
        self.x_entry = ctk.CTkEntry(content, width=180)
        self.x_entry.insert(0, str(x))
        self.x_entry.configure(state="readonly")
        self.x_entry.grid(row=3, column=1, sticky="w", pady=6)

        ctk.CTkLabel(content, text="screenY:", anchor="w").grid(row=4, column=0, sticky="w", pady=6)
        self.y_entry = ctk.CTkEntry(content, width=180)
        self.y_entry.insert(0, str(y))
        self.y_entry.configure(state="readonly")
        self.y_entry.grid(row=4, column=1, sticky="w", pady=6)

        self.refresh_xy_btn = ctk.CTkButton(content, text="Lấy X/Y hiện tại", command=self._refresh_xy)
        self.refresh_xy_btn.grid(row=5, column=0, columnspan=2, sticky="ew", pady=(10, 4))

        btn_row = ctk.CTkFrame(content, fg_color="transparent")
        btn_row.grid(row=6, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        btn_row.grid_columnconfigure((0, 1), weight=1)

        save_btn = ctk.CTkButton(btn_row, text="Lưu", command=self._do_save)
        save_btn.grid(row=0, column=0, padx=(0, 8), sticky="ew")

        cancel_btn = ctk.CTkButton(btn_row, text="Hủy", fg_color="#999999", hover_color="#7a7a7a",
                                   command=self.destroy)
        cancel_btn.grid(row=0, column=1, padx=(8, 0), sticky="ew")

        self.bind("<Return>", lambda e: self._do_save())
        self.bind("<Escape>", lambda e: self.destroy())
        self.after(50, self.title_entry.focus)

    def _calc_geometry_near_cursor(self):
        cx, cy = pyautogui.position()
        x0, y0 = cx + 20, cy + 20
        x, y = _clamp_with_margin(x0, y0, FORM_W, FORM_H, FORM_MARGIN)
        return f"{FORM_W}x{FORM_H}+{int(x)}+{int(y)}"

    def _refresh_xy(self):
        x, y = pyautogui.position()
        self.x_entry.configure(state="normal")
        self.y_entry.configure(state="normal")
        self.x_entry.delete(0, "end")
        self.y_entry.delete(0, "end")
        self.x_entry.insert(0, str(x))
        self.y_entry.insert(0, str(y))
        self.x_entry.configure(state="readonly")
        self.y_entry.configure(state="readonly")

    def _do_save(self):
        site = self.site_entry.get().strip()
        title = self.title_entry.get().strip()
        x = int(self.x_entry.get())
        y = int(self.y_entry.get())

        if not site:
            mbox.showwarning("Thiếu website", "Vui lòng nhập Website (ví dụ: A, B, C hoặc domain).")
            return
        if not title:
            mbox.showwarning("Thiếu title", "Vui lòng nhập Title.")
            return

        data = _load_json()
        sites = data.setdefault("sites", {})
        arr = sites.setdefault(site, [])
        arr.append({
            "title": title,
            "screenX": x,
            "screenY": y,
            "ts": datetime.now().isoformat(timespec="seconds")
        })
        _save_json(data)

        if self.on_save:
            self.on_save(site)
        self.destroy()


# ================== OVERLAY HIỂN THỊ TỌA ĐỘ ==================
class Overlay(ctk.CTkToplevel):
    def __init__(self):
        super().__init__()
        self.overrideredirect(True)
        self.attributes("-topmost", True)
        self.attributes("-alpha", ALPHA)
        self.configure(fg_color=("white", "white"), corner_radius=CORNER_RADIUS)

        vx, vy, vw, vh = _get_virtual_screen_rect()
        start_x = vx + vw - 260 - FORM_MARGIN
        start_y = vy + FORM_MARGIN
        self.geometry(f"+{int(start_x)}+{int(start_y)}")

        container = ctk.CTkFrame(self, corner_radius=CORNER_RADIUS)
        container.pack(padx=6, pady=6, fill="both", expand=True)

        self.label_xy = ctk.CTkLabel(container, text="X=0, Y=0", font=LABEL_FONT)
        self.label_xy.pack(padx=10, pady=(8, 2))

        self.label_hint = ctk.CTkLabel(
            container,
            text=f"Giữ chuột trái {HOLD_SECONDS:.0f}s\nđể lưu tọa độ vào JSON",
            font=("Segoe UI", 11),
            text_color="#444444"
        )
        self.label_hint.pack(padx=10, pady=(0, 8))

        self.last_site = ""
        self.lbl_site = ctk.CTkLabel(container, text="Website gần nhất: (chưa có)", font=("Segoe UI", 11, "italic"))
        self.lbl_site.pack(padx=10, pady=(0, 8))

        for widget in (self.label_xy, self.label_hint, self.lbl_site):
            widget.bind("<Button-1>", self._start_move)
            widget.bind("<B1-Motion>", self._do_move)

        threading.Thread(target=self._update_position_loop, daemon=True).start()
        threading.Thread(target=self._hold_watcher_loop, daemon=True).start()

    def _start_move(self, event):
        self._drag_x = event.x
        self._drag_y = event.y

    def _do_move(self, event):
        x = self.winfo_x() + event.x - self._drag_x
        y = self.winfo_y() + event.y - self._drag_y
        self.geometry(f"+{x}+{y}")

    def _update_position_loop(self):
        while True:
            try:
                x, y = pyautogui.position()
                self.label_xy.configure(text=f"X={x}, Y={y}")
                time.sleep(0.1)
            except Exception:
                time.sleep(0.2)

    def _hold_watcher_loop(self):
        user32 = ctypes.windll.user32

        def is_left_down():
            return (user32.GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0

        cooldown = 0.6
        last_trigger_time = 0.0

        while True:
            try:
                if is_left_down():
                    t0 = time.time()
                    while is_left_down():
                        if time.time() - t0 >= HOLD_SECONDS and (time.time() - last_trigger_time) > cooldown:
                            x, y = pyautogui.position()
                            last_trigger_time = time.time()
                            self.after(0, self._open_form, x, y)
                            while is_left_down():
                                time.sleep(0.05)
                            time.sleep(0.1)
                            break
                        time.sleep(0.03)
                time.sleep(0.03)
            except Exception:
                time.sleep(0.2)

    def _open_form(self, x, y):
        form = CaptureForm(self, x=x, y=y, default_site=self.last_site, on_save=self._on_saved)
        form.lift()
        form.focus_force()

    def _on_saved(self, site_just_saved: str):
        self.last_site = site_just_saved
        self.lbl_site.configure(text=f"Website gần nhất: {self.last_site}")


# ================== MAIN ==================
if __name__ == "__main__":
    _ensure_json_file()

    app = ctk.CTk()
    app.withdraw()
    overlay = Overlay()
    overlay.mainloop()
