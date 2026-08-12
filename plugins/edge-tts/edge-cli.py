import argparse
import asyncio
import edge_tts
import sys
import os

# Hàm chuyển đổi Ticks (100-nanosecond) của Edge TTS sang chuẩn giờ VTT (HH:MM:SS.ms)
def format_vtt_time(ticks):
    ms = int(ticks / 10000)
    s, ms = divmod(ms, 1000)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

async def generate_tts(text, voice, output_file, sub_file, rate, pitch):
    try:
        communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        
        last_offset = 0
        last_duration = 0
        
        with open(output_file, "wb") as file:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    file.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    # Liên tục cập nhật để lấy mốc thời gian của chữ cuối cùng
                    last_offset = chunk["offset"]
                    last_duration = chunk["duration"]
        
        # Tự động sinh file VTT chuẩn chỉnh
        if sub_file:
            # Tính thời gian kết thúc của câu (cộng thêm 200ms đệm cho tự nhiên)
            end_ticks = last_offset + last_duration + 2000000 
            end_time = format_vtt_time(end_ticks)
            
            # Ghi nguyên văn đoạn Text (Giữ nguyên viết hoa, dấu câu)
            vtt_content = f"WEBVTT\n\n00:00:00.000 --> {end_time}\n{text}\n"
            
            with open(sub_file, "w", encoding="utf-8") as f:
                f.write(vtt_content)
        
        print(f"SUCCESS|{output_file}")
        
    except Exception as e:
        print(f"ERROR|{str(e)}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Edge TTS CLI Custom")
    parser.add_argument("--text", required=True)
    parser.add_argument("--voice", default="vi-VN-NamMinhNeural")
    parser.add_argument("--output", required=True)
    parser.add_argument("--write-subtitles", default=None)
    parser.add_argument("--rate", default="+0%")
    parser.add_argument("--pitch", default="+0Hz")

    args = parser.parse_args()

    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    asyncio.run(generate_tts(args.text, args.voice, args.output, args.write_subtitles, args.rate, args.pitch))

if __name__ == "__main__":
    main()