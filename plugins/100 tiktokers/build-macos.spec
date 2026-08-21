# -*- mode: python ; coding: utf-8 -*-
import sys
import os
from PyInstaller.utils.hooks import collect_all

block_cipher = None

datas = [
    ('assets', 'assets'),
    ('mouse_coords.json', '.'),
    ('opera_profiles.config.json', '.'),
    ('version_info.txt', '.'),
]
datas = [(src, dst) for src, dst in datas if os.path.exists(src)]

hiddenimports = [
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.http.h11_impl',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.protocols.websockets.websockets_impl',
    'uvicorn.lifespans',
    'uvicorn.lifespans.on',
    'uvicorn.lifespans.off',
    'fastapi',
    'fastapi.middleware',
    'fastapi.middleware.cors',
    'starlette',
    'starlette.routing',
    'starlette.responses',
    'starlette.middleware',
    'starlette.middleware.cors',
    'pydantic',
    'profiles_router',
    'accounts_router',
    'search_click_router',
    'like_click_router',
    'captcha_auto_router',
    'captcha_jigsaw_match',
    'captcha_mp3_to_txt',
    'comment_click_router',
    'opera_ai_router',
    'history_db',
    'goto_first_tab',
    'tiktok_live_caption',
    'pychrome',
    'websocket',
    'websockets',
    'psutil',
    'requests',
    'httpx',
    'sqlite3',
]

for pkg in ['fastapi', 'starlette', 'uvicorn', 'pydantic', 'pychrome', 'websocket']:
    try:
        sub_datas, sub_bins, sub_hidden = collect_all(pkg)
        datas += sub_datas
        hiddenimports += sub_hidden
    except Exception:
        pass

hiddenimports = list(set(hiddenimports))

excludes = [
    'torch',
    'torchvision',
    'torchaudio',
    'triton',
    'nvidia',
    'scipy',
    'matplotlib',
    'tkinter',
    'whisper',
]

a = Analysis(
    ['app.py'],
    pathex=['.'],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='100tiktok-macos',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
