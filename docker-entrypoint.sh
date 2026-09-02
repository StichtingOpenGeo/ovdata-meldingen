#!/usr/bin/env bash
#
# Installs Flarum on first boot, then keeps it in sync with the environment on
# every subsequent boot. Safe to run repeatedly: everything here is idempotent.
#
set -euo pipefail

APP=/flarum/app

: "${DB_HOST:=db}"
: "${DB_PORT:=3306}"
: "${DB_NAME:=flarum}"
: "${DB_USER:=flarum}"
: "${DB_PASS:=}"
: "${DB_PREFIX:=}"

: "${FORUM_URL:=http://localhost:8888}"
: "${FORUM_TITLE:=Flarum}"
: "${ADMIN_USER:=admin}"
: "${ADMIN_PASS:=}"
: "${ADMIN_MAIL:=admin@example.com}"
: "${FLARUM_DEBUG:=false}"
# Default language for the forum. Users can pick any enabled language pack
# from their own settings; this is only what guests and new accounts get.
: "${FORUM_LOCALE:=nl}"

# Primary tags (Flarum's categories) to create on first install, as JSON.
# Set SEED_TAGS_ALWAYS=true to re-run on every boot; the seeder only ever adds
# slugs that are missing, so it never overwrites edits made in the admin panel.
: "${SEED_TAGS_FILE:=$APP/tags.json}"
: "${SEED_TAGS_ALWAYS:=false}"

# Mail. "log" writes messages to storage/logs/flarum.log, which is what you
# want locally: registration confirmation links land in the log instead of
# vanishing into a mail server that isn't there.
: "${MAIL_DRIVER:=log}"
: "${MAIL_FROM:=noreply@localhost}"
: "${MAIL_HOST:=}"
: "${MAIL_PORT:=}"
: "${MAIL_USERNAME:=}"
: "${MAIL_PASSWORD:=}"
: "${MAIL_ENCRYPTION:=}"

# Extensions to enable on top of Flarum's own bundled set, comma separated.
: "${ENABLE_EXTENSIONS:=fof-gamification,flarum-lang-dutch}"

# Voting behaviour, applied once at install time. Change them later in
# Admin -> Gamification; this script will not overwrite your choices.
: "${VOTE_FIRST_POST_ONLY:=true}"     # vote on topics only, not on replies
: "${VOTE_ALLOW_SELF_VOTES:=false}"
: "${VOTE_UPVOTES_ONLY:=false}"
: "${VOTE_LIST_LAYOUT:=true}"         # vote arrows on the discussion list
: "${VOTE_SHOW_ON_LIST:=true}"        # vote totals on the discussion list

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

bool01() { case "${1,,}" in 1|true|yes|on) echo 1 ;; *) echo 0 ;; esac; }

# Debian's default-mysql-client is MariaDB's; recent versions drop the "mysql"
# compatibility symlink, so take whichever is actually on PATH.
if command -v mariadb >/dev/null 2>&1; then MYSQL_BIN=mariadb; else MYSQL_BIN=mysql; fi

mysql_q() {
    MYSQL_PWD="$DB_PASS" "$MYSQL_BIN" --protocol=TCP \
        -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" "$@"
}

flarum() { php "$APP/flarum" "$@"; }

# --- wait for the database ---------------------------------------------------
log "waiting for MySQL at ${DB_HOST}:${DB_PORT} ..."
for _ in $(seq 1 90); do
    if mysql_q -e 'SELECT 1' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
[ "${ready:-}" = 1 ] || die "database at ${DB_HOST}:${DB_PORT} did not become reachable"
log "database is up"

# Flarum writes absolute asset URLs built from FORUM_URL. Point it at
# "localhost" and the CSS/JS links resolve to the *viewer's* machine, so
# anyone browsing from another host gets unstyled HTML and a dead frontend.
case "$FORUM_URL" in
    *localhost*|*127.0.0.1*)
        log "NOTE: FORUM_URL is ${FORUM_URL} — assets will only load in a browser"
        log "      on this machine. Browsing from another host? Set FORUM_URL to"
        log "      the address you actually type (e.g. http://192.168.1.10:8888)."
        ;;
esac

