#!/data/data/com.termux/files/usr/bin/bash
#
# =============================================================
#   ☤ DCFBDAgent — Hermes Agent Installer (Termux)
#   Tool:  DCFBDHermesAgent
#   Developer: Dark Sniper
#   Team: DarkNet Cyber Force BD
#   Repo:  https://github.com/darksniper4/DCFBDAgent
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
echo -e "${GRN}       Tool: DCFBDAgent | Developer: DarkSniper${RST}"
echo -e "${CYN}=====================================================${RST}"
echo -e "${GRN}          Team: DarkNet Cyber Force BD${RST}"
echo -e "${CYN}=====================================================${RST}"
echo ""

termux-wake-lock 2>/dev/null || true

echo -e "${YLW}📦 Updating Termux packages...${RST}"
if ! yes | pkg update -y 2>&1; then
    echo -e "${YLW}⚠️  pkg update returned an error.${RST}"
    apt --fix-broken install -y 2>&1 || true
    yes | pkg update -y 2>&1 || true
fi

echo -e "${YLW}📦 Upgrading Termux packages...${RST}"
yes | pkg upgrade -y 2>&1 || true

echo -e "${YLW}🔧 Ensuring proot-distro is installed...${RST}"
pkg install proot-distro -y

# --- Container setup ---
DISTRO="${HERMES_DISTRO:-}"
ROOTFS_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro"

container_exists() {
    proot-distro list 2>/dev/null | grep -qiE "^[[:space:]]*\*?[[:space:]]*$1([[:space:]]|$)" && return 0
    [ -d "$ROOTFS_DIR/installed-rootfs/$1" ] && return 0
    [ -f "$ROOTFS_DIR/containers/$1/manifest.json" ] && [ -d "$ROOTFS_DIR/containers/$1/rootfs" ] && return 0
    return 1
}

if [ -z "$DISTRO" ]; then
    for name in ubuntu-hermes hermes2 hermes3 hermes4 hermes ubuntu; do
        if container_exists "$name"; then
            DISTRO="$name"
            echo -e "${GRN}✅ Reusing existing container: ${name}${RST}"
            break
        fi
    done
fi

if [ -z "$DISTRO" ]; then
    DISTRO="ubuntu"
    echo -e "${YLW}🐧 Installing Ubuntu container (may take a few minutes)...${RST}"
    if ! proot-distro install ubuntu 2>&1; then
        echo -e "${YLW}⚠️  Install reported an issue — assuming 'ubuntu' exists, reusing it.${RST}"
    fi
    echo -e "${GRN}✅ Ubuntu container ready${RST}"
fi

INNER_SCRIPT=$(mktemp)
trap 'rm -f "$INNER_SCRIPT"' EXIT

cat > "$INNER_SCRIPT" << 'INNER_EOF'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

echo "📦 Updating Ubuntu packages..."
apt-get update -qq
apt-get upgrade -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 || true

echo "🐍 Installing system dependencies..."
apt-get install -y -o Dpkg::Options::="--force-confold" \
    python3 python3-pip python3-venv python3-dev python-is-python3 \
    git curl wget build-essential \
    nodejs npm \
    libffi-dev libssl-dev pkg-config \
    ca-certificates >/dev/null 2>&1

PYBIN="python3"
if "$PYBIN" -c 'import sys; sys.exit(0 if (3, 11) <= sys.version_info < (3, 14) else 1)' 2>/dev/null; then
    echo "✅ Default Python is compatible: $("$PYBIN" --version 2>&1)"
else
    echo "⚠️  hermes-agent needs Python <3.14 — installing Python 3.13 via uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || python3 -m pip install --break-system-packages uv >/dev/null 2>&1 || true
    uv python install 3.13 >/dev/null 2>&1 || true
    if FOUND="$(uv python find 3.13 2>/dev/null)" && [ -x "$FOUND" ]; then
        PYBIN="$FOUND"
    fi
    echo "✅ Using $("$PYBIN" --version 2>&1 || echo "$PYBIN")"
fi

REPO_DIR="$HOME/hermes-agent"

