import traceback
from transformers import AutoProcessor

model_name = r"C:\Users\Wing386\apps\pdf-viewer\models--opendatalab--MinerU2.5-Pro-2604-1.2B\snapshots\d3f5e08d073c21466bbabe21c71bb1e9c2e595da"

try:
    print("Testing AutoProcessor natively...")
    processor = AutoProcessor.from_pretrained(model_name, use_fast=True)
    print("AutoProcessor loaded successfully natively!")
except Exception as e:
    print("NATIVE ERROR:")
    traceback.print_exc()
