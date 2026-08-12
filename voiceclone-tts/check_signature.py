import inspect
import sys

try:
    from omnivoice import OmniVoice
    
    sig = inspect.signature(OmniVoice.generate)
    print("OmniVoice.generate signature:")
    for name, param in sig.parameters.items():
        print(f"  {name}: {param.annotation} (default: {param.default})")
except Exception as e:
    print("Error:", e)
