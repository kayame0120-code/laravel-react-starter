#!/usr/bin/env sh
set -e

# .fly/scripts/*.sh を名前順に実行する。
# 1本でも失敗したらここで起動を止める（set -e）。
# マイグレーションに失敗したまま supervisord を起動すると、
# テーブルが無い状態でアプリが応答してしまい、原因の特定が遅れる。
for f in /var/www/html/.fly/scripts/*.sh; do
    [ -e "$f" ] || continue
    echo "[entrypoint] running $f"
    bash "$f"
done

if [ $# -gt 0 ]; then
    # If we passed a command, run it as root
    exec "$@"
else
    exec supervisord -c /etc/supervisor/supervisord.conf
fi