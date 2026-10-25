#!/data/data/com.termux/files/usr/bin/bash
#
# =============================================================
#   ☤ DCFBDAgent — Hermes Agent Installer (Termux)
# =============================================================

set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
CYN='\033[0;36m'; RST='\033[0m'

export TERM="${TERM:-xterm}"
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC
clear 2>/dev/null || true

echo -e "${CYN}=====================================================${RST}"
echo -e "${RED}         ☤ DCFBDAgent INSTALLER ☤"
echo -e "${CYN}=====================================================${RST}"

termux-wake-lock 2>/dev/null || true

echo -e "${YLW}📦 Updating Termux packages...${RST}"
yes | pkg update -y || true
yes | pkg upgrade -y || true
pkg install proot-distro -y

DISTRO="ubuntu"

if proot-distro list 2>/dev/null | grep -qiE "^[[:space:]]*\*?[[:space:]]*${DISTRO}([[:space:]]|$)"; then
    echo -e "${GRN}✅ Reusing existing container: ${DISTRO}${RST}"
else
    echo -e "${YLW}🐧 Installing Ubuntu container...${RST}"
    proot-distro install ${DISTRO}
fi

INNER_SCRIPT=$(mktemp)
trap 'rm -f "$INNER_SCRIPT"' EXIT

cat > "$INNER_SCRIPT" << 'INNER_EOF'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

echo "📦 Updating Ubuntu packages..."
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confold" || true

echo "🐍 Installing system dependencies..."
apt-get install -y --fix-broken \
    python3 python3-pip python3-venv python3-dev python-is-python3 \
    git curl wget build-essential \
    nodejs npm \
    libffi-dev libssl-dev pkg-config \
    ca-certificates

echo "✅ System dependencies installed."

PYBIN="python3"
if "$PYBIN" -c 'import sys; sys.exit(0 if (3, 11) <= sys.version_info < (3, 14) else 1)' 2>/dev/null; then
    echo "✅ Default Python is compatible."
else
    echo "⚠️ Installing Python 3.13 via uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh || true
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || python3 -m pip install --break-system-packages uv || true
    uv python install 3.13 || true
    if FOUND="$(uv python find 3.13 2>/dev/null)" && [ -x "$FOUND" ]; then
        PYBIN="$FOUND"
    fi
fi

REPO_DIR="$HOME/hermes-agent"

# আসল রিপোজিটরি থেকে ক্লোন করা হচ্ছে (কারণ আপনার রিপোতে সোর্স কোড নেই)
echo "📥 Cloning Hermes Agent repository..."
rm -rf "$REPO_DIR"
git clone --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/NousResearch/hermes-agent.git "$REPO_DIR"
cd "$REPO_DIR"

if [ -d "venv" ]; then
    rm -rf venv
fi

echo "🐍 Creating virtual environment..."
"$PYBIN" -m venv venv
source venv/bin/activate

# venv এর ভেতরে --break-system-packages কাজ করে না, তাই সাধারণ pip ব্যবহার
echo "⬆️  Upgrading pip, setuptools, wheel..."
pip install --upgrade pip setuptools wheel || true

echo "🔧 Installing Hermes Agent..."
# --force-reinstall ছাড়া ইন্সটল করা হচ্ছে
if ! pip install -e ".[all]"; then
    echo "⚠️  [all] extras failed, trying [termux]..."
    if ! pip install -e ".[termux]" -c constraints-termux.txt; then
        echo "⚠️  [termux] extras failed, trying base install..."
        if ! pip install -e "."; then
            echo "❌ Failed to install Hermes Agent"
            exit 1
        fi
    fi
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hermes" << 'LAUNCHER_EOF'
#!/bin/bash
cd "$HOME/hermes-agent"
source venv/bin/activate
exec hermes "$@"
LAUNCHER_EOF
chmod +x "$HOME/.local/bin/hermes"

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

echo "✅ Hermes Agent installed successfully inside Ubuntu!"
INNER_EOF

echo -e "${YLW}🚀 Running installation inside Ubuntu...${RST}"

if ! proot-distro login "$DISTRO" -- bash -s < "$INNER_SCRIPT"; then
    echo -e "${RED}❌ Installation inside Ubuntu failed.${RST}"
    exit 1
fi

echo -e "${CYN}===================================================${RST}"
echo -e "${GRN}     ✅ DCFBD Agent installed successfully!${RST}"
echo -e "${CYN}===================================================${RST}"

WRAPPER="$PREFIX/bin/hermes"
cat > "$WRAPPER" << WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/bash
exec proot-distro login "$DISTRO" -- bash -lc 'source ~/hermes-agent/venv/bin/activate && exec hermes "\$@"' hermes "\$@"
WRAPPER_EOF
chmod +x "$WRAPPER" 2>/dev/null || true

echo -e "${YLW}🌐 Starting Hermes Gateway in background...${RST}"
proot-distro login "$DISTRO" -- bash -c "cd ~/hermes-agent && source venv/bin/activate && nohup hermes gateway run > ~/gateway.log 2>&1 &" || true
sleep 3
echo -e "${GRN}✅ Gateway is starting in the background.${RST}"

echo -e "${YLW}🚀 Quick Start (from Termux, just type):${RST}"
echo -e "${CYN}   hermes setup      # Run first-time setup${RST}"
echo -e "${CYN}   hermes            # Start chatting${RST}"
echo -e "${CYN}   hermes gateway    # Run the gateway${RST}"