# --- is Flarum already installed? -------------------------------------------
installed=$(mysql_q -N -B -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = DATABASE() AND table_name = '${DB_PREFIX}settings'")

write_config_php() {
    # Generated through PHP so passwords with quotes in them survive.
    DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" \
    DB_PASS="$DB_PASS" DB_PREFIX="$DB_PREFIX" FORUM_URL="$FORUM_URL" \
    FLARUM_DEBUG="$FLARUM_DEBUG" APP="$APP" \
    php -r '
        $config = [
            "debug" => filter_var(getenv("FLARUM_DEBUG"), FILTER_VALIDATE_BOOLEAN),
            "database" => [
                "driver"         => "mysql",
                "host"           => getenv("DB_HOST"),
                "port"           => (int) getenv("DB_PORT"),
                "database"       => getenv("DB_NAME"),
                "username"       => getenv("DB_USER"),
                "password"       => getenv("DB_PASS"),
                "charset"        => "utf8mb4",
                "collation"      => "utf8mb4_unicode_ci",
                "prefix"         => getenv("DB_PREFIX"),
                "strict"         => false,
                "engine"         => "InnoDB",
                "prefix_indexes" => true,
            ],
            "url"   => rtrim(getenv("FORUM_URL"), "/"),
            "paths" => ["api" => "api", "admin" => "admin"],
        ];
        file_put_contents(getenv("APP")."/config.php", "<?php return ".var_export($config, true).";\n");
    '
}

if [ "$installed" = "0" ]; then
    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS=$(php -r 'echo bin2hex(random_bytes(9));')
        generated_pass=1
    fi

    log "fresh database — installing Flarum"

    # FileDataProvider accepts JSON as well as YAML, and json_encode saves us
    # from hand-escaping anything.
    #
    # The "extensions" key is effectively mandatory. Flarum only falls back to
    # its bundled-extension whitelist when the value is null, but
    # FileDataProvider builds it with explode(',', $config['extensions'] ?? ''),
    # which yields [''] for a missing key — an array that matches no extension.
    # Omit it and the forum installs with *nothing* enabled: no Tags, no
    # Markdown, no Mentions. So we read Flarum's own whitelist and pass that,
    # reproducing exactly what the web installer would have enabled.
    #
    # Only the bundled ones go here. Third-party extensions cannot safely be
    # enabled by the install pipeline: fof/gamification's permissions migration
    # uses the Eloquent Permission model statically, and Eloquent's connection
    # resolver is not bootstrapped during install, so it dies with "Call to a
    # member function connection() on null". They are enabled after the install
    # instead, with the app booted.
    install_file=$(mktemp /tmp/flarum-install.XXXXXX.json)
    FORUM_URL="$FORUM_URL" FORUM_TITLE="$FORUM_TITLE" FLARUM_DEBUG="$FLARUM_DEBUG" \
    DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" \
    DB_PASS="$DB_PASS" DB_PREFIX="$DB_PREFIX" ADMIN_USER="$ADMIN_USER" \
    ADMIN_PASS="$ADMIN_PASS" ADMIN_MAIL="$ADMIN_MAIL" OUT="$install_file" \
    APP="$APP" \
    php -r '
        require getenv("APP")."/vendor/autoload.php";

        $bundled = class_exists("Flarum\\Install\\Steps\\EnableBundledExtensions")
            ? Flarum\Install\Steps\EnableBundledExtensions::EXTENSION_WHITELIST
            : [];

        file_put_contents(getenv("OUT"), json_encode([
            "debug"   => filter_var(getenv("FLARUM_DEBUG"), FILTER_VALIDATE_BOOLEAN),
            "baseUrl" => rtrim(getenv("FORUM_URL"), "/"),
            "databaseConfiguration" => [
                "driver"   => "mysql",
                "host"     => getenv("DB_HOST"),
                "port"     => (int) getenv("DB_PORT"),
                "database" => getenv("DB_NAME"),
                "username" => getenv("DB_USER"),
                "password" => getenv("DB_PASS"),
                "prefix"   => getenv("DB_PREFIX"),
            ],
            "adminUser" => [
                "username" => getenv("ADMIN_USER"),
                "password" => getenv("ADMIN_PASS"),
                "email"    => getenv("ADMIN_MAIL"),
            ],
            "settings"   => ["forum_title" => getenv("FORUM_TITLE")],
            "extensions" => implode(",", $bundled),
        ], JSON_PRETTY_PRINT));
    '
    flarum install --file="$install_file"
    rm -f "$install_file"
    fresh_install=1

    # Drop the settings cache the installer leaves behind, so the enables
    # below read the extension list the installer just committed.
    flarum cache:clear
else
    log "existing database detected — writing config and running migrations"
    write_config_php
    flarum migrate
fi

# --- third-party extensions --------------------------------------------------
# Runs on every boot, not just installs: enabling is a no-op when already on,
# and this picks up extensions added to the image since the forum was created.
IFS=',' read -ra _extensions <<< "$ENABLE_EXTENSIONS"
for ext in "${_extensions[@]}"; do
    ext="$(echo "$ext" | tr -d '[:space:]')"
    [ -n "$ext" ] || continue
    log "enabling $ext"
    flarum extension:enable "$ext"
done

# --- one-time defaults -------------------------------------------------------
sql_set_setting() {
    # $1 = key, $2 = value
    mysql_q -e "INSERT INTO \`${DB_PREFIX}settings\` (\`key\`, \`value\`)
                VALUES ('$1', '$2')
                ON DUPLICATE KEY UPDATE \`value\` = VALUES(\`value\`);"
}

sql_grant() {
    # $1 = group id, $2 = permission. Written as an INSERT..SELECT so it works
    # whether or not the table carries a unique key on (group_id, permission).
    mysql_q -e "INSERT INTO \`${DB_PREFIX}group_permission\` (\`group_id\`, \`permission\`)
                SELECT $1, '$2' FROM DUAL
                WHERE NOT EXISTS (
                    SELECT 1 FROM \`${DB_PREFIX}group_permission\`
                    WHERE \`group_id\` = $1 AND \`permission\` = '$2'
                );"
}

seed_tags() {
    DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" \
    DB_PASS="$DB_PASS" DB_PREFIX="$DB_PREFIX" \
    php "$APP/seed-tags.php" "$SEED_TAGS_FILE"
}

if [ "${fresh_install:-}" = 1 ]; then
    log "applying voting defaults"

    sql_set_setting 'default_locale' "$FORUM_LOCALE"

    sql_set_setting 'fof-gamification.firstPostOnly'             "$(bool01 "$VOTE_FIRST_POST_ONLY")"
    sql_set_setting 'fof-gamification.allowSelfVotes'            "$(bool01 "$VOTE_ALLOW_SELF_VOTES")"
    sql_set_setting 'fof-gamification.upVotesOnly'               "$(bool01 "$VOTE_UPVOTES_ONLY")"
    sql_set_setting 'fof-gamification.useAlternateLayout'        "$(bool01 "$VOTE_LIST_LAYOUT")"
    sql_set_setting 'fof-gamification.showVotesOnDiscussionPage' "$(bool01 "$VOTE_SHOW_ON_LIST")"

    # The extension's own migration grants discussion.votePosts to Members, but
    # nothing grants the "see votes" permissions — without these the vote
    # counts are hidden from everybody, which looks like a broken install.
    # Group ids: 1 admin, 2 guest, 3 member, 4 moderator.
    sql_grant 2 'discussion.canSeeVotes'    # guests -> everyone
    sql_grant 3 'discussion.canSeeVoters'
    sql_grant 3 'discussion.votePosts'      # belt and braces

    log "seeding categories from $SEED_TAGS_FILE"
    seed_tags

    log "configuring mail (driver: ${MAIL_DRIVER})"
    sql_set_setting 'mail_driver' "$MAIL_DRIVER"
    sql_set_setting 'mail_from'   "$MAIL_FROM"
    if [ "$MAIL_DRIVER" = "smtp" ]; then
        [ -n "$MAIL_HOST" ] || die "MAIL_DRIVER=smtp requires MAIL_HOST"
        sql_set_setting 'mail_host'       "$MAIL_HOST"
        sql_set_setting 'mail_port'       "$MAIL_PORT"
        sql_set_setting 'mail_username'   "$MAIL_USERNAME"
        sql_set_setting 'mail_password'   "$MAIL_PASSWORD"
        sql_set_setting 'mail_encryption' "$MAIL_ENCRYPTION"
    fi
fi

if [ "${fresh_install:-}" != 1 ] && [ "$SEED_TAGS_ALWAYS" = "true" ]; then
    log "seeding categories from $SEED_TAGS_FILE"
    seed_tags
fi

# --- housekeeping ------------------------------------------------------------
flarum cache:clear
for path in "$APP/storage" "$APP/public/assets" "$APP/extensions" "$APP/config.php"; do
    [ -e "$path" ] && chown -R www-data:www-data "$path" || true
done

if [ "${generated_pass:-}" = 1 ]; then
    cat <<BANNER

  ============================================================
   Flarum installed.

     URL      : ${FORUM_URL}
     Admin    : ${ADMIN_USER}
     Password : ${ADMIN_PASS}

   No ADMIN_PASS was set, so this one was generated. It is not
   stored anywhere else — copy it now, or set ADMIN_PASS and
   start from an empty database.
  ============================================================

BANNER
fi

log "starting: $*"
exec "$@"