if [ -d "$REPO_DIR/.git" ]; then
    echo "🔄 Updating existing hermes-agent repository..."
    cd "$REPO_DIR"
    git fetch origin
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || git reset --hard origin/master 2>/dev/null || true
else
    echo "📥 Cloning Hermes Agent repository..."
    rm -rf "$REPO_DIR"
    git clone --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/NousResearch/hermes-agent.git "$REPO_DIR"
    cd "$REPO_DIR"
fi

cd "$REPO_DIR"

if [ -d "venv" ]; then
    echo "♻️  Recreating virtual environment..."
    rm -rf venv
fi

echo "🐍 Creating virtual environment..."
# venv তৈরি করার জন্য uv বাদ দিয়ে সরাসরি পাইথন ব্যবহার করা হলো
"$PYBIN" -m venv venv || { echo "❌ venv creation failed"; exit 1; }
source venv/bin/activate

# uv বাদ দিয়ে সরাসরি pip ব্যবহার করার ফাংশন
pipi() {
    "$PWD/venv/bin/python" -m pip --break-system-packages "$@" \
        || "$PWD/venv/bin/python" -m pip "$@"
}

echo "⬆️  Upgrading pip, setuptools, wheel..."
pipi install --upgrade pip setuptools wheel || true

echo "🔧 Installing Hermes Agent (this can take 5–10 minutes)..."
# --force-reinstall দিয়ে সব প্যাকেজ নিশ্চিত করা হলো
if ! pipi install -e ".[all]" --force-reinstall; then
    echo "⚠️  [all] extras failed, trying [termux]..."
    if ! pipi install -e ".[termux]" -c constraints-termux.txt --force-reinstall; then
        echo "⚠️  [termux] extras failed, trying base install..."
        if ! pipi install -e "." --force-reinstall; then
            echo "❌ Failed to install Hermes Agent"
            echo "❌ Last error is shown above. Please share it for a fix."
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

echo ""
echo "✅ Hermes Agent installed successfully inside Ubuntu!"
INNER_EOF

echo -e "${YLW}🚀 Running installation inside Ubuntu...${RST}"
echo -e "${YLW}   (This may take 5–15 minutes depending on your connection)${RST}"
echo ""

if ! proot-distro login "$DISTRO" -- bash -s < "$INNER_SCRIPT"; then
    echo -e "${RED}❌ Installation inside Ubuntu failed${RST}"
    exit 1
fi

echo ""
echo -e "${CYN}===================================================${RST}"
echo -e "${GRN}     ✅ DCFBD Agent installed successfully!${RST}"
echo -e "${CYN}===================================================${RST}"
echo ""

# Termux লেভেলের 'hermes' র্যাপার তৈরি
WRAPPER="$PREFIX/bin/hermes"
cat > "$WRAPPER" << WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/bash
# DCFBD Agent - Termux-level launcher for Hermes Agent
exec proot-distro login "$DISTRO" -- bash -lc 'source ~/hermes-agent/venv/bin/activate && exec hermes "\$@"' hermes "\$@"
WRAPPER_EOF
chmod +x "$WRAPPER" 2>/dev/null || true

# --- অটোমেটিক গেটওয়ে চালু করা (ব্যাকগ্রাউন্ডে) ---
echo -e "${YLW}🌐 Starting Hermes Gateway in background...${RST}"
proot-distro login "$DISTRO" -- bash -c "cd ~/hermes-agent && source venv/bin/activate && nohup hermes gateway run > ~/gateway.log 2>&1 &" || true
sleep 3
echo -e "${GRN}✅ Gateway is starting in the background.${RST}"

echo -e "${YLW}🚀 Quick Start (from Termux, just type):${RST}"
echo -e "${CYN}   hermes setup      # Run first-time setup${RST}"
echo -e "${CYN}   hermes            # Start chatting${RST}"
echo -e "${CYN}   hermes gateway    # Run the gateway${RST}"
echo ""
echo -e "${YLW}📖 Manual path (if 'hermes' wrapper is missing):${RST}"
echo -e "${CYN}   proot-distro login $DISTRO${RST}"
echo -e "${CYN}   cd hermes-agent && source venv/bin/activate${RST}"
echo -e "${CYN}   hermes${RST}"
echo ""
echo -e "${GRN}💡 Need help? Visit: https://github.com/darksniper4/DCFBDAgent${RST}"
