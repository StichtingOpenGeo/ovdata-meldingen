# Flarum + FoF Gamification (topic voting)

A single Docker image with [Flarum](https://flarum.org/) 1.8 and
[FriendsOfFlarum/gamification](https://github.com/FriendsOfFlarum/gamification)
pre-installed, plus a compose file that pairs it with MariaDB. It installs and
configures itself on first boot: no web installer, no clicking through the
admin panel to turn voting on.

## Quick start

```sh
cp .env.example .env
$EDITOR .env          # at minimum, set DB_PASS
make up               # generates composer.lock if missing, then builds
make logs
```

Or without make:

```sh
./update-lock.sh                  # once; commit composer.json + composer.lock
docker compose up -d --build
docker compose logs -f flarum
```

The first boot takes a minute (migrations + asset compilation). When the log
says Flarum is installed, open <http://localhost:8888>. If you left
`ADMIN_PASS` empty, the generated admin password is printed in that log — it is
not stored anywhere else.

## What you get

- Vote arrows on every topic in the discussion list, and on the opening post.
- Vote counts visible to everyone, including logged-out visitors.
- Two extra sort options in the discussion list: **Trending** (hotness, which
  decays with age) and **Upvotes** (raw score).
- A `/rankings` leaderboard of users by points, linked in the sidebar.
- Points on user cards and profiles.
- Dutch and English, with Dutch as the default.

Voting is granted to the **Members** group, so you need to be logged in to
vote. The admin account created at install can vote immediately.

## Voting on topics, not replies

`VOTE_FIRST_POST_ONLY=true` (the default) restricts voting to the first post of
a discussion. Since a discussion's first post *is* the topic, this turns the
forum into a Reddit/HN-style "vote on topics" model: replies are just replies.

Set it to `false` if you want the full up/down-vote-every-post behaviour.

All the `VOTE_*` variables are applied **once**, during the initial install.
After that they are yours to change under **Admin → Gamification**, and this
container will not overwrite them. To re-apply them from the environment, start
again from an empty database (`docker compose down -v`).

## Configuration

Everything lives in `.env`; see `.env.example` for the full list.

| Variable | Default | Notes |
| --- | --- | --- |
| `DB_PASS` | — | Required. |
| `FORUM_URL` | `http://localhost:8888` | Must match the URL in your browser, port included. Flarum bakes it into generated links. |
| `HTTP_PORT` | `8888` | Host port to publish. The container always listens on 8888 internally, so changing this needs a restart, not a rebuild. Keep `FORUM_URL` in step with it. |
| `ADMIN_USER` / `ADMIN_MAIL` / `ADMIN_PASS` | `admin` / `admin@example.com` / generated | Created on first install only. |
| `FORUM_LOCALE` | `nl` | Default language for guests and new accounts: `nl` or `en`. |
| `ENABLE_EXTENSIONS` | `fof-gamification,flarum-lang-dutch` | Enabled on top of Flarum's bundled set. |
| `MAIL_DRIVER` | `log` | `log`, `smtp`, `mail` or `mailgun`. |
| `VOTE_FIRST_POST_ONLY` | `true` | Vote on topics only. |
| `VOTE_UPVOTES_ONLY` | `false` | Hide the downvote arrow. |
| `VOTE_ALLOW_SELF_VOTES` | `false` | |
| `VOTE_LIST_LAYOUT` | `true` | Vote arrows in the discussion list. |
| `VOTE_SHOW_ON_LIST` | `true` | Vote totals in the discussion list. |
| `FLARUM_VERSION` | `v1.8.19` | Exact skeleton tag. Re-run `./update-lock.sh` after changing. |
| `GAMIFICATION_VERSION` | latest compatible | Only read by `./update-lock.sh`. |

Changing `FORUM_URL`, the database settings or `FLARUM_DEBUG` and restarting is
enough — `config.php` is rewritten from the environment on every boot.

## Categories

Flarum calls them tags; the ones with a position are **primary tags**, which is
what shows up as a category. `tags.json` defines them and `seed-tags.php`
creates them on first install:

| Category | Slug | Colour | Icon |
| --- | --- | --- | --- |
| Tarieven | `/t/tarieven` | `#D4761A` | `fas fa-euro-sign` |
| Statische Dienstregeling | `/t/statische-dienstregeling` | `#2C7BB6` | `fas fa-calendar-alt` |
| GTFS | `/t/gtfs` | `#4B9560` | `fas fa-file-code` |
| Toegankelijkheid | `/t/toegankelijkheid` | `#7B5EA7` | `fas fa-universal-access` |
| Realtime Gegevens | `/t/realtime-gegevens` | `#C0392B` | `fas fa-satellite-dish` |

The seeder only ever **inserts**, and only slugs that are missing. Rename a
category, recolour it or reorder it in the admin panel and the change sticks
across restarts and rebuilds — nothing here overwrites it. Deleting one is also
respected, unless you re-run the seeder.

To change the list, edit `tags.json` and rebuild. On a forum that already
exists, apply the new entries with:

```sh
docker compose exec flarum sh -c \
  'DB_HOST=db DB_NAME=$DB_NAME DB_USER=$DB_USER DB_PASS=$DB_PASS php seed-tags.php'
```

or set `SEED_TAGS_ALWAYS=true` in `.env` to have every restart pick up
additions to the file.

Flarum's own installer creates a default **General** tag at position 0, which
this does not touch. Delete or rename it under **Admin → Tags** if you would
rather not have it. Note that `min_primary_tags` and `max_primary_tags` are both
`1` by default, so each discussion gets exactly one category.

A category added through **Admin → Tags** lives only in the database. It will
not exist on a fresh install, or after `make clean`. If you want it to be part
of the forum's definition rather than of one particular database, mirror it
into `tags.json` — the seeder skips slugs that already exist, so adding it
there after the fact is safe.

### Choosing an icon and a colour

**Icons must exist in Font Awesome 5.15.4**, which is what Flarum 1.8 bundles.
This is the easy mistake: search for an icon today and you get Font Awesome 6
names, and an FA6 name renders as a blank box with no error anywhere. Both
`fa-location-dot` and `fa-signs-post` fail this way — they are the FA6 spellings
of `fa-map-marker-alt` and `fa-map-signs`.

Check a name against the running forum before committing to it:

```sh
curl -s http://localhost:8888/assets/forum.css | grep -c '\.fa-map-marker-alt:before'
# 1 = usable, 0 = not in this build
```

Prefer an icon that describes the *subject* rather than one mode of transport:
`fa-map-marker-alt` covers a bus stop and a Centraal Station equally, where
`fa-train` quietly claims the category is only about rail.

**Colours should be far apart perceptually, not just different.** These render
as small labels, where similar hues blur together. Compare a candidate against
the palette above in CIELAB rather than by eye — ΔE above roughly 25 reads as
clearly distinct at label size, below 15 gets confusable. Watch the greys too:
the default General tag is `#888888`, and desaturated candidates collide with
it before they collide with anything colourful.

Hues currently in use are orange, blue, green, purple and red, which leaves
teal (`#17868A`) and magenta (`#B0407A`) as the roomiest gaps.

## Languages

Dutch (`flarum-lang/dutch`) and English are both installed; `FORUM_LOCALE`
picks the default for guests and new accounts, and every user can override it
in their own settings.

`FORUM_LOCALE` is applied at install time only. On a forum that already exists,
change the default under **Admin → Basics → Default language** instead, so this
container never fights a choice you made in the panel.

The Dutch pack covers Flarum core and 22 FoF extensions, but ships no
`fof-gamification.yml` — the whole voting UI would otherwise stay English.
`locale/nl.yml` in this repo fills that in and is registered by `extend.php`
via `Extend\Locales`. Translations there are merged per key, so they override
upstream where they overlap and leave everything else alone. Those strings are
a hand translation, not an official pack: edit `locale/nl.yml` and rebuild if
you would word something differently.

Adding another language is two steps:

```sh
docker run --rm -v "$PWD:/lock" -u "$(id -u):$(id -g)" -e COMPOSER_HOME=/tmp/composer \
    -w /lock composer:2 require flarum-lang/german --no-install '--ignore-platform-req=ext-*'
# then add flarum-lang-german to ENABLE_EXTENSIONS in .env, and rebuild
```

## Registering more users

The default `MAIL_DRIVER=log` means confirmation emails are written to the log
rather than sent. To find a new user's confirmation link:

```sh
docker compose exec flarum grep -o 'http[^ ]*/confirm/[^ ]*' storage/logs/flarum.log | tail -1
```

For a forum with real users, set `MAIL_DRIVER=smtp` and the `MAIL_*` variables
before the first boot (or configure mail under **Admin → Email** afterwards).

## Running Flarum commands

```sh
docker compose exec flarum php flarum cache:clear
docker compose exec flarum php flarum info
docker compose exec flarum php flarum fof:gamification:resyncUsers
docker compose exec flarum php flarum fof:gamification:resync
docker compose exec flarum php flarum fof:gamification:assign-groups
```

## Pinned dependencies

`composer.json` and `composer.lock` are committed and are the sole authority on
what gets installed. The image build runs `composer install --no-dev`, which
resolves nothing — rebuild in a year and you get byte-identical dependencies.

`./update-lock.sh` regenerates both files. It runs Composer in a throwaway
container, so the only thing you need on the host is Docker, and it resolves
against PHP 8.3 (the runtime image's version) rather than whatever PHP the
Composer image happens to ship.

Re-run it, and commit the result, whenever you:

- change `FLARUM_VERSION` in `.env` — the skeleton supplies the application
  files and the lock supplies the dependencies, so the two must be regenerated
  together or you get a mismatched forum;
- want to pull in upstream security or bugfix releases;
- add an extension (below).

## Adding more extensions

Add it to the lock, then rebuild:

```sh
docker run --rm -v "$PWD:/lock" -u "$(id -u):$(id -g)" -e COMPOSER_HOME=/tmp/composer \
    -w /lock composer:2 require fof/upload --no-install '--ignore-platform-req=ext-*'
docker compose up -d --build
docker compose exec flarum php flarum extension:enable fof-upload
```

Because extensions live in the image rather than in a volume, they survive
container recreation — but they can only be added this way, not through
Flarum's in-admin extension manager. That is the deliberate trade for a
reproducible image; if you would rather click to install, mount the whole
`/flarum/app` as a volume and add `flarum/extension-manager`.

## Behind a reverse proxy

The container speaks plain HTTP on `HTTP_PORT` and binds neither 80 nor 443,
so it sits behind a proxy without argument. Terminate TLS there, point it at
`http://<host>:8888`, and set `FORUM_URL=https://forum.example.com` so Flarum
builds its absolute asset URLs correctly.

If you want nginx to see the real client IP, add a `set_real_ip_from` for your
proxy's address to `nginx.conf` and rebuild. Do not add `real_ip_header`
without that — trusting a forwarded header from anyone lets clients spoof their
own IP.

## Updating

```sh
git pull
make update
```

`make update` dumps the database and uploads first, then rebuilds and
restarts. The dump matters: the entrypoint runs `flarum migrate` on boot, and
migrations do not roll back.

Volumes are never touched by a rebuild, so your data survives. The only command
in this repo that deletes anything is `make clean`.

**`.env` changes only half apply.** Compose recreates the container with the new
values, but several settings are written to the database at install time only,
so editing them later does nothing — silently:

| Applied on every boot | Applied at install only |
| --- | --- |
| `FORUM_URL`, `DB_*`, `FLARUM_DEBUG` | `FORUM_LOCALE` |
| `HTTP_PORT`, `ENABLE_EXTENSIONS` | `VOTE_*` |
| `SEED_TAGS_ALWAYS` | `MAIL_*`, `tags.json` |

That is deliberate — it stops the container from overwriting a choice you made
in the admin panel. Change the right-hand column under **Admin → Basics /
Gamification / Email** instead.

Since `.env` is gitignored, `diff .env .env.example` after a pull to spot new
variables. Anything missing falls back to the compose default.

Updating **Flarum itself** is separate, because the lock file pins it:

```sh
./update-lock.sh          # re-resolve within the current Flarum line
git diff composer.lock    # see exactly what moved
make update
git commit -am 'Bump dependencies'
```

For a minor release (1.8 → 1.9), bump `FLARUM_VERSION` in `.env` *before*
running `update-lock.sh` — it pins the skeleton's own application files, and
changing one without the other mixes files from two releases.

## Backups

```sh
make backup                                        # → ./backups/
make restore FILE=backups/flarum-20260903-213223.sql.gz
```

Each run writes two files: a gzipped SQL dump and a tar of `public/assets`.
The dump uses `--single-transaction`, so it is a consistent snapshot taken
without locking — the forum stays up throughout. The script verifies the gzip
stream and checks for the dump's completion marker before reporting success, so
a truncated dump fails loudly instead of sitting on disk pretending to be a
backup.

`storage/` is not backed up on purpose: it holds cache, logs and sessions, all
regenerated on boot.

The last 10 backups are kept; set `BACKUP_KEEP` to change that, or `BACKUP_DIR`
to write somewhere else — a different disk is a better place than this one.

`make restore` asks for confirmation, reloads the dump, unpacks the uploads and
clears the cache. Restore is exercised, not assumed: deleting every discussion
and a tag, then restoring, brings them all back.

`make clean` is the only destructive command. It requires you to type `DELETE`,
takes a backup first, and refuses to proceed if that backup fails unless you
pass `FORCE=1`.

## Web server and security posture

nginx and php-fpm, supervised, in one container. nginx serves static files and
hands `.php` to php-fpm over a **unix socket** — there is no FastCGI TCP port,
which matters because FastCGI is unauthenticated and an exposed one is remote
code execution.

Nothing in the container runs as root:

```
$ docker compose exec flarum cat /proc/1/status | grep -E 'Uid|CapEff|NoNewPrivs'
Uid:        33  33  33  33
CapEff:     0000000000000000
NoNewPrivs: 1
```

That falls out of the port choice. nginx listens on 8888 rather than 80, so no
process ever needs `CAP_NET_BIND_SERVICE`, which in turn means the image can
set `USER www-data` and compose can drop **all** capabilities and set
`no-new-privileges`. Neither 80 nor 443 is bound, in the container or on the
host.

Everything the daemons write to is owned by `www-data` at build time: nginx's
pid file and temp paths under `/var/run/flarum` and `/var/lib/nginx`, the
php-fpm socket, and the Flarum tree itself. The entrypoint does no `chown`,
because as a non-root user it could only fail — Docker seeds a named volume
with the ownership of the image directory it shadows, so `storage/` and
`public/assets` come up writable on their own.

Requests for `config.php`, `/vendor`, `/storage` and dotfiles return 404. They
already sit outside the document root; the rules are there so that a future
misconfiguration fails closed instead of serving credentials.

The database container keeps its own defaults — MariaDB's image already drops
to the `mysql` user on its own — plus `no-new-privileges`. Its port is not
published, so it is reachable only from the flarum container.

## Notes on the implementation

A few things this image handles that a naive setup gets wrong:

- The gamification migrations grant `discussion.votePosts` to Members but grant
  nothing for **seeing** votes, so vote counts are hidden from everyone by
  default. The entrypoint grants `discussion.canSeeVotes` to Guests (which
  every group inherits) and `discussion.canSeeVoters` to Members.
- Flarum's file-based installer enables **nothing** unless you tell it to, and
  not obviously: `FileDataProvider` builds the extension list with
  `explode(',', $config['extensions'] ?? '')`, so a missing key becomes `['']`
  rather than `null` — and only `null` triggers the fallback to the bundled
  whitelist. Install from a file without that key and you get a forum with no
  Tags, no Markdown and no Mentions. The entrypoint reads Flarum's own
  `EnableBundledExtensions::EXTENSION_WHITELIST` and passes it explicitly.
- Third-party extensions still cannot go in that list. `fof/gamification`'s
  permissions migration uses the Eloquent `Permission` model statically, and
  Eloquent's connection resolver is not bootstrapped during the install
  pipeline, so it dies with *"Call to a member function connection() on null"*
  and takes the install with it. It is enabled after the install instead, via
  `flarum extension:enable`, with the app booted.
- `config.php` is not on a volume; it is regenerated from the environment on
  every boot, so the container stays disposable while the database persists.
- The MariaDB client does not treat `MYSQL_PWD` as a real password when
  deciding whether to verify the server's certificate, so it disabled
  verification and said so on every query — nine warning lines per boot. The
  entrypoint passes the password in a `--defaults-extra-file` instead, which
  silences it at the source rather than by opting out of verification for good.
- The build never resolves dependencies. `composer create-project --no-install`
  fetches only the skeleton's application files; the committed lock then drives
  a plain `composer install`.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Stichting OpenGeo.

This covers the packaging in this repository: the Dockerfile, entrypoint,
compose file, seeders and translations. The software it installs carries its
own licences — Flarum and its bundled extensions are MIT, as are
`fof/gamification` and `flarum-lang/dutch`.
