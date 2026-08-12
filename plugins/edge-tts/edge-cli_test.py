import argparse
import asyncio
import edge_tts
import sys
import json
import os

def sanitize_text(text):
    """Làm sạch văn bản để tránh ký tự rác"""
    if not text: return ""
    return text.replace('\ufeff', '').replace('\xa0', ' ').strip()

async def process_json_tts(json_data, output_file, subtitle_flag):
    try:
        submaker = edge_tts.SubMaker()
        
        # Mở file mp3 để ghi tuần tự (append binary)
        with open(output_file, "wb") as audio_file:
            for index, segment in enumerate(json_data):
                seg_type = segment.get("type", "speech")
                
                if seg_type == "pause":
                    # Xử lý khoảng lặng bằng cách tạo một đoạn SSML nghỉ ngắn
                    duration = segment.get("duration", 1000) # mặc định 1s
                    print(f"--> [PAUSE]: Nghỉ {duration}ms")
                    pause_ssml = f"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='vi-VN'><break time='{duration}ms'/></speak>"
                    communicate = edge_tts.Communicate(text=pause_ssml)
                
                else:
                    # Xử lý giọng nói
                    text = sanitize_text(segment.get("text", ""))
                    voice = segment.get("voice", "vi-VN-NamMinhNeural")
                    rate = segment.get("rate", "+0%")
                    pitch = segment.get("pitch", "+0Hz")
                    volume = segment.get("volume", "+0%")
                    
                    print(f"--> [SPEECH]: Segment {index+1} | Giọng: {voice} | Text: {text[:30]}...")
                    
                    communicate = edge_tts.Communicate(
                        text=text,
                        voice=voice,
                        rate=rate,
                        pitch=pitch,
                        volume=volume
                    )

                # Ghi dữ liệu vào file tổng
                async for chunk in communicate.stream():
                    if chunk["type"] == "audio":
                        audio_file.write(chunk["data"])
                    elif chunk["type"] in ("WordBoundary", "SentenceBoundary") and subtitle_flag:
                        submaker.feed(chunk)

        # Xuất phụ đề nếu yêu cầu
        if subtitle_flag:
            subs_path = os.path.splitext(output_file)[0] + ".vtt"
            with open(subs_path, "w", encoding="utf-8") as f:
                f.write("WEBVTT\n\n" + submaker.get_srt())
            print(f"SUCCESS|{output_file}|{subs_path}")
        else:
            print(f"SUCCESS|{output_file}")

    except Exception as e:
        print(f"ERROR|{str(e)}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Edge TTS JSON Processor")
    parser.add_argument("--input-json", required=True, help="Đường dẫn file JSON kịch bản")
    parser.add_argument("--output", required=True, help="File mp3 đầu ra")
    parser.add_argument("--subtitle", action="store_true", help="Xuất phụ đề tổng")
    
    args = parser.parse_args()

    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    if not os.path.exists(args.input_json):
        print(f"ERROR|Không tìm thấy file JSON: {args.input_json}", file=sys.stderr)
        sys.exit(1)

    with open(args.input_json, "r", encoding="utf-8") as f:
        data = json.load(f)

    asyncio.run(process_json_tts(data, args.output, args.subtitle))

if __name__ == "__main__":
    main()