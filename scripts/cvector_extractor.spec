# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['extract_vectors.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['scipy', 'numpy', 'pandas', 'tkinter', '_tkinter', 'tcl', 'tk', 'torch', 'tensorflow', 'matplotlib', 'PyQt5', 'PyQt6', 'PySide2', 'PySide6', 'PIL', 'Pillow', 'IPython', 'jedi', 'jsonschema', 'aiohttp', 'asyncio', 'unittest', 'pydoc', 'doctest', 'test', 'setuptools', 'pkg_resources', 'distutils', 'sqlite3', 'xml', 'xmlrpc', 'email', 'html', 'http', 'urllib3', 'certifi', 'cryptography', 'OpenSSL'],
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
    name='cvector_extractor',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
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
