#!/usr/bin/env bash
#
# Dumps the database and the uploads to ./backups/, without taking the forum
# down. Run before anything that migrates or removes data.
#
# What is captured:
#   - the whole database (discussions, posts, users, votes, tags, settings)
#   - public/assets (avatars and any uploaded images)
#
# What is not, because it is all regenerated on boot: storage/ (cache, logs,
# sessions) and the compiled CSS/JS, which Flarum rebuilds on the next request.
#
set -euo pipefail
cd "$(dirname "$0")"

BACKUP_DIR="${BACKUP_DIR:-./backups}"
BACKUP_KEEP="${BACKUP_KEEP:-10}"

die() { printf 'backup: %s\n' "$*" >&2; exit 1; }

# Whether a compose service has a running container. Deliberately avoids
# "docker compose ps --status running --services": --status is not supported by
# every Compose version, and when it errors the empty output looks exactly like
# "the service is stopped" — reporting a running stack as down.
service_running() {
    cid="$(docker compose ps -q "$1" 2>/dev/null | head -n1)"
    [ -n "$cid" ] || return 1
    [ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" = "true" ]
}

service_running db \
    || die "the db service is not running — start it with 'make up' first"

mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
sql="$BACKUP_DIR/flarum-$stamp.sql.gz"
assets="$BACKUP_DIR/flarum-$stamp-assets.tar.gz"

# --single-transaction takes the dump inside one consistent InnoDB snapshot,
# so the forum keeps serving and the result is not a mix of before and after.
# The password goes through a defaults file rather than the command line, where
# it would show up in the container's process list.
echo "backup: dumping database ..."
docker compose exec -T db sh -c '
    f="$(mktemp)"; chmod 600 "$f"
    printf "[client]\npassword=\"%s\"\n" "$MARIADB_PASSWORD" > "$f"
    trap '\''rm -f "$f"'\'' EXIT
    mariadb-dump --defaults-extra-file="$f" \
        -u"$MARIADB_USER" \
        --single-transaction --quick \
        --default-character-set=utf8mb4 \
        "$MARIADB_DATABASE"
' | gzip > "$sql"

# A dump that ends mid-statement is worse than no dump, so prove it is whole
# before reporting success.
gzip -t "$sql" || die "the dump is not a valid gzip stream — not trusting it"
grep -q 'Dump completed' <(gzip -dc "$sql" | tail -5) \
    || die "the dump has no completion marker — it was truncated"

# Uploads need the forum container; the database does not. When the stack is
# stopped — which is exactly the case when "make update" starts it just to take
# this dump — skip them rather than failing the whole backup. The assets volume
# is not being modified while the container is down, so nothing is at risk.
if service_running flarum; then
    echo "backup: archiving uploads ..."
    docker compose exec -T flarum tar -czf - -C /flarum/app/public assets > "$assets"
    gzip -t "$assets" || die "the assets archive is not a valid gzip stream"
else
    echo "backup: the flarum service is not running — skipping uploads"
    echo "backup: (its volume is untouched; 'make backup' once it is up captures them)"
    rm -f "$assets"
    assets=""
fi

printf 'backup: %s (%s)\n' "$sql" "$(du -h "$sql" | cut -f1)"
[ -n "$assets" ] && printf 'backup: %s (%s)\n' "$assets" "$(du -h "$assets" | cut -f1)"
true

# Keep the last N pairs; old backups that silently fill the disk are their own
# kind of outage.
if [ "$BACKUP_KEEP" -gt 0 ]; then
    ls -1t "$BACKUP_DIR"/flarum-*.sql.gz 2>/dev/null | tail -n "+$((BACKUP_KEEP + 1))" | while read -r old; do
        echo "backup: pruning $(basename "$old")"
        rm -f "$old" "${old%.sql.gz}-assets.tar.gz"
    done
fi
