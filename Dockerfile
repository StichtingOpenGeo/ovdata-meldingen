# syntax=docker/dockerfile:1

FROM composer:2 AS composer_bin

FROM php:8.3-apache

# Exact skeleton tag. Must match the version composer.lock was generated
# against — change it and re-run ./update-lock.sh, never one without the other.
ARG FLARUM_VERSION=v1.8.19

ENV FLARUM_HOME=/flarum/app

# --- system + PHP extensions Flarum needs -----------------------------------
# mbstring, dom, tokenizer, curl, fileinfo, openssl and json are already
# compiled into the official php image; the rest we build here.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        unzip \
        default-mysql-client \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        libicu-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd zip exif intl pdo_mysql opcache; \
    a2enmod rewrite headers remoteip; \
    rm -rf /var/lib/apt/lists/*

RUN { \
      echo 'memory_limit = 256M'; \
      echo 'upload_max_filesize = 16M'; \
      echo 'post_max_size = 16M'; \
      echo 'max_execution_time = 120'; \
      echo 'opcache.enable = 1'; \
      echo 'opcache.memory_consumption = 192'; \
      echo 'opcache.max_accelerated_files = 20000'; \
      echo 'opcache.validate_timestamps = 1'; \
      echo 'opcache.revalidate_freq = 2'; \
    } > /usr/local/etc/php/conf.d/zz-flarum.ini

COPY --from=composer_bin /usr/bin/composer /usr/local/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_NO_INTERACTION=1

COPY apache-flarum.conf /etc/apache2/sites-available/000-default.conf
RUN echo 'ServerName localhost' > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername

# --- Flarum + FoF Gamification ----------------------------------------------
WORKDIR ${FLARUM_HOME}

# The skeleton supplies the application's own files — index.php, the flarum
# CLI, site.php, public/, storage/. --no-install skips dependency resolution:
# that is the lock file's job, below.
RUN set -eux; \
    composer create-project "flarum/flarum:${FLARUM_VERSION}" . \
        --no-install --no-scripts --prefer-dist

# Our pinned manifest and lock replace the skeleton's unpinned manifest. Both
# are generated as a pair by ./update-lock.sh; if the build fails here with
# "file not found", that script has not been run yet.
COPY composer.json composer.lock ./

# --no-dev + a lock file means this resolves nothing: every package, at every
# commit, is dictated by composer.lock. Two builds a year apart are identical.
RUN set -eux; \
    composer install --no-dev --prefer-dist --optimize-autoloader; \
    composer clear-cache; \
    chown -R www-data:www-data /flarum

# Site-level extenders and translations, layered over the skeleton's stubs.
COPY extend.php seed-tags.php tags.json ./
COPY locale ./locale/

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/flarum/app/storage", "/flarum/app/public/assets"]

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
