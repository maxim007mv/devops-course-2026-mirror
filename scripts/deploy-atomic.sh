#!/usr/bin/env bash
# Опциональный атомарный деплой (раздел 6): releases/<ts>, ln -s + mv -T current.
set -euo pipefail
REMOTE="${REMOTE:-devops}"
BASE="${BASE:-/var/www/devops-releases}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/devops-site}"
SITE_URL="${SITE_URL:-https://devops.local}"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="$ROOT/site"
[[ -f "$LOCAL_DIR/index.html" ]] || { echo "нет index.html" >&2; exit 1; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || { echo "грязное дерево" >&2; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)
ssh -o BatchMode=yes "$REMOTE" "sudo install -d -o devops -g devops '$BASE' '$BASE/releases' && mkdir -p '$BASE/releases/$TS'"
rsync -avz --delete --chmod=D755,F644 \
  -e "ssh -o BatchMode=yes" "$LOCAL_DIR/" "${REMOTE}:${BASE}/releases/$TS/"
ssh -o BatchMode=yes "$REMOTE" "set -e
  cd '$BASE'
  ln -sfn 'releases/$TS' current_tmp
  mv -T current_tmp current
  rsync -a --delete --chmod=D755,F644 current/ '$REMOTE_DIR/'
  ls -1dt releases/* | tail -n +6 | xargs -r rm -rf
  echo CURRENT=\$(readlink -f current)"
curl -fsS --cacert "$CA_CERT" "$SITE_URL/" -o /dev/null
echo "Atomic OK HEAD=$(git rev-parse --short HEAD)"
echo "Пояснение: ln -sfn меняет имя symlink неатомарно для читателей; mv -T атомарно заменяет inode каталога/ссылки."
