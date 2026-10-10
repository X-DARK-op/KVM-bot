#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/X-DARK-op/KVM-bot.git"
WORK_DIR="/opt/KVM-bot"
APP_DIR="/opt/bloodcloud-kvm-bot"
SERVICE="bloodcloud-kvm-bot"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
step() { echo -e "\n${CYAN}==>${RESET} $*"; }
ok() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail() { local rc=$?; echo -e "\n${RED}[ERROR] Installer line ${BASH_LINENO[0]:-?} failed (exit $rc).${RESET}"; echo "Command: ${BASH_COMMAND:-unknown}"; echo "Scroll up for the original error. Installation stopped."; exit "$rc"; }
trap fail ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash install.sh"; exit 1
fi

clear 2>/dev/null || true
cat <<'BANNER'
 ____  _                 _   ____ _oud
| __ )| | ___   ___   __| | / ___| | ___  _   _  __| |
|  _ \| |/ _ \ / _ \ / _` | | |   | |/ _ \| | | |/ _` |
| |_) | | (_) | (_) | (_| | | |___| | (_) | |_| | (_| |
|____/|_|\___/ \___/ \__,_|  \____|_|\___/ \__,_|\__,_|
             KVM / QEMU Discord Bot Installer
BANNER

ask() {
  local var="$1" prompt="$2" default="${3:-}" value=""
  if [[ -n "$default" ]]; then read -r -p "$prompt [$default]: " value; value="${value:-$default}";
  else read -r -p "$prompt: " value; fi
  printf -v "$var" '%s' "$value"
}

step "Installing system packages (errors will be shown)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git unzip ca-certificates python3 python3-venv python3-pip qemu-system-x86 qemu-utils cloud-image-utils wget curl openssh-client

step "Downloading latest repository from GitHub"
if [[ -d "$WORK_DIR/.git" ]]; then
  git -C "$WORK_DIR" pull --ff-only
else
  if [[ -e "$WORK_DIR" ]]; then
    mv "$WORK_DIR" "${WORK_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  git clone "$REPO" "$WORK_DIR"
fi

ZIP="$WORK_DIR/BloodCloud-KVM-Bot.zip"
if [[ ! -f "$ZIP" ]]; then
  echo "Expected ZIP not found: $ZIP"; echo "Repository files:"; ls -la "$WORK_DIR"; exit 1
fi

step "Extracting bot files"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE:-}"' EXIT
unzip -oq "$ZIP" -d "$STAGE"
for f in bot-qemu.py qemu_backend.py webssh.html; do
  [[ -s "$STAGE/$f" ]] || { echo "Required file missing from ZIP: $f"; exit 1; }
done
mkdir -p "$APP_DIR" /var/lib/unixnodes-qemu/vms /var/lib/unixnodes-qemu/images
install -m 750 "$STAGE/bot-qemu.py" "$APP_DIR/bot.py"
install -m 640 "$STAGE/qemu_backend.py" "$APP_DIR/qemu_backend.py"
install -m 640 "$STAGE/webssh.html" "$APP_DIR/webssh.html"

step "Configure bot environment"
ENV_FILE="$APP_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  cp -a "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
  warn "Existing .env backed up. Enter values for the new configuration."
fi
ask DISCORD_TOKEN "Discord bot token" ""
[[ -n "$DISCORD_TOKEN" ]] || { echo "Discord token cannot be empty."; exit 1; }
ask BOT_NAME "Bot display name" "BloodCloud"
ask PREFIX "Command prefix" "!"
ask MAIN_ADMIN_ID "Main admin Discord user ID" ""
[[ "$MAIN_ADMIN_ID" =~ ^[0-9]+$ ]] || { echo "Admin ID must be a numeric Discord ID."; exit 1; }
ask VPS_USER_ROLE_ID "VPS user role ID (leave blank if not used)" "$MAIN_ADMIN_ID"
ask YOUR_SERVER_IP "Public server IP/domain" "127.0.0.1"
ask WEBSSH_SERVER_IP "Public WebSSH IP/domain" "$YOUR_SERVER_IP"
ask WEBSSH_PORT "WebSSH port" "5000"
[[ "$WEBSSH_PORT" =~ ^[0-9]+$ ]] && (( WEBSSH_PORT >= 1 && WEBSSH_PORT <= 65535 )) || { echo "Invalid WebSSH port."; exit 1; }
ask DEFAULT_STORAGE_POOL "Default storage pool label" "default"
ask DEFAULT_VPS_EXPIRATION_DAYS "Default VPS expiry in days" "30"
ask PUBLIC_VPS_MAX_RAM "Max RAM per VPS (GB)" "4"
ask PUBLIC_VPS_MAX_CPU "Max CPU cores per VPS" "2"
ask PUBLIC_VPS_MAX_DISK "Max disk per VPS (GB)" "50"
ask PUBLIC_VPS_MAX_PER_USER "Max VPS per user" "1"

cat > "$ENV_FILE" <<ENV
DISCORD_TOKEN=$DISCORD_TOKEN
BOT_NAME=$BOT_NAME
PREFIX=$PREFIX
YOUR_SERVER_IP=$YOUR_SERVER_IP
MAIN_ADMIN_ID=$MAIN_ADMIN_ID
VPS_USER_ROLE_ID=$VPS_USER_ROLE_ID
DEFAULT_STORAGE_POOL=$DEFAULT_STORAGE_POOL
BOT_VERSION=8.0-PRO
BOT_DEVELOPER=BloodCloud
BOT_THUMBNAIL_URL=https://i.imgur.com/xAx2gRQ.jpeg
BOT_ICON_URL=https://i.imgur.com/xAx2gRQ.jpeg
DEFAULT_VPS_EXPIRATION_DAYS=$DEFAULT_VPS_EXPIRATION_DAYS
EXPIRATION_WARNING_DAYS=1
HOST_MOTD=
PUBLIC_VPS_ENABLED=true
PUBLIC_VPS_MAX_RAM=$PUBLIC_VPS_MAX_RAM
PUBLIC_VPS_MAX_CPU=$PUBLIC_VPS_MAX_CPU
PUBLIC_VPS_MAX_DISK=$PUBLIC_VPS_MAX_DISK
PUBLIC_VPS_EXPIRY_DAYS=$DEFAULT_VPS_EXPIRATION_DAYS
PUBLIC_VPS_MAX_PER_USER=$PUBLIC_VPS_MAX_PER_USER
PUBLIC_VPS_MAX_PER_IP=1
PUBLIC_VPS_REQUIRE_VERIFICATION=false
PUBLIC_VPS_RENEWAL_ENABLED=true
PUBLIC_VPS_RENEWAL_DAYS=30
WEBSSH_ENABLED=true
WEBSSH_PORT=$WEBSSH_PORT
WEBSSH_SERVER_IP=$WEBSSH_SERVER_IP
WEBSSH_URL_FORMAT=http://{SERVER_IP}:{PORT}
QEMU_VPS_DIR=/var/lib/unixnodes-qemu
ENV
chmod 600 "$ENV_FILE"

step "Installing Python requirements"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/python" -m pip install --upgrade pip
"$APP_DIR/venv/bin/python" -m pip install discord.py python-dotenv requests paramiko flask flask-cors
"$APP_DIR/venv/bin/python" -m py_compile "$APP_DIR/bot.py" "$APP_DIR/qemu_backend.py"
ok "Python dependencies installed and Python syntax checked"

step "Creating systemd service"
cat > "/etc/systemd/system/${SERVICE}.service" <<UNIT
[Unit]
Description=BloodCloud KVM QEMU Discord Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/bot.py
Restart=on-failure
RestartSec=5
User=root
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now "$SERVICE"
sleep 2
if ! systemctl is-active --quiet "$SERVICE"; then
  echo -e "${RED}[ERROR] Service did not start. Recent logs:${RESET}"
  journalctl -u "$SERVICE" -n 80 --no-pager || true
  exit 1
fi

ok "Bot service is running"
echo
echo "Install complete."
echo "Service status: systemctl status $SERVICE --no-pager"
echo "Live logs:      journalctl -u $SERVICE -f"
echo "Stop bot:       systemctl stop $SERVICE"
echo "Restart bot:    systemctl restart $SERVICE"
echo "App directory:  $APP_DIR"
echo "Env file:       $ENV_FILE (permissions 600)"
warn "KVM acceleration is available only if /dev/kvm is accessible."
warn "Keep WebSSH behind HTTPS and access controls before exposing it publicly."
