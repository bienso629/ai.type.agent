# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = ['gtts', 'pypdf', 'docx', 'lxml']
tmp_ret = collect_all('google.antigravity')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret_pdf = collect_all('pypdf')
datas += tmp_ret_pdf[0]; binaries += tmp_ret_pdf[1]; hiddenimports += tmp_ret_pdf[2]
tmp_ret_docx = collect_all('docx')
datas += tmp_ret_docx[0]; binaries += tmp_ret_docx[1]; hiddenimports += tmp_ret_docx[2]



a = Analysis(
    ['ai_agent.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='ai_agent_linux',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
