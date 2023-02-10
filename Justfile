default:
    just --list

run:
	docker-compose up

psql *args:
    PGHOST=localhost psql -Upostgres {{args}}
