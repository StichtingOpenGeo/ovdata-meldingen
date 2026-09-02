#!/usr/bin/env bash
#
# Regenerates composer.json + composer.lock as a matched pair, pinning every
# package Flarum and FoF Gamification pull in. Commit both files afterwards.
#
# Runs Composer in a throwaway container, so no PHP toolchain is needed on the
# host — only Docker. Re-run it whenever you change FLARUM_VERSION, bump
# GAMIFICATION_VERSION, or want to pick up upstream updates.
#
set -euo pipefail
cd "$(dirname "$0")"

# .env is the single source of truth for FLARUM_VERSION; docker compose passes
# the same value to the image build. Read the two keys we care about rather
# than sourcing the file — .env holds unquoted values with spaces in them,
# which compose parses happily but a shell would try to execute.
env_get() {
    [ -f .env ] || return 0
    sed -n "s/^[[:space:]]*$1=//p" .env | tail -n 1 \
        | sed -e "s/[[:space:]]*$//" -e "s/^\"\(.*\)\"$/\1/" -e "s/^'\(.*\)'$/\1/"
}

FLARUM_VERSION="${FLARUM_VERSION:-$(env_get FLARUM_VERSION)}"
FLARUM_VERSION="${FLARUM_VERSION:-v1.8.19}"
GAMIFICATION_VERSION="${GAMIFICATION_VERSION:-$(env_get GAMIFICATION_VERSION)}"
# Must match the PHP in the Dockerfile's base image. Resolution targets this
# version rather than whatever PHP the composer container happens to ship.
PHP_TARGET="${PHP_TARGET:-8.3.0}"

# docker run -e VAR passes these through by name, so they must be exported.
export FLARUM_VERSION GAMIFICATION_VERSION PHP_TARGET

command -v docker >/dev/null 2>&1 || {
    echo "update-lock.sh needs docker: sudo apt install docker.io" >&2
    exit 1
}

echo "Resolving flarum/flarum ${FLARUM_VERSION} + fof/gamification${GAMIFICATION_VERSION:+ $GAMIFICATION_VERSION} for PHP ${PHP_TARGET} ..."

docker run --rm \
    -v "$PWD:/lock" \
    -u "$(id -u):$(id -g)" \
    -e COMPOSER_HOME=/tmp/composer \
    -e FLARUM_VERSION -e GAMIFICATION_VERSION -e PHP_TARGET \
    composer:2 sh -eu -c '
        composer create-project "flarum/flarum:${FLARUM_VERSION}" /tmp/app \
            --no-install --no-scripts --prefer-dist --quiet
        cd /tmp/app

        # Target the runtime PHP explicitly. Without this the lock would be
        # resolved against the composer image PHP, which need not match.
        composer config platform.php "${PHP_TARGET}"

        # --no-install resolves and writes the lock without downloading.
        # ext-* requirements are ignored here because this container has none
        # of them; the real "composer install" in the Dockerfile runs on an
        # image that does, and enforces them properly there.
        composer require "fof/gamification${GAMIFICATION_VERSION:+:$GAMIFICATION_VERSION}" \
            --no-install --no-scripts "--ignore-platform-req=ext-*"

        cp composer.json composer.lock /lock/
    '

echo
echo "Wrote composer.json and composer.lock. Locked versions:"
python3 - <<'PY' 2>/dev/null || true
import json
lock = json.load(open("composer.lock"))
for pkg in lock["packages"]:
    if pkg["name"] in ("flarum/core", "fof/gamification", "fof/extend"):
        print(f"  {pkg['name']:24} {pkg['version']}")
print(f"  ({len(lock['packages'])} packages total)")
PY
echo
echo "Commit both files, then: docker compose up -d --build"
