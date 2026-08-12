import torch
import torchaudio
import time

try:
    from omnivoice import OmniVoice
    
    model = OmniVoice.from_pretrained(
        r"D:\projects\apps\voiceclone-tts\models--k2-fsa--OmniVoice\models--k2-fsa--OmniVoice\snapshots\995b1b114ae423a4fd69b3834a6fd86423dd361c",
        device_map="cuda:0",
        dtype=torch.float16,
        local_files_only=True
    )
    
    texts = ["Xin chào, câu số một.", "Và đây là câu số hai.", "Cuối cùng là câu số ba."]
    print("Generating batch...")
    start = time.time()
    with torch.inference_mode():
        audio_tensors = model.generate(
            text=texts,
            num_step=10, 
            # using lower steps just for quick testing
        )
    print("Generation took:", time.time() - start)
    print("Type of audio_tensors:", type(audio_tensors))
    if isinstance(audio_tensors, list):
        print("Length:", len(audio_tensors))
        for i, t in enumerate(audio_tensors):
            print(f"Tensor {i} shape:", t.shape)
    else:
        print("Shape:", audio_tensors.shape)
        
except Exception as e:
    import traceback
    traceback.print_exc()
