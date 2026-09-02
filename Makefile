.PHONY: help lock up down logs shell clean

help:
	@echo "make lock   - (re)generate composer.json + composer.lock; commit both"
	@echo "make up     - build and start; generates the lock first if missing"
	@echo "make logs   - follow the forum log"
	@echo "make shell  - shell into the running forum container"
	@echo "make down   - stop (keeps data)"
	@echo "make clean  - stop and DELETE all data volumes"

composer.lock:
	./update-lock.sh

lock:
	./update-lock.sh

up: composer.lock
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f flarum

shell:
	docker compose exec flarum bash

clean:
	docker compose down -v
