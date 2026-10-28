#!/usr/bin/env bash
# Задание 3: default deny incoming; разрешающие правила СОЗДАЮТСЯ ДО ufw enable.
set -euo pipefail
SSH_PORT=${SSH_PORT:-2222}
ufw default deny incoming
ufw default allow outgoing
ufw limit "${SSH_PORT}/tcp" comment 'SSH rate-limited'   # НЕ 'ufw allow ssh' (это порт 22 по /etc/services)
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw logging medium
ufw --force enable
ufw status verbose
