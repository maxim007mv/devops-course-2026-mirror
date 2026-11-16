#!/usr/bin/env bash
# Задание 2: drop-in 99-hardening.conf, нейтрализация 50-cloud-init.conf, отказ от ssh.socket, порт 2222.
# ВНИМАНИЕ: выполнять, не закрывая текущую сессию; проверять вход из второго терминала.
# После выполнения изменить проброс порта гипервизора: 127.0.0.1:2222 -> гость:2222.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ -f /etc/ssh/sshd_config.backup ]] || cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
install -m 644 "$HERE/../sshd/99-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf
# первое встреченное значение директивы побеждает -> закомментировать PasswordAuthentication yes в 50-cloud-init.conf
sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes  # disabled in PR5, see 99-hardening.conf/' \
    /etc/ssh/sshd_config.d/*.conf
grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/
sshd -t && echo "Конфигурация корректна"
sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) "
systemctl disable --now ssh.socket
systemctl enable --now ssh.service
systemctl restart ssh
# проверить, что порт 22 больше не прослушивается (без restart остаётся процесс со старой конфигурацией)
ss -tlnp | grep sshd
