# -*- mode: python ; coding: utf-8 -*-
import sys
import os

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
    'uvicorn.lifespan.on',
    'uvicorn.lifespan.off',
    'fastapi',
    'fastapi.middleware',
    'fastapi.middleware.cors',
    'starlette',
    'starlette.routing',
    'starlette.responses',
    'starlette.middleware',
    'starlette.middleware.cors',
    'pydantic',
    'pydantic_core',
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
    'psutil',
    'requests',
    'httpx',
    'sqlite3',
    'email_validator',
]

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
    name='100tiktok-win',
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
