default:
    just --list

run:
	docker-compose up

psql:
	docker-compose exec db psql -Upostgres
