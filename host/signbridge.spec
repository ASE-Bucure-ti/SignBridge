# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for SignBridge native host.

Builds a one-dir bundle including:
  - The signbridge Python package
  - PKCS#11 vendor library for the current platform
  - All Python dependencies (PyQt6, pyHanko, cryptography, etc.)

Usage:
  pyinstaller --clean signbridge.spec
"""

import platform
import os

# ─── Platform-specific PKCS#11 library ──────────────────────────────────────
system = platform.system()
pkcs11_binaries = []

if system == "Windows":
    lib = os.path.join("libs", "eTPKCS11.dll")
    if os.path.exists(lib):
        pkcs11_binaries.append((lib, "."))
elif system == "Linux":
    lib = os.path.join("libs", "libeTPkcs11.so")
    if os.path.exists(lib):
        pkcs11_binaries.append((lib, "."))
elif system == "Darwin":
    lib = os.path.join("libs", "libeToken.dylib")
    if os.path.exists(lib):
        pkcs11_binaries.append((lib, "."))
    # libeToken.dylib depends on OpenSSL 1.1 via @loader_path
    libcrypto = os.path.join("libs", "libcrypto.1.1.dylib")
    if os.path.exists(libcrypto):
        pkcs11_binaries.append((libcrypto, "."))

# ─── Analysis ───────────────────────────────────────────────────────────────

a = Analysis(
    ["signbridge/__main__.py"],
    pathex=["."],
    binaries=pkcs11_binaries,
    datas=[("logo.png", "."), ("logo.ico", ".")],
    hiddenimports=[
        # PyQt6
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtWidgets",
        "PyQt6.sip",
        # PKCS#11
        "pkcs11",
        "pkcs11.types",
        "pkcs11.mechanisms",
        "pkcs11.defaults",
        "pkcs11.attributes",
        "pkcs11.constants",
        "pkcs11.exceptions",
        "pkcs11._pkcs11",
        "pkcs11.util",
        "pkcs11.util.rsa",
        "pkcs11.util.x509",
        "pkcs11.util.dh",
        "pkcs11.util.dsa",
        "pkcs11.util.ec",
        # pyHanko
        "pyhanko",
        "pyhanko.sign",
        "pyhanko.sign.signers",
        "pyhanko.sign.fields",
        "pyhanko.sign.pkcs11",
        "pyhanko.pdf_utils",
        "pyhanko.pdf_utils.incremental_writer",
        "pyhanko_certvalidator",
        # cryptography
        "cryptography",
        "cryptography.x509",
        "cryptography.hazmat",
        "cryptography.hazmat.primitives",
        "cryptography.hazmat.primitives.serialization",
        "cryptography.hazmat.primitives.hashes",
        "cryptography.hazmat.primitives.asymmetric",
        "cryptography.hazmat.backends",
        "cryptography.hazmat.backends.openssl",
        # signxml / lxml (XML signing)
        "signxml",
        "signxml.signer",
        "signxml.verifier",
        "signxml.algorithms",
        "lxml",
        "lxml.etree",
        "lxml._elementpath",
        # asn1crypto
        "asn1crypto",
        "asn1crypto.x509",
        "asn1crypto.core",
        "asn1crypto.algos",
        # requests
        "requests",
        "urllib3",
        "certifi",
        "charset_normalizer",
        "idna",
        # Other
        "hashlib",
        "json",
        "struct",
        "base64",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "tkinter",
        "unittest",
        "test",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SignBridge",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # Required for native messaging stdin/stdout
    icon="logo.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="SignBridge",
)
