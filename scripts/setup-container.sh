#!/bin/bash
# Setup script to install development tools in the ubuntu-desktop container
# Run with: ./isopod.sh setup

set -e

echo "=== Updating package lists ==="
if ! apt-get update; then
    echo "=== Primary mirror failed, trying ports.ubuntu.com fallback ==="
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "armhf" ]; then
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list.d/*.list 2>/dev/null || true
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list 2>/dev/null || true
        apt-get update
    else
        echo "Not an ARM system, cannot use ports fallback"
        exit 1
    fi
fi

echo "=== Installing prerequisites ==="
apt-get install -y \
    software-properties-common \
    curl \
    wget \
    gnupg \
    ca-certificates \
    build-essential \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    liblzma-dev

echo "=== Adding deadsnakes PPA for Python versions ==="
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update

echo "=== Installing Python 3.14 with tkinter ==="
apt-get install -y python3.14 python3.14-venv python3.14-dev python3.14-tk

# Create 'python' symlink (Ubuntu doesn't have this by default, Poetry needs it)
ln -sf python3 /usr/bin/python

echo "=== Installing pip ==="
curl -sS https://bootstrap.pypa.io/get-pip.py | python3.14

echo "=== Installing Poetry ==="
curl -sSL https://install.python-poetry.org | python3.14 -

# Configure Poetry - disable in-project venvs (Poetry 2.2.x bug workaround)
/config/.local/bin/poetry config virtualenvs.in-project false

# Configure shell environment (overwrites to avoid duplicates on re-run)
# Disable lsiopy venv - it's read-only and breaks Poetry installs
cat > /config/.bashrc <<'BASHRC'
# Poetry and local binaries
export PATH="/config/.local/bin:$PATH"

# Cargo/Rust
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Disable lsiopy venv (read-only, breaks Poetry)
export PATH="${PATH//:\/lsiopy\/bin/}"
unset VIRTUAL_ENV

# Aliases
alias clauded="claude --dangerously-skip-permissions"
BASHRC

cat > /etc/profile.d/poetry.sh <<'EOF'
export PATH="/config/.local/bin:$PATH"
# Disable lsiopy venv - it's read-only and breaks Poetry
export PATH="${PATH//:\/lsiopy\/bin/}"
unset VIRTUAL_ENV
EOF

echo "=== Installing Rust ==="
# Install Rust for abc user
su - abc -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

echo "=== Installing Node.js and Claude Code CLI ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g @anthropic-ai/claude-code

echo "=== Installing VS Code ==="
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/packages.microsoft.gpg
# Detect architecture for VS Code package
ARCH=$(dpkg --print-architecture)
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get install -y code

echo "=== Installing VS Code extensions ==="
# Fix ownership of config directories (volumes may be created as root, setup runs as root)
mkdir -p /config/.config/Code /config/.vscode
mkdir -p /config/.config/google-chrome /config/.config/chromium
mkdir -p /config/.cache/pip /config/.cache/pypoetry/virtualenvs /config/.local
chown -R abc:abc /config/.config/Code /config/.vscode
chown -R abc:abc /config/.config/google-chrome /config/.config/chromium
chown -R abc:abc /config/.cache /config/.local

# Run as abc user since VS Code extensions install to user profile
su - abc -c "code --install-extension ms-python.python"
su - abc -c "code --install-extension ms-python.debugpy"
su - abc -c "code --install-extension rust-lang.rust-analyzer"
su - abc -c "code --install-extension anthropic.claude-code"

echo "=== Setting up SSH server ==="
apt-get install -y openssh-server
mkdir -p /var/run/sshd

# Create SSH config if it doesn't exist (some containers don't generate it)
if [[ ! -f /etc/ssh/sshd_config ]]; then
    mkdir -p /etc/ssh
    cat > /etc/ssh/sshd_config <<EOF
Port 22
PermitRootLogin no
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    # Generate host keys if missing
    ssh-keygen -A
else
    # Configure SSH for the abc user (default webtop user)
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
fi

# Create sshd privilege separation user if missing
if ! id -u sshd >/dev/null 2>&1; then
    useradd -r -d /var/empty -s /usr/sbin/nologin sshd
    mkdir -p /var/empty
    chmod 755 /var/empty
fi

# Set password for abc user (default: isopod)
echo "abc:isopod" | chpasswd

# Ensure abc user has a proper shell
usermod -s /bin/bash abc

# Create startup script for SSH (linuxserver.io uses s6-overlay)
mkdir -p /config/custom-cont-init.d
cat > /config/custom-cont-init.d/99-start-ssh <<'SSHSTARTUP'
#!/bin/bash
mkdir -p /var/run/sshd
/usr/sbin/sshd
SSHSTARTUP
chmod +x /config/custom-cont-init.d/99-start-ssh

# Start SSH now
mkdir -p /var/run/sshd
/usr/sbin/sshd || true

echo "=== Installing Claude in Chrome extension ==="
# Extension ID from Chrome Web Store: https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn
CLAUDE_EXTENSION_ID="fcoeoabgfenejglbffodgkkbkcdhcgfn"
EXTENSION_UPDATE_URL="https://clients2.google.com/service/update2/crx"

# Create policy directories for both Chromium and Chrome
mkdir -p /etc/chromium/policies/managed
mkdir -p /etc/opt/chrome/policies/managed

# Create policy JSON to force-install Claude in Chrome extension
POLICY_JSON=$(cat <<EOF
{
    "ExtensionInstallForcelist": [
        "${CLAUDE_EXTENSION_ID};${EXTENSION_UPDATE_URL}"
    ]
}
EOF
)

echo "$POLICY_JSON" > /etc/chromium/policies/managed/claude-extension.json
echo "$POLICY_JSON" > /etc/opt/chrome/policies/managed/claude-extension.json

echo "Claude in Chrome extension will be installed on first browser launch"
echo "Note: You'll need to log in to Claude on first use (credentials persist after)"

echo "=== Verifying installations ==="
python3.14 --version
/config/.local/bin/poetry --version || true
node --version
claude --version

echo ""
echo "=== Setup complete! ==="
echo "Projects mounted at: /projects/"
echo "Access desktop at: http://localhost:3000"
echo "SSH access: ssh abc@localhost -p 2222 (password: isopod)"
echo ""
echo "All installations persist across restarts"
echo "IMPORTANT: Change the default SSH password with passwd"

exit 0
