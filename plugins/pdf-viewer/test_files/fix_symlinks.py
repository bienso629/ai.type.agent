import os
import shutil

extract_to = r"C:\Users\Wing386\apps\pdf-viewer\models--opendatalab--MinerU2.5-Pro-2604-1.2B"

print("Fixing symlinks...")
fixed_count = 0
for root_dir, dirs, files in os.walk(extract_to):
    for file in files:
        file_path = os.path.join(root_dir, file)
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read(200).strip()
            
            # Check if it looks like a HuggingFace symlink pointing to blobs
            if content.startswith("../../blobs/") or content.startswith("..\\..\\blobs\\"):
                # Clean the content path just in case
                blob_rel_path = content.replace('/', os.sep)
                target_abs_path = os.path.normpath(os.path.join(os.path.dirname(file_path), blob_rel_path))
                
                if os.path.exists(target_abs_path):
                    os.remove(file_path)
                    shutil.copy2(target_abs_path, file_path)
                    fixed_count += 1
                    print(f"Fixed: {file}")
        except Exception as e:
            pass

print(f"Done! Fixed {fixed_count} files.")
