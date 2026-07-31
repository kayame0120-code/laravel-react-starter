#!/usr/bin/env bash

# caches.sh（root実行）が作る config/route/view キャッシュを www-data 所有に戻す。
# root所有のままだと PHP-FPM(www-data) が storage/framework に書けず全リクエスト500になる。
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
