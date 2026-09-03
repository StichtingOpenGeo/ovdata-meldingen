.PHONY: help lock up update backup restore down logs shell clean

help:
	@echo "make up      - build and start (generates composer.lock if missing)"
	@echo "make update  - back up, rebuild and restart; use after a git pull"
	@echo "make backup  - dump the database and uploads to ./backups"
	@echo "make restore FILE=backups/flarum-<stamp>.sql.gz"
	@echo "make lock    - re-resolve composer.lock; commit the result"
	@echo "make logs    - follow the forum log"
	@echo "make shell   - shell into the running forum container"
	@echo "make down    - stop (keeps all data)"
	@echo "make clean   - stop and DELETE all data (backs up first)"

composer.lock:
	./update-lock.sh

lock:
	./update-lock.sh

up: composer.lock
	docker compose up -d --build

# Always dumps before touching anything: the rebuild itself is safe, but the
# entrypoint runs "flarum migrate" on boot, and migrations do not roll back.
#
# The database has to be running to be dumped, so start it first. Starting db
# on its own runs no migrations — only the forum's entrypoint does that — so
# the data is still untouched when the backup is taken.
update: composer.lock
	@docker compose up -d db
	@printf 'waiting for the database'
	@for i in $$(seq 1 60); do \
		if [ "$$(docker inspect -f '{{.State.Health.Status}}' $$(docker compose ps -q db) 2>/dev/null)" = "healthy" ]; then \
			echo " ok"; break; \
		fi; \
		printf '.'; sleep 2; \
		if [ "$$i" = "60" ]; then echo; echo "database did not become healthy"; exit 1; fi; \
	done
	./backup.sh
	docker compose up -d --build
	@echo
	@echo "Updated. Watch it come up with 'make logs'."
	@echo "Note: FORUM_LOCALE, VOTE_* and MAIL_* are applied at install time"
	@echo "only — change those in the admin panel, not in .env."

backup:
	./backup.sh

restore:
	@test -n "$(FILE)" || { echo "usage: make restore FILE=backups/flarum-<stamp>.sql.gz"; exit 1; }
	./restore.sh "$(FILE)"

down:
	docker compose down

logs:
	docker compose logs -f flarum

shell:
	docker compose exec flarum bash

# The only command here that destroys data. It takes a backup first and will
# not proceed if that backup fails, unless you pass FORCE=1.
clean:
	@echo
	@echo "  This DELETES the database and all uploads for this forum."
	@echo "  A backup is taken first; 'make restore' can bring it back."
	@echo
	@printf '  Type DELETE to continue: '; read answer; [ "$$answer" = "DELETE" ] || { echo "  aborted"; exit 1; }
	@./backup.sh || { echo; echo "  Backup FAILED — refusing to delete. Pass FORCE=1 to override."; test "$(FORCE)" = "1"; }
	docker compose down -v
