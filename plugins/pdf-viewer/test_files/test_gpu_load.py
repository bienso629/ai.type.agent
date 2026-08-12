import torch
import traceback
from transformers import Qwen2VLForConditionalGeneration

model_name = r"C:\Users\Wing386\apps\pdf-viewer\models--opendatalab--MinerU2.5-Pro-2604-1.2B\snapshots\d3f5e08d073c21466bbabe21c71bb1e9c2e595da"

try:
    print("Testing GPU load...")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = "auto" if device == "cuda" else torch.float32
    
    print(f"Device: {device}, Dtype: {dtype}")
    
    model = Qwen2VLForConditionalGeneration.from_pretrained(
        model_name, 
        torch_dtype=dtype, 
        device_map={"": "cuda"} if device == "cuda" else {"": "cpu"}
    )
    print("Successfully loaded to GPU!")
except Exception as e:
    print("FAILED TO LOAD MODEL:")
    traceback.print_exc()
