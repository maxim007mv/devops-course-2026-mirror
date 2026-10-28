# infra/devops-vm — ПР №5 (SSH, sudo, UFW, DNS)

| Каталог | Содержимое |
|---|---|
| `hypervisor/` | запуск ВМ в QEMU: `hostonly-up.sh` (мост host-only 192.168.56.0/24 + DHCP), `start-vm.sh` (2 vCPU, 2048 МБ, 25 ГБ, NAT+hostfwd, host-only), `vm-monitor.py` (команды монитора: `savevm`, `info snapshots`, `hostfwd_add`), cloud-init (`user-data.example`, `meta-data`, `network-config`) |
| `setup/` | идемпотентные шаги настройки гостя в порядке выполнения (основа задач Ansible в ПР №11): `01-user.sh`, `02-ssh-hardening.sh`, `03-ufw.sh`, `04-hostname.sh` |
| `sshd/99-hardening.conf` | drop-in конфигурации sshd |
| `client/` | `~/.ssh/config` и запись hosts для хостовой системы |
| `captured/` | фактические выводы с ВМ: `sshd -T`, `ufw status verbose`, `/etc/ufw/user.rules`, `/etc/hosts` |

Описание конфигурации — `docs/server-setup.md`, аудит — `scripts/audit.sh`.
Закрытые ключи и пароли в репозиторий не помещаются.
