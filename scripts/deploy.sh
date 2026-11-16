#!/usr/bin/env bash
# Деплой статического сайта на devops-vm через rsync (ПР6).
set -euo pipefail

REMOTE="${REMOTE:-devops}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/devops-site}"
SITE_URL="${SITE_URL:-https://devops.local}"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run]
  Синхронизирует каталог site/ из корня git-репозитория на \$REMOTE:\$REMOTE_DIR
  и проверяет доступность \$SITE_URL.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Неизвестный аргумент: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Ошибка: запустите скрипт из git-репозитория." >&2
  exit 1
}
LOCAL_DIR="${LOCAL_DIR:-$ROOT/site}"

if [[ ! -f "$LOCAL_DIR/index.html" ]]; then
  echo "Ошибка: не найден $LOCAL_DIR/index.html" >&2
  exit 1
fi

# Незакоммиченные изменения (tracked) или неотслеживаемые файлы в site/
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  echo "Ошибка: в репозитории есть незакоммиченные изменения. Сделайте commit перед деплоем." >&2
  git -C "$ROOT" status --short >&2
  exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain -- "$LOCAL_DIR")" ]]; then
  echo "Ошибка: в site/ есть неотслеживаемые или изменённые файлы." >&2
  git -C "$ROOT" status --short -- "$LOCAL_DIR" >&2
  exit 1
fi

RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ "$DRY_RUN" -eq 1 ]]; then
  RSYNC_OPTS+=(--dry-run)
  echo "[dry-run] Синхронизация $LOCAL_DIR/ -> ${REMOTE}:${REMOTE_DIR}/"
fi

rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR/" "${REMOTE}:${REMOTE_DIR}/"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Проверка HTTP пропущена."
  echo "HEAD=$(git -C "$ROOT" rev-parse --short HEAD)"
  exit 0
fi

# Проверка без SSH (curl к SITE_URL)
if [[ ! -f "$CA_CERT" ]]; then
  echo "Ошибка: CA-сертификат не найден: $CA_CERT" >&2
  exit 1
fi
if ! curl -fsS --cacert "$CA_CERT" "$SITE_URL/" -o /dev/null; then
  echo "Ошибка: сайт $SITE_URL недоступен после деплоя." >&2
  exit 1
fi

echo "Деплой успешен. HEAD=$(git -C "$ROOT" rev-parse --short HEAD) URL=$SITE_URL"
