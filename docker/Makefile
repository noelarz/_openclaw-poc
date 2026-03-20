.PHONY: setup up down restart rebuild logs status doctor shell token clean nuke

setup:
	cp .env.example .env
	mkdir -p workspace
	@echo "Edit .env and set OPENCLAW_GATEWAY_TOKEN, then run: make up"

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

rebuild:
	docker compose down
	docker compose build --no-cache
	docker compose up -d

logs:
	docker compose logs -f

status:
	docker compose ps
	docker stats openclaw-agent --no-stream

doctor:
	docker compose exec openclaw openclaw doctor

shell:
	docker compose exec openclaw bash

token:
	@docker compose exec openclaw sh -c 'jq -r ".gateway.auth.token" ~/.openclaw/openclaw.json'

config-show:
	@docker compose exec openclaw sh -c 'jq "del(.gateway.auth.token)" ~/.openclaw/openclaw.json'

clean:
	docker compose down --rmi local

nuke:
	docker compose down -v --rmi local
	@echo "All containers, images, and volumes removed."
