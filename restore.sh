#!/usr/bin/env bash
#
# Restores a dump made by ./backup.sh. This replaces the current database
# contents, so it asks before doing anything.
#
#   ./restore.sh backups/flarum-20260903-191500.sql.gz
#
# The matching -assets.tar.gz beside it is restored too when present.
#
set -euo pipefail
cd "$(dirname "$0")"

die() { printf 'restore: %s\n' "$*" >&2; exit 1; }

sql="${1:-}"
[ -n "$sql" ] || die "usage: ./restore.sh backups/flarum-<stamp>.sql.gz"
[ -f "$sql" ] || die "no such file: $sql"
gzip -t "$sql" || die "$sql is not a valid gzip file"

assets="${sql%.sql.gz}-assets.tar.gz"

docker compose ps --status running --services 2>/dev/null | grep -qx db \
    || die "the db service is not running — start it with 'make up' first"

if [ "${FORCE:-}" != "1" ]; then
    echo
    echo "  This REPLACES the current database with:"
    echo "    $sql"
    [ -f "$assets" ] && echo "    $assets"
    echo
    printf '  Type RESTORE to continue: '
    read -r answer
    [ "$answer" = "RESTORE" ] || die "aborted"
fi

echo "restore: loading database ..."
gzip -dc "$sql" | docker compose exec -T db sh -c '
    f="$(mktemp)"; chmod 600 "$f"
    printf "[client]\npassword=\"%s\"\n" "$MARIADB_PASSWORD" > "$f"
    trap '\''rm -f "$f"'\'' EXIT
    mariadb --defaults-extra-file="$f" -u"$MARIADB_USER" \
        --default-character-set=utf8mb4 "$MARIADB_DATABASE"
'

if [ -f "$assets" ]; then
    echo "restore: unpacking uploads ..."
    docker compose exec -T flarum tar -xzf - -C /flarum/app/public < "$assets"
fi

# Settings and the compiled frontend are cached; without this the forum would
# keep serving whatever the pre-restore state looked like.
echo "restore: clearing cache ..."
docker compose exec -T flarum php flarum cache:clear

echo "restore: done"
