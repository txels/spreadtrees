default:
    just --list

run:
	docker-compose up

psql *args:
    PGHOST=localhost psql -Upostgres {{args}}

dpsql *args:
    @docker-compose exec db psql "{{args}}" -U postgres
