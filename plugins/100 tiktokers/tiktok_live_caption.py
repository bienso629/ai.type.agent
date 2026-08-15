#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TikTok Live Caption (FFmpeg → faster-whisper) - CPU-friendly, max-accuracy for Vietnamese
-----------------------------------------------------------------------------------------
- Pulls audio from a livestream URL (FLV/HLS/RTMP) using FFmpeg
- Cleans/normalizes audio and segments into small WAV chunks
- Transcribes each chunk with faster-whisper using a rolling context
- Writes SRT + TXT outputs at the end (and logs partial results during run)

Defaults are tuned for **CPU-only** machines prioritizing accuracy:
    model: large-v3, device: cpu, compute_type: float32, language: vi

Usage (Windows example):
    python tiktok_live_caption.py ^
      --input "https://pull-f5-sg01.tiktokcdn.com/stage/stream-xxxx_or4.flv?expire=...&sign=..." ^
      --lang vi --task transcribe ^
      --model large-v3 --fw-device cpu --fw-compute float32 ^
      --segment-sec 10 --idle-stop-sec 25

Author: 100tiktok / ChatGPT
"""

import argparse
import contextlib
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import wave
from typing import List, Tuple, Optional

# ------------------------------
# Platform & FFmpeg detection
# ------------------------------
WIN = platform.system().lower().startswith("win")
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
if not shutil.which(FFMPEG):
    # Try common Windows embeds
    extra = [
        r"C:\ffmpeg\bin\ffmpeg.exe",
        r"C:\Program Files\ffmpeg\bin\ffmpeg.exe",
        r"C:\ProgramData\chocolatey\bin\ffmpeg.exe",
    ]
    for p in extra:
        if os.path.exists(p):
            FFMPEG = p
            break

# ------------------------------
# HTTP Headers for TikTok pulls
# ------------------------------
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)

FF_HEADERS = [
    "-user_agent", UA,
    "-referer", "https://www.tiktok.com/",
    "-headers", "Accept-Language: vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7\r\nOrigin: https://www.tiktok.com",
]

# ------------------------------
# Utilities
# ------------------------------
def ensure_dir(path: str):
    if path and not os.path.exists(path):
        os.makedirs(path, exist_ok=True)

def spawn(cmd: List[str]) -> subprocess.Popen:
    creationflags = 0
    if WIN:
        creationflags = subprocess.CREATE_NO_WINDOW
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=creationflags)

def terminate_tree(proc: Optional[subprocess.Popen]):
    if not proc:
        return
    with contextlib.suppress(Exception):
        if WIN:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            proc.terminate()

def fmt_ts(sec: float) -> str:
    if sec < 0:
        sec = 0
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def write_srt(path: str, segments: List[Tuple[float, float, str]]):
    ensure_dir(os.path.dirname(path))
    with open(path, "w", encoding="utf-8") as f:
        idx = 1
        for st, et, text in segments:
            if et <= st:
                et = st + 0.50  # avoid zero-length
            line = (text or "").strip()
            if not line:
                continue
            f.write(f"{idx}\n{fmt_ts(st)} --> {fmt_ts(et)}\n{line}\n\n")
            idx += 1

def sanitize_text(t: str) -> str:
    # Light cleanup: collapse spaces, strip odd quotes
    t = re.sub(r"\s+", " ", (t or "")).strip()
    return t

def _is_valid_wav(path: str) -> bool:
    try:
        with wave.open(path, "rb") as w:
            ok = (w.getnchannels() == 1 and w.getframerate() == 16000 and w.getsampwidth() == 2 and w.getnframes() > 0)
            return bool(ok)
    except Exception:
        return False

def _wav_ready(path: str, max_wait_s: float = 10.0) -> bool:
    deadline = time.time() + max_wait_s
    last_sz = -1
    while time.time() < deadline:
        if not os.path.exists(path):
            time.sleep(0.15)
            continue
        try:
            sz = os.path.getsize(path)
        except OSError:
            sz = -1
        if sz > 46 and sz == last_sz:
            try:
                with wave.open(path, "rb") as w:
                    if (w.getnchannels()==1 and w.getframerate()==16000 and w.getsampwidth()==2):
                        return True
            except Exception:
                pass
        last_sz = sz
        time.sleep(0.25)
    return False

# ------------------------------
# FFmpeg segmenter
# ------------------------------
def ffmpeg_chunk_audio(input_url: str, out_dir: str, segment_sec: int, extra_headers: bool = True) -> subprocess.Popen:
    """
    Spawn FFmpeg to read the livestream URL and cut mono/16k WAV chunks.
    Tuned for Whisper: highpass/lowpass + dynaudnorm.
    """
    ensure_dir(out_dir)
    out_tpl = os.path.join(out_dir, "chunk-%09d.wav")

    af = "highpass=f=120,lowpass=f=3800,dynaudnorm=f=250:g=15"

    cmd = [FFMPEG]
    if extra_headers:
        cmd += FF_HEADERS
    cmd += [
        "-hide_banner", "-loglevel", "error",
        "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5",
        "-rw_timeout", "15000000",
        "-i", input_url,
        "-vn", "-sn", "-dn",
        "-af", af,
        "-ac", "1", "-ar", "16000",
        "-c:a", "pcm_s16le",
        "-f", "segment",
        "-segment_time", str(segment_sec),
        "-segment_format", "wav",
        "-reset_timestamps", "1",
        out_tpl,
    ]
    print("[FFmpeg]", " ".join(cmd[:8]), "...", out_tpl)
    return spawn(cmd)

# ------------------------------
# Transcription (faster-whisper)
# ------------------------------
def transcribe_stream_faster_whisper(
    dir_chunks: str,
    lang: str,
    task: str,
    model_name: str,
    device: str,
    compute_type: str,
    idle_stop_sec: int = 25,
    ctx_tail_keep: int = 600,
) -> List[Tuple[float, float, str]]:
    """
    Walk through chunk-000000000.wav ... in dir_chunks and transcribe them in order.
    Uses rolling context via initial_prompt + condition_on_previous_text.
    """
    try:
        from faster_whisper import WhisperModel
    except Exception as e:
        print("[ERROR] faster-whisper not installed:", e)
        print("        pip install faster-whisper==1.* or compatible")
        return []

    # Decide device/compute_type
    dev = "cpu" if device in ("auto", "cpu", "", None) else device
    ctype = compute_type
    if ctype in ("", "auto", None):
        ctype = "float32" if dev == "cpu" else "float16"

    # Avoid OpenMP duplicate issues on Windows in some setups
    os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

    print(f"[WHISPER] Loading model={model_name} device={dev} compute_type={ctype}")
    model = WhisperModel(model_name, device=dev, compute_type=ctype)

    next_idx = 0
    results: List[Tuple[float, float, str]] = []
    ctx_tail = ""  # keep last N chars as rolling context
    last_activity = time.time()

    while True:
        fname = f"chunk-{next_idx:09d}.wav"
        fpath = os.path.join(dir_chunks, fname)

        if os.path.exists(fpath):
            if _wav_ready(fpath, max_wait_s=12) and _is_valid_wav(fpath):
                print(f"[ASR] Transcribing {fname} ...")
                segments, _info = model.transcribe(
                    fpath,
                    language=lang,
                    task=task,
                    vad_filter=True,
                    vad_parameters={"min_silence_duration_ms": 200},
                    beam_size=5,
                    patience=0.25,
                    temperature=[0.0, 0.2, 0.5],
                    condition_on_previous_text=True,
                    initial_prompt=ctx_tail[-300:],
                    word_timestamps=False,
                )
                chunk_text = ""
                for seg in segments:
                    st = float(getattr(seg, "start", 0.0) or 0.0)
                    et = float(getattr(seg, "end", 0.0) or 0.0)
                    txt = sanitize_text(getattr(seg, "text", "") or "")
                    if txt:
                        results.append((st, et, txt))
                        chunk_text += (txt + " ")
                if chunk_text:
                    ctx_tail = (ctx_tail + chunk_text)[-ctx_tail_keep:]
                    # Log partial line
                    print("[PARTIAL]", chunk_text.strip())
                last_activity = time.time()
            next_idx += 1
        else:
            if time.time() - last_activity >= idle_stop_sec:
                print(f"[INFO] Idle > {idle_stop_sec}s → stop.")
                break
            time.sleep(0.2)

    return results

# ------------------------------
# CLI
# ------------------------------
def parse_args():
    p = argparse.ArgumentParser(description="TikTok Live Caption: FFmpeg → faster-whisper (CPU-friendly, vi max-accuracy)")
    p.add_argument("--input", "--url", dest="input_url", required=True, help="Livestream media URL (FLV/HLS/RTMP)")
    p.add_argument("--segment-sec", type=int, default=10, help="FFmpeg chunk size in seconds (default: 10)")
    p.add_argument("--idle-stop-sec", type=int, default=25, help="Stop if no new chunk after N seconds (default: 25)")
    p.add_argument("--lang", default="vi", help="ASR language code (default: vi)")
    p.add_argument("--task", default="transcribe", choices=["transcribe", "translate"], help="Whisper task (default: transcribe)")
    p.add_argument("--model", default="large-v3", help="faster-whisper model id (default: large-v3)")
    p.add_argument("--fw-device", default="cpu", help="faster-whisper device: cpu/cuda/auto (default: cpu)")
    p.add_argument("--fw-compute", default="auto", help="faster-whisper compute_type (auto|float32|int8|int8_float16|float16)")
    p.add_argument("--jobs-dir", default=os.path.join(os.getcwd(), "livestream", "jobs"), help="Base jobs dir (default: ./livestream/jobs)")
    p.add_argument("--job-id", default=None, help="Job id (default: auto timestamp)")
    p.add_argument("--chunks-dir", default=None, help="Override directory for audio chunks (default: <jobs>/<job-id>/chunks)")
    p.add_argument("--srt-out", default=None, help="Output SRT path (default: <jobs>/<job-id>/captions.srt)")
    p.add_argument("--txt-out", default=None, help="Output TXT path (default: <jobs>/<job-id>/captions.txt)")
    p.add_argument("--no-extra-headers", action="store_true", help="Disable extra TikTok headers on FFmpeg")
    return p.parse_args()

def main():
    args = parse_args()

    # Job folders
    ts = time.strftime("%Y%m%d-%H%M%S")
    job_id = args.job_id or f"job-{ts}"
    dir_job = os.path.join(args.jobs_dir, job_id)
    dir_chunks = args.chunks_dir or os.path.join(dir_job, "chunks")
    ensure_dir(dir_chunks)

    srt_out = args.srt_out or os.path.join(dir_job, "captions.srt")
    txt_out = args.txt_out or os.path.join(dir_job, "captions.txt")

    print("===========================================")
    print(" TikTok Live Caption (CPU max-accuracy)")
    print("===========================================")
    print("Input URL   :", args.input_url)
    print("Job Dir     :", dir_job)
    print("Chunks Dir  :", dir_chunks)
    print("Model       :", args.model)
    print("Device/Comp :", args.fw_device, "/", args.fw_compute)
    print("Lang/Task   :", args.lang, "/", args.task)
    print("Segment (s) :", args.segment_sec)
    print("-------------------------------------------")

    # 1) Start FFmpeg segmenter
    seg_proc = ffmpeg_chunk_audio(
        input_url=args.input_url,
        out_dir=dir_chunks,
        segment_sec=args.segment_sec,
        extra_headers=(not args.no_extra_headers),
    )
    print("[INFO] Segmenter started. Waiting for chunks...")

    # 2) Transcribe stream with rolling context
    segments = []
    try:
        segments = transcribe_stream_faster_whisper(
            dir_chunks=dir_chunks,
            lang=args.lang,
            task=args.task,
            model_name=args.model,
            device=args.fw_device,
            compute_type=args.fw_compute,
            idle_stop_sec=args.idle_stop_sec,
        )
    finally:
        # 3) Cleanup segmenter
        terminate_tree(seg_proc)

    if not segments:
        print("[ERROR] No transcription segments produced.")
        return 2

    # 4) Write outputs
    write_srt(srt_out, segments)
    print("[OK] SRT written:", srt_out)

    ensure_dir(os.path.dirname(txt_out))
    with open(txt_out, "w", encoding="utf-8") as f:
        f.write("\n".join(t for _, _, t in segments))
    print("[OK] TXT written:", txt_out)

    print("[DONE] Total segments:", len(segments))
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[INTERRUPTED]")
        sys.exit(130)
