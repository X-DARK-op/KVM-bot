#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/X-DARK-op/KVM-bot.git"
DIR="/opt/KVM-bot"

echo '=================================='
echo '       BLOOD CLOUD INSTALLER'
echo '=================================='

if [[ "$EUID" -ne 0 ]]; then
  echo 'Please run as root: sudo bash install.sh'
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git ca-certificates

if [[ -d "$DIR/.git" ]]; then
  echo '[INFO] Existing repository found; updating...'
  git -C "$DIR" pull --ff-only
else
  if [[ -e "$DIR" ]]; then
    echo "[ERROR] $DIR exists but is not a Git repository."
    echo 'Move it aside or change DIR in this script, then retry.'
    exit 1
  fi
  git clone "$REPO" "$DIR"
fi

cd "$DIR"

# Launch a setup script already provided by the repository, if present.
for installer in install-qemu-bot.sh setup.sh; do
  if [[ -f "$installer" ]]; then
    chmod +x "$installer"
    exec bash "./$installer"
  fi
done

echo
echo "[OK] Repository downloaded to: $DIR"
echo '[INFO] No install-qemu-bot.sh or setup.sh was found.'
echo 'Files in repository:'
ls -la
echo
echo 'This script cloned the repository but cannot complete bot setup'
echo 'unless the project has a setup script with the required install steps.'
