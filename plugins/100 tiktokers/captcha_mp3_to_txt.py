
"""
mp3_to_txt.py — Transcribe (or translate) an MP3/URL to a .txt using faster-whisper (offline).

Usage:
  python mp3_to_txt.py <input_mp3_or_url> [--out OUT.txt] [--task transcribe|translate]
                       [--model-size tiny|base|small|medium|large-v3] [--language xx]
                       [--device auto|cpu|cuda] [--vad]

Notes:
- "translate" uses Whisper's built-in English translation (any source -> English).
- For best accuracy, try --model-size medium or large-v3 (needs more RAM/VRAM).
- Requires FFmpeg available on PATH.
"""

import argparse
import os
import sys
import tempfile
from pathlib import Path
from typing import Optional, Tuple

# Lazy imports to allow showing a clean error if deps are missing
def _require_pkgs():
    try:
        import requests  # noqa: F401
    except Exception as e:
        print("Missing dependency 'requests'. Please install with: pip install requests", file=sys.stderr)
        raise
    try:
        from faster_whisper import WhisperModel  # noqa: F401
    except Exception:
        print("Missing dependency 'faster-whisper'. Install via: pip install faster-whisper", file=sys.stderr)
        raise

def _is_url(s: str) -> bool:
    return s.startswith("http://") or s.startswith("https://")

def _download(url: str) -> Path:
    import requests
    r = requests.get(url, stream=True, timeout=60)
    r.raise_for_status()
    suffix = ".mp3"
    # Try to infer from Content-Type or URL
    ctype = r.headers.get("Content-Type", "").lower()
    if "audio/wav" in ctype: suffix = ".wav"
    elif "audio/mpeg" in ctype: suffix = ".mp3"
    elif "audio/ogg" in ctype: suffix = ".ogg"
    elif "audio/mp4" in ctype or "audio/m4a" in ctype: suffix = ".m4a"
    elif "audio" in ctype and "." in url:
        suffix = "." + url.split("?")[0].split("/")[-1].split(".")[-1]
    fd, tmp = tempfile.mkstemp(prefix="audio_", suffix=suffix)
    os.close(fd)
    path = Path(tmp)
    with path.open("wb") as f:
        for chunk in r.iter_content(chunk_size=1024 * 256):
            if chunk:
                f.write(chunk)
    return path

def _choose_device(device: str) -> str:
    if device != "auto":
        return device
    # faster-whisper uses CTranslate2; if CUDA is available and installed, "cuda" is valid.
    # We can't reliably probe here without the package; assume CPU if CUDA env not obvious.
    return "cuda" if os.environ.get("CUDA_VISIBLE_DEVICES", "") not in ("", "-1") else "cpu"

def transcribe(input_path_or_url: str,
               out_path: Optional[str] = None,
               task: str = "transcribe",
               model_size: str = "small",
               language: Optional[str] = None,
               device: str = "auto",
               vad_filter: bool = False) -> Tuple[Path, str]:
    """
    Returns: (output_txt_path, detected_language)
    """
    _require_pkgs()
    from faster_whisper import WhisperModel

    # Download if URL
    cleanup_tmp = None
    src = Path(input_path_or_url)
    if _is_url(input_path_or_url):
        src = _download(input_path_or_url)
        cleanup_tmp = src

    if not src.exists():
        raise FileNotFoundError(f"Input not found: {src}")

    # Derive output path
    if out_path is None:
        out_path = src.with_suffix(".txt") if not _is_url(input_path_or_url) else Path.cwd() / (src.stem + ".txt")
    out_path = Path(out_path)

    # Device
    device = _choose_device(device)

    # Init model
    print(f"[INFO] Loading faster-whisper model '{model_size}' on device='{device}' ...", file=sys.stderr)
    compute_type = "float16" if device == "cuda" else "int8"
    model = WhisperModel(model_size, device=device, compute_type=compute_type)

    # Do transcription/translation
    print(f"[INFO] Transcribing: {src}", file=sys.stderr)
    segments, info = model.transcribe(str(src),
                                      task=task,
                                      language=language,
                                      vad_filter=vad_filter,
                                      beam_size=5,
                                      vad_parameters=dict(min_silence_duration_ms=500))

    # Write results
    lines = []
    lines.append(f"# mp3_to_txt result")
    lines.append(f"# source: {input_path_or_url}")
    lines.append(f"# task: {task}")
    lines.append(f"# model: {model_size}")
    lines.append(f"# language_detected: {info.language} (prob={info.language_probability:.2f})")
    lines.append("")
    for seg in segments:
        start = seg.start or 0.0
        end = seg.end or start
        text = (seg.text or "").strip()
        lines.append(f"[{start:8.2f} - {end:8.2f}] {text}")
    txt = "\n".join(lines)

    out_path.write_text(txt, encoding="utf-8")
    print(f"[OK] Saved: {out_path}", file=sys.stderr)

    # Cleanup
    if cleanup_tmp and cleanup_tmp.exists():
        try: cleanup_tmp.unlink()
        except Exception: pass

    return out_path, info.language

def main():
    parser = argparse.ArgumentParser(description="Transcribe (or translate->English) MP3/URL to TXT via faster-whisper.")
    parser.add_argument("input", help="Path to audio file or HTTP(S) URL")
    parser.add_argument("--out", help="Output .txt path (default: alongside input)", default=None)
    parser.add_argument("--task", choices=["transcribe", "translate"], default="transcribe",
                        help="Use 'translate' to translate any source language to English with Whisper.")
    parser.add_argument("--model-size", default="small",
                        choices=["tiny","base","small","medium","large-v3"],
                        help="Whisper model size")
    parser.add_argument("--language", default=None, help="Force language code (e.g., vi, en). Default: auto-detect")
    parser.add_argument("--device", default="auto", choices=["auto","cpu","cuda"], help="Inference device")
    parser.add_argument("--vad", action="store_true", help="Enable voice activity detection (can help separate segments)")
    args = parser.parse_args()

    try:
        out_path, lang = transcribe(
            input_path_or_url=args.input,
            out_path=args.out,
            task=args.task,
            model_size=args.model_size,
            language=args.language,
            device=args.device,
            vad_filter=args.vad,
        )
        print(str(out_path))
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
