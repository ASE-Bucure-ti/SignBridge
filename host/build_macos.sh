#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — macOS Build Script
#  Builds a one-dir PyInstaller bundle in dist/SignBridge/
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo " SignBridge - Production Build (macOS)"
echo "========================================"
echo

# ── Find a suitable Python (>= 3.10) ───────────────────────────────────
PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3.10; do
    if command -v "$candidate" &>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    # Fall back to python3 and check its version
    if command -v python3 &>/dev/null; then
        PY_VER=$(python3 -c 'import sys; print(sys.version_info.minor)')
        if [ "$PY_VER" -ge 10 ]; then
            PYTHON="python3"
        else
            echo "ERROR: Python >= 3.10 is required (found 3.$PY_VER)"
            echo "Install via: brew install python@3.12"
            exit 1
        fi
    else
        echo "ERROR: Python 3 is not installed"
        echo "Install via: brew install python@3.12"
        exit 1
    fi
fi

echo "[1/7] Python version:"
$PYTHON --version

# ── Virtual environment ─────────────────────────────────────────────────
if [ ! -d "venv" ]; then
    echo "[2/7] Creating virtual environment..."
    $PYTHON -m venv venv
else
    # Recreate if existing venv uses a different Python
    VENV_PY_VER=$(./venv/bin/python3 --version 2>/dev/null || echo "none")
    WANT_PY_VER=$($PYTHON --version)
    if [ "$VENV_PY_VER" != "$WANT_PY_VER" ]; then
        echo "[2/7] Recreating virtual environment ($VENV_PY_VER → $WANT_PY_VER)..."
        rm -rf venv
        $PYTHON -m venv venv
    else
        echo "[2/7] Using existing virtual environment..."
    fi
fi

echo "[3/7] Activating virtual environment..."
source venv/bin/activate

# ── Install dependencies ────────────────────────────────────────────────
echo "[4/7] Installing dependencies..."
pip install --upgrade pip wheel setuptools
pip install -r requirements.txt

# ── Verify PKCS#11 library ──────────────────────────────────────────────
DYLIB="libs/libeToken.dylib"
echo "[5/7] Checking PKCS#11 library..."
if [ -f "$DYLIB" ]; then
    echo "Found: $DYLIB"
    # Remove quarantine attribute
    xattr -r -d com.apple.quarantine "$DYLIB" 2>/dev/null || true

    # libeToken.dylib requires libcrypto.1.1.dylib via @loader_path
    LIBCRYPTO="libs/libcrypto.1.1.dylib"
    if [ ! -f "$LIBCRYPTO" ]; then
        echo "Locating libcrypto.1.1.dylib (required by libeToken)..."
        BREW_LIBCRYPTO="$(brew --prefix openssl@1.1 2>/dev/null)/lib/libcrypto.1.1.dylib"
        if [ -f "$BREW_LIBCRYPTO" ]; then
            cp "$BREW_LIBCRYPTO" "$LIBCRYPTO"
            echo "Copied: $BREW_LIBCRYPTO → $LIBCRYPTO"
        else
            echo "WARNING: libcrypto.1.1.dylib not found. Install with: brew install openssl@1.1"
            echo "The eToken PKCS#11 library may fail to load at runtime."
        fi
    else
        echo "Found: $LIBCRYPTO"
    fi
    xattr -r -d com.apple.quarantine libs/ 2>/dev/null || true
else
    echo "WARNING: $DYLIB not found"
    echo "HSM operations will require the vendor library at runtime"
fi

# ── Clean previous build ───────────────────────────────────────────────
echo "[6/7] Cleaning previous builds..."
rm -rf dist build

# ── Build ───────────────────────────────────────────────────────────────
echo "[7/7] Building with PyInstaller..."
echo
pyinstaller --clean signbridge.spec

BIN="dist/SignBridge/SignBridge"
if [ -f "$BIN" ]; then
    echo
    echo "Removing quarantine from dist..."
    xattr -r -d com.apple.quarantine dist 2>/dev/null || true

    echo "Ad-hoc code signing..."
    # Sign all binaries
    find "dist/SignBridge" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0 |
        while IFS= read -r -d '' bin; do
            codesign --remove-signature "$bin" 2>/dev/null || true
            codesign --force --sign - "$bin" 2>/dev/null || true
        done
    codesign --force --deep --sign - "$BIN" 2>/dev/null || true

    echo
    echo "========================================"
    echo " BUILD SUCCESSFUL"
    echo "========================================"
    echo "Executable: $BIN"
    echo
    echo "Next steps:"
    echo "  1. python3 install/register_host.py"
    echo "  2. Load the extension in Chrome/Firefox/Edge"
    echo "  3. Test from the web app"
else
    echo
    echo "========================================"
    echo " BUILD FAILED"
    echo "========================================"
    exit 1
fi
