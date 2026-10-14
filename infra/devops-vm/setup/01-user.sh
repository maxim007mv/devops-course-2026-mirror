#!/usr/bin/env bash
# Шаг 1.1/1.3: учётная запись devops в группе sudo + открытый ключ. Запуск: sudo ./01-user.sh "<содержимое devops_vm.pub>"
set -euo pipefail
USER_NAME=devops
PUBKEY="${1:?usage: $0 '<ssh-ed25519 AAAA... devops-vm-key>'}"
id "$USER_NAME" >/dev/null 2>&1 || adduser --gecos "" "$USER_NAME"     # интерактивно запросит пароль (нужен для sudo)
usermod -aG sudo "$USER_NAME"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" /home/$USER_NAME/.ssh
AK=/home/$USER_NAME/.ssh/authorized_keys
touch "$AK"; grep -qxF "$PUBKEY" "$AK" || echo "$PUBKEY" >> "$AK"
chown "$USER_NAME:$USER_NAME" "$AK"; chmod 600 "$AK"
groups "$USER_NAME"; stat -c '%a %n' /home/$USER_NAME/.ssh "$AK"
