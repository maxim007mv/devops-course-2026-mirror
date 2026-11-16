#!/usr/bin/env bash
# Задание 4.2: FQDN devops-vm.devops.local (в cloud-образе строки 127.0.1.1 нет -> добавляем, а не только sed)
set -euo pipefail
hostnamectl set-hostname devops-vm
if grep -q '^127.0.1.1' /etc/hosts; then
  sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
else
  echo '127.0.1.1 devops-vm.devops.local devops-vm' >> /etc/hosts
fi
hostname -f
