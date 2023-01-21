# Postgres cheatshee

## Extensions

```sql
SELECT * FROM pg_available_extensions;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS ltree;
```

[ltree](https://www.postgresql.org/docs/current/ltree.html)
[hstore](https://www.postgresql.org/docs/current/hstore.html)

## Hstore

Query for objects with some value for a key.

```sql
select e.*
from entity e
where e.data?'level';
```
