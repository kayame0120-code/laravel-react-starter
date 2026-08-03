# syntax = docker/dockerfile:1
# ============================================================
#  laravel-react-starter / 本番イメージ
#
#  版の正本は下の ENV PHP_VERSION / ENV NODE_VERSION。
#  このファイルの中でしか定義されておらず、他の場所には存在しない。
#
#  ARG を使わない理由：
#    ARG は「外から --build-arg で渡せる」ための構文である。
#    渡せるということは、意図しない値が渡って気づけない、ということでもある。
#    実際、fly.toml と Dockerfile の両方に 8.4 と書いてあるのに
#    ビルドが 8.3 で走り、原因を特定できないという事故が起きた。
#    ENV は --build-arg で上書きできない。版はこの2行でしか変わらない。
# ============================================================

FROM ubuntu:22.04 AS base
LABEL fly_launch_runtime="laravel"

# --- 版の正本（ここだけを直す） ---
ENV PHP_VERSION=8.4 \
    NODE_VERSION=24

ENV DEBIAN_FRONTEND=noninteractive \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/composer \
    COMPOSER_MAX_PARALLEL_HTTP=24 \
    PHP_PM_MAX_CHILDREN=10 \
    PHP_PM_START_SERVERS=3 \
    PHP_MIN_SPARE_SERVERS=2 \
    PHP_MAX_SPARE_SERVERS=4 \
    PHP_DATE_TIMEZONE=UTC \
    PHP_DISPLAY_ERRORS=Off \
    PHP_ERROR_REPORTING=22527 \
    PHP_MEMORY_LIMIT=256M \
    PHP_MAX_EXECUTION_TIME=90 \
    PHP_POST_MAX_SIZE=100M \
    PHP_UPLOAD_MAX_FILE_SIZE=100M \
    PHP_ALLOW_URL_FOPEN=Off

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY .fly/php/ondrej_ubuntu_php.gpg /etc/apt/trusted.gpg.d/ondrej_ubuntu_php.gpg

# ADD は ENV を展開できないため、パッケージ一覧はディレクトリごと入れてから選ぶ。
COPY .fly/php/packages/ /tmp/php-packages/

# --- PHP ---
RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg2 ca-certificates git-core curl zip unzip \
    rsync vim-tiny htop sqlite3 nginx supervisor \
    && ln -sf /usr/bin/vim.tiny /etc/alternatives/vim \
    && ln -sf /etc/alternatives/vim /usr/bin/vim \
    && echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu jammy main" > /etc/apt/sources.list.d/ondrej-ubuntu-php.list \
    && apt-get update \
    && apt-get -y --no-install-recommends install $(cat /tmp/php-packages/${PHP_VERSION}.txt) \
    && ln -sf /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm \
    && php -v \
    && mkdir -p /var/www/html/public && echo "index" > /var/www/html/public/index.php \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/php-packages /tmp/* /var/tmp/* /usr/share/doc/*

# --- Node ---
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && node -v && npm -v \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 版が意図どおりに焼けたことを、ビルドの中で確かめてから先へ進む。
# 食い違ったままイメージが出来上がると、composer install で初めて露見して原因が読めない。
RUN php -v | grep -q "PHP ${PHP_VERSION}" \
    && node -v | grep -q "^v${NODE_VERSION}\." \
    && echo "version check passed: PHP ${PHP_VERSION} / Node ${NODE_VERSION}"

COPY .fly/nginx/ /etc/nginx/
COPY .fly/fpm/ /etc/php/${PHP_VERSION}/fpm/
COPY .fly/supervisor/ /etc/supervisor/
COPY .fly/entrypoint.sh /entrypoint
COPY .fly/start-nginx.sh /usr/local/bin/start-nginx
RUN chmod +x /entrypoint && chmod 754 /usr/local/bin/start-nginx

COPY . /var/www/html
WORKDIR /var/www/html

# artisan が起動できる下地を先に作る（composer の package:discover が bootstrap/cache へ書く）
RUN mkdir -p storage/logs \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache

# ★ composer が先。npm run build の途中で Wayfinder が
#   `php artisan wayfinder:generate` を叩くため、vendor/ が無いと必ず落ちる。
#   この2つの RUN の順序は絶対に入れ替えない。
RUN composer install --optimize-autoloader --no-dev --no-interaction --prefer-dist

RUN npm ci && npm run build && rm -rf node_modules

# optimize:clear は置かない（cache:clear が DB 接続を要求してビルドが落ちる）
# chown は単独 RUN にする（前段の失敗でスキップされると www-data が書けず全リクエスト500になる）
RUN chown -R www-data:www-data /var/www/html

# cron は入れない。スケジューラは外部から HTTP で起こす（README 参照）。
# auto_stop_machines を使う構成では、マシンが眠っている間コンテナ内 cron も眠るため、
# 定時実行は原理的に成立しない。動かないものを置くと「動くはず」と誤解される。

EXPOSE 8080
ENTRYPOINT ["/entrypoint"]