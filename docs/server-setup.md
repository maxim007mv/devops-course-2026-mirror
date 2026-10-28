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

### 2.1. Локальное имя и разрешение имён

* Хост: `/etc/hosts` ← `192.168.56.101    devops.local` (`infra/devops-vm/client/hosts.fragment`).
* Гость: `hostnamectl set-hostname devops-vm`; в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm` (в cloud-образе её нет — добавить, `setup/04-hostname.sh`); `hostname -f` → `devops-vm.devops.local`.
* Порядок: `nsswitch.conf: hosts: files dns` → `/etc/hosts` → systemd-resolved (127.0.0.53, кэш) → DNS 10.0.2.3 (DHCP NAT).

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
| `01-clean-install` | 14.10.2026 08:19 | после `apt upgrade`, ВМ выключена (`qemu-img snapshot -c`) |
| `02-keys-configured` | 21.10.2026 07:18 | пользователь devops, ключ, `~/.ssh/config` (живой снимок `savevm`, с ОЗУ; пересоздан после восстановления с 01) |
| `03-ssh-hardened` | 21.10.2026 07:18 | SSH на 2222, UFW, FQDN (живой снимок `savevm`) |
| `04-nginx-https` | 21.10.2026 07:26 | ПР6: Nginx, TLS, редирект 301 |
| `05-docker-compose` | 21.10.2026 09:58 | ПР7: Docker Engine, проект `~/app` (app + db) |

Откат: ВМ выключена — `qemu-img snapshot -a <имя> devops-vm.qcow2`; ВМ работает — `loadvm <имя>` в мониторе.

## 8. Веб-сервер

### 8.1. Nginx и виртуальный хост

* Пакет: `nginx` (`sudo apt install nginx`).
* Конфиг сайта: `/etc/nginx/sites-available/devops-site` (symlink в `sites-enabled/`), эталон в репозитории: `infra/devops-vm/nginx/devops-site`.
* `server_name devops.local`; корень `/var/www/devops-site` (владелец `devops:devops`).
* Порт 80: `return 301 https://$host$request_uri;`.
* Порт 443: `ssl_certificate /etc/ssl/certs/devops.crt`, `ssl_certificate_key /etc/ssl/private/devops.key`, `ssl_protocols TLSv1.2 TLSv1.3` (без HSTS).
* Логи: `/var/log/nginx/devops-site.access.log`, `devops-site.error.log`.
* Проверка: `sudo nginx -t && sudo systemctl reload nginx`.

### 8.2. TLS (самоподписанный сертификат)

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
sudo chmod 600 /etc/ssl/private/devops.key
```

На клиенте: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`, затем `curl --cacert ~/devops.crt https://devops.local/`.

Снимок ВМ после настройки: `04-nginx-https`.

### 8.3. Деплой

Скрипт `scripts/deploy.sh`: `rsync -avz --delete --chmod=D755,F644` каталога `site/` на `devops:/var/www/devops-site`, затем проверка `curl --cacert`. Требует чистого git working tree.

```bash
./scripts/deploy.sh --dry-run
./scripts/deploy.sh
```

## 9. Контейнеризация

### 9.1. Docker Engine

* Установка: официальный репозиторий Docker (`/etc/apt/sources.list.d/docker.list` → `https://download.docker.com/linux/ubuntu noble stable`, ключ `/etc/apt/keyrings/docker.asc`); пакет `docker.io` дистрибутива не используется.
* Пакеты: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`. Версии: Docker Engine 29.9.2, Docker Compose v5.6.0.
* Служба: `systemctl enable --now docker` (`systemctl is-active docker` → `active`).
* Группа `docker`: только `devops` (`sudo usermod -aG docker devops`, затем новая SSH-сессия). Участник группы фактически имеет права root — добавлять только учётные записи, которым уже выдан sudo.

### 9.2. Проект приложения

* Исходный код: каталог `app/` репозитория (`Dockerfile`, `.dockerignore`, `app.py`, `requirements.txt`, `docker-compose.yml`, `.env.example`).
* Расположение на сервере: `/home/devops/app` (`~/app`), доставка с хоста:
  `rsync -avz --delete --exclude=.env app/ devops:app/` (сначала с `--dry-run`).
* Образ: `devops-app:1.0` (база `python:3.12-slim`, процесс от системного пользователя `app`, gunicorn на `0.0.0.0:5000` внутри контейнера).
* Запуск: `cd ~/app && docker compose up -d --build`; состояние: `docker compose ps` (у `db` — `healthy`).

### 9.3. Секреты

* Файл `/home/devops/app/.env`, владелец `devops`, права `600`; создаётся только на сервере:
  `cp .env.example .env && chmod 600 .env && sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env`.
* `.env` исключён из репозитория (`.gitignore`), из контекста сборки (`.dockerignore`) и из доставки (`rsync --exclude=.env`). На хост не копируется.

### 9.4. Сеть, порты, тома

| Сервис | Образ | Публикация | Сеть |
|---|---|---|---|
| `app` | `devops-app:1.0` | `127.0.0.1:5000:5000` (только для Nginx на той же машине) | `app_backend` |
| `db` | `postgres:16-alpine` | не публикуется (5432 доступен только в сети проекта) | `app_backend` |

* Сеть проекта: `app_backend` (bridge, встроенный DNS: приложение обращается к СУБД по имени `db`, `DB_HOST=db`).
* Именованный том: `app_db_data` → `/var/lib/postgresql/data`. `docker compose down` том сохраняет; `docker compose down -v` удаляет данные безвозвратно.
* Опубликованные на `0.0.0.0` порты Docker обходят UFW (цепочки iptables `DOCKER`), поэтому порт приложения публикуется только на `127.0.0.1`.

### 9.5. Обратный прокси-сервер

В HTTPS-блок `/etc/nginx/sites-available/devops-site` (эталон: `infra/devops-vm/nginx/devops-site`) добавлено:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

* Проверка: `curl --cacert ~/devops.crt https://devops.local/app/` (счётчик), `.../app/health` → `ok`; статический ресурс `https://devops.local/` сохранён (200).
* Отказ контейнера приложения → `502 Bad Gateway`, в `devops-site.error.log`: `connect() failed (111: Connection refused) while connecting to upstream`.
* Снимок ВМ после настройки: `05-docker-compose`.

## 10. Контроль

`bash scripts/audit.sh` на ВМ (от имени devops): код 0 — конфигурация корректна, 1 — есть нарушения. Разделы: [1] SSH, [2] UFW, [3] учётные записи, [4] веб-сервер, [5] контейнеризация.
