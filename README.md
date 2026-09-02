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
| `HTTP_PORT` | `8888` | Host port to publish. |
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

| Category | Slug |
| --- | --- |
| Tarieven | `/t/tarieven` |
| Statische Dienstregeling | `/t/statische-dienstregeling` |
| GTFS | `/t/gtfs` |
| Toegankelijkheid | `/t/toegankelijkheid` |
| Realtime Gegevens | `/t/realtime-gegevens` |

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

Terminate TLS at the proxy, set `FORUM_URL=https://forum.example.com`, and
uncomment the two `RemoteIP*` lines in `apache-flarum.conf` (both of them —
enabling the header without a trusted-proxy list lets clients spoof their IP).
Rebuild afterwards.

## Backups

State lives in three named volumes: `db-data`, `flarum-storage` (logs, cache,
sessions) and `flarum-assets` (avatars, uploads, compiled CSS/JS). A database
dump plus `flarum-assets` is enough to restore.

```sh
docker compose exec db mariadb-dump -uflarum -p"$DB_PASS" flarum > backup.sql
```

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
- The build never resolves dependencies. `composer create-project --no-install`
  fetches only the skeleton's application files; the committed lock then drives
  a plain `composer install`.
