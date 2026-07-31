# syntax = docker/dockerfile:1
# ============================================================
#  laravel-react-starter / 本番イメージ
#
#  版の正本は fly.toml の [build.args]。
#  下の ARG 既定値は素の `docker build` 用の保険であり、
#  fly.toml と必ず同じ数字にする（検品スクリプトで照合する）。
# ============================================================
ARG PHP_VERSION=8.4
ARG NODE_VERSION=24

FROM ubuntu:22.04 AS base
LABEL fly_launch_runtime="laravel"

ARG PHP_VERSION
ARG NODE_VERSION

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
ADD .fly/php/packages/${PHP_VERSION}.txt /tmp/php-packages.txt

# --- PHP ${PHP_VERSION} ---
RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg2 ca-certificates git-core curl zip unzip \
    rsync vim-tiny htop sqlite3 nginx supervisor cron \
    && ln -sf /usr/bin/vim.tiny /etc/alternatives/vim \
    && ln -sf /etc/alternatives/vim /usr/bin/vim \
    && echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu jammy main" > /etc/apt/sources.list.d/ondrej-ubuntu-php.list \
    && apt-get update \
    && apt-get -y --no-install-recommends install $(cat /tmp/php-packages.txt) \
    && ln -sf /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm \
    && php -v \
    && mkdir -p /var/www/html/public && echo "index" > /var/www/html/public/index.php \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

# --- Node ${NODE_VERSION} ---
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && node -v && npm -v \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

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

RUN printf 'MAILTO=""\n* * * * * www-data /usr/bin/php /var/www/html/artisan schedule:run\n' > /etc/cron.d/laravel

EXPOSE 8080
ENTRYPOINT ["/entrypoint"]