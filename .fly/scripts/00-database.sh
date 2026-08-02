#!/usr/bin/env bash
# ============================================================
#  00-database.sh — SQLite の置き場を整えてマイグレーションを実行する
#
#  なぜ entrypoint 側でやるのか：
#    release_command が作る一時マシンにはボリュームが付かない（Fly公式）。
#    /data に到達できないため、そこで migrate を走らせても意味が無い。
#
#  ファイル名が 00- で始まるのは、他のスタートアップスクリプトより先に
#  DBを用意するため。glob のアルファベット順に依存している。名前を変えない。
# ============================================================
set -euo pipefail

# release_command の一時マシンで実行された場合は何もしない。
# 現在このテンプレートは release_command を持たないが、
# 将来誰かが足したときに壊れないようにしておく。
if [ -n "${RELEASE_COMMAND:-}" ]; then
    echo "[00-database] release command machine detected. skipped."
    exit 0
fi

DB_PATH="${DB_DATABASE:-/data/database.sqlite}"
DB_DIR="$(dirname "$DB_PATH")"

# ボリュームはマウント直後 root 所有。ここを直さないと www-data が書けず
# 全リクエストが 500 になる（読めるが書けないので原因が分かりにくい）。
mkdir -p "$DB_DIR"
[ -f "$DB_PATH" ] || : > "$DB_PATH"
chown -R www-data:www-data "$DB_DIR"

# migrate は root で走るため、生成される -wal / -shm が root 所有になる。
# 実行後にもう一度 chown する。順序を入れ替えない。
php /var/www/html/artisan migrate --force --no-interaction

chown -R www-data:www-data "$DB_DIR"

echo "[00-database] ready: $DB_PATH"
