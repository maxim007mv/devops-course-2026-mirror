#!/usr/bin/env bash
# Аудит базовой конфигурации сервера devops-vm (ПР №5–7).
# Код возврата: 0 — все проверки пройдены, 1 — есть нарушения (пригодно для CI, ПР №10).
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]    $desc"; ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
SSHD_T="$(sudo sshd -T 2>/dev/null)"
check "Вход от имени root запрещён"        "no" "$(awk '/^permitrootlogin/{print $2}' <<<"$SSHD_T")"
check "Парольная аутентификация отключена" "no" "$(awk '/^passwordauthentication/{print $2}' <<<"$SSHD_T")"
# TODO 1: значение параметра port отлично от 22
SSH_PORT="$(awk '/^port /{print $2; exit}' <<<"$SSHD_T")"
check "Порт SSH отличен от 22 (port=${SSH_PORT:-?})" "yes" "$([[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]] && echo yes || echo no)"
# TODO 2: значение параметра maxauthtries равно 3
check "MaxAuthTries равно 3" "3" "$(awk '/^maxauthtries/{print $2}' <<<"$SSHD_T")"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: политика по умолчанию для входящего трафика равна deny
check "Политика по умолчанию для входящих: deny" "deny" \
      "$(sudo ufw status verbose | awk -F'[:(,]' '/^Default:/{gsub(/ /,"",$2); print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "              %s (uid=%s)\n",$1,$3}' /etc/passwd


# [4] Веб-сервер
echo "[4] Веб-сервер"
if systemctl is-active --quiet nginx; then
  check "nginx активен" "active" "active"
else
  check "nginx активен" "active" "inactive"
fi
if sudo nginx -t >/dev/null 2>&1; then
  check "nginx -t успешен" "ok" "ok"
else
  check "nginx -t успешен" "ok" "fail"
fi
if [[ -f /etc/ssl/certs/devops.crt ]] && openssl x509 -in /etc/ssl/certs/devops.crt -checkend $((30*86400)) >/dev/null 2>&1; then
  check "сертификат devops.crt ≥30 дней" "ok" "ok"
else
  check "сертификат devops.crt ≥30 дней" "ok" "fail"
fi
WW=$(find /var/www/devops-site -perm -o+w 2>/dev/null | head -1 || true)
KEYMODE=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo missing)
if [[ -z "$WW" && "$KEYMODE" == "600" ]]; then
  check "нет o+w в сайте и ключ 600" "ok" "ok"
else
  check "нет o+w в сайте и ключ 600" "ok" "fail"
fi

# [5] Контейнеризация
echo "[5] Контейнеризация"
APP_DIR="${APP_DIR:-$HOME/app}"
check "Служба docker активна" "active" "$(systemctl is-active docker 2>/dev/null)"
check "СУБД app-db-1 в состоянии healthy" "healthy" \
      "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo absent)"
# порты 5000 и 5432 допускаются только на 127.0.0.1
EXPOSED="$(ss -tlnH | awk '{print $4}' | grep -E ':(5000|5432)$' | grep -v '^127\.0\.0\.1:' | sort -u | paste -sd, -)"
check "Порты 5000/5432 только на 127.0.0.1" "none" "${EXPOSED:-none}"
check "Права файла $APP_DIR/.env равны 600" "600" "$(stat -c '%a' "$APP_DIR/.env" 2>/dev/null || echo missing)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
