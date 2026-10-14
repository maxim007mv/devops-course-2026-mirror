# Конфигурация виртуальной машины devops-vm

> ПР №5 «Удалённый сервер и безопасный доступ. SSH, sudo, UFW, DNS». Документ — исходные данные для Ansible-роли (ПР №11).
> Гипервизор: QEMU 10 на хостовой Linux-машине (режим TCG, т. к. аппаратное ускорение KVM на ней неработоспособно) вместо VirtualBox; адаптеры построены как аналоги NAT и Host-only VirtualBox.
> Скрипты: `infra/devops-vm/hypervisor/` (запуск ВМ), `infra/devops-vm/setup/` (настройка гостя), `scripts/audit.sh` (контроль).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя ВМ / hostname | `devops-vm` (FQDN `devops-vm.devops.local`) |
| ОС | Ubuntu Server 24.04.5 LTS (cloud image `noble-server-cloudimg-amd64.img`, ядро 6.8), cloud-init |
| ОЗУ | 2048 МБ |
| vCPU | 2 |
| Диск | 25 ГБ, qcow2 (динамически расширяемый), virtio |
| Запуск | `sudo ./hostonly-up.sh && sudo ./start-vm.sh` (из каталога с диском ВМ, скрипты — `infra/devops-vm/hypervisor/`) |

## 2. Сетевые интерфейсы

| Интерфейс гостя | Тип адаптера | Адрес | Назначение |
|---|---|---|---|
| `enp0s3` (MAC 52:54:00:12:34:01) | NAT (QEMU user-mode/slirp, сеть 10.0.2.0/24, шлюз 10.0.2.2, DNS 10.0.2.3) | 10.0.2.15/24 (DHCP) | доступ в Интернет, apt; вход по SSH только через проброс порта |
| `enp0s8` (MAC 52:54:00:12:34:02) | Host-only (tap `tap-devops` в мосте `hostonly0` хоста, 192.168.56.1/24, DHCP dnsmasq, без маршрутизации в Интернет) | 192.168.56.101/24 (DHCP, закреплён за MAC) | прямой доступ с хоста: `devops.local`, веб-сервер в ПР №6 |

Маршрут по умолчанию — только через `enp0s3` (для `enp0s8` в netplan `dhcp4-overrides: use-routes: false, use-dns: false`).

## 3. Правило проброса портов

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | (10.0.2.15) | **2222** (до задания 2 — 22) |

QEMU: `-netdev user,id=nat,hostfwd=tcp:127.0.0.1:2222-:2222`. Изменение «на лету» через монитор:
`hostfwd_remove nat tcp:127.0.0.1:2222` → `hostfwd_add nat tcp:127.0.0.1:2222-:2222` (`vm-monitor.py`).

## 4. Учётные записи

| Имя | UID | Группы | Аутентификация SSH |
|---|---|---|---|
| `student` | 1000 | student, adm, sudo, … | создана cloud-init; вход по SSH **запрещён** (`AllowUsers devops`), только консоль |
| `devops` | 1001 | devops, sudo, users | только ключ ed25519 `~/.ssh/devops_vm` (комментарий `devops-vm-key`); пароль — только для sudo |
| `root` | 0 | — | вход по SSH запрещён (`PermitRootLogin no`) |

`~/.ssh` = 700, `authorized_keys` = 600 (иначе sshd: `Authentication refused: bad ownership or modes`).
Создание: `sudo adduser devops && sudo usermod -aG sudo devops`; ключ: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`, `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1` (или `setup/01-user.sh`).
Клиент: `infra/devops-vm/client/ssh_config.example` → `~/.ssh/config` (`ssh devops`, `ssh devops.local`).

Отпечаток ключа хоста (ED25519): `SHA256:bPGA6/8frBA7rpIpWs6als2w42dSlEN779qEU085nKU` (сверен с `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`).

## 5. Служба SSH

* Файл: `/etc/ssh/sshd_config.d/99-hardening.conf` (копия — `infra/devops-vm/sshd/99-hardening.conf`); основной `sshd_config` не изменялся, резервная копия `/etc/ssh/sshd_config.backup`.
* Директивы: `Port 2222`, `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `PermitEmptyPasswords no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers devops`, `X11Forwarding no`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`.
* В `/etc/ssh/sshd_config.d/50-cloud-init.conf` (права 600, читать через sudo) строка `PasswordAuthentication yes` закомментирована — иначе она побеждает (первое значение).
* `ssh.socket` отключён (`systemctl disable --now ssh.socket`), `ssh.service` включён и перезапущен (`systemctl restart ssh`); убедиться, что порт 22 больше не прослушивается (`ss -tlnp`, `ps -C sshd -o pid,cmd`) — без перезапуска остаётся старый процесс со старой конфигурацией.
* Порядок: `sudo sshd -t` → `sudo systemctl restart ssh` → проверка во втором терминале, текущая сессия не закрывается.
* Проверка: `sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '`, `sudo ss -tlnp | grep sshd` → `0.0.0.0:2222`.
* Автоматизация: `sudo infra/devops-vm/setup/02-ssh-hardening.sh`.

## 6. Правила межсетевого экрана

* Политики: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`; logging `medium` (`/var/log/ufw.log`).
* Правила (IPv4 и v6):

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp | LIMIT IN | SSH rate-limited (≥6 соединений за 30 с с одного адреса — блок) |
| 80/tcp | ALLOW IN | HTTP (ПР №6) |
| 443/tcp | ALLOW IN | HTTPS (ПР №6) |

* Порядок: правила → `ufw enable` (никогда наоборот). Не использовать `ufw allow ssh` (= 22/tcp по `/etc/services`).
* Автоматизация: `sudo infra/devops-vm/setup/03-ufw.sh`. Снимок фактических правил: `infra/devops-vm/captured/`.

## 7. Снимки состояния

Внутренние снимки qcow2 (`qemu-img snapshot -l devops-vm.qcow2` / `info snapshots` в мониторе QEMU):

| Наименование | Момент создания (MSK) | Состояние |
|---|---|---|
| `01-clean-install` | 14.10.2026 09:37 | после `apt upgrade`, ВМ выключена (`qemu-img snapshot -c`) |
| `02-keys-configured` | 14.10.2026 09:44 | пользователь devops, ключ, `~/.ssh/config` (живой снимок `savevm`, с ОЗУ) |
| `03-ssh-hardened` | 14.10.2026 09:50 | задание 2 выполнено (живой снимок `savevm`) |

Откат: ВМ выключена — `qemu-img snapshot -a <имя> devops-vm.qcow2`; ВМ работает — `loadvm <имя>` в мониторе.

## 8. Локальное имя и разрешение имён

* Хост: `/etc/hosts` ← `192.168.56.101    devops.local` (`infra/devops-vm/client/hosts.fragment`).
* Гость: `hostnamectl set-hostname devops-vm`; в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm` (в cloud-образе её нет — добавить, `setup/04-hostname.sh`); `hostname -f` → `devops-vm.devops.local`.
* Порядок: `nsswitch.conf: hosts: files dns` → `/etc/hosts` → systemd-resolved (127.0.0.53, кэш) → DNS 10.0.2.3 (DHCP NAT).

## 9. Контроль

`bash scripts/audit.sh` на ВМ: код 0 — конфигурация корректна, 1 — есть нарушения.
