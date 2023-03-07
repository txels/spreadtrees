# Postgres cheatsheet

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

## JSONB

### Use JSONB fields

```sql
create table if not exists entity (
    data jsonb
);

-- migrate hstore field to jsonb:
alter table entity alter data type jsonb using data::jsonb;

-- find items with a particular key
select *
from entity
where data?'blob';               -- present

select *
from entity
where data->'blob' is not null;  -- not null

-- set values for full column or a particular key
update entity
set data = '{"blob":{"id": 24}}'
where id='bob';
--- this works even if data is initially null
update entity
set data['blob'] = '{"id": 24}'
where id='bob';

-- select item 2 within an array in a json field
select data->'blob'->2
from entity
where data?'blob';

select data->'blob'->>2
from entity
where data?'blob';

-- more json-y syntax
select data['blob'][2]
from entity
where data?'blob';

select data['blob']->>2
from entity
where data?'blob';

-- path-based
--- literal, e.g. strings come up as `"one"`
select data#>'{"blob",2}'
from entity
where data?'blob';

--- as text, e.g. strings come up as `one`
select data#>>'{"blob",2}'
from entity
where data?'blob';

-- select by containment of key/values
select *
from entity
where data @> '{"name":"dev", "tier":2}';

-- convert json array to postgres array
select id, array_agg(e::text::int)
from entity, jsonb_array_elements(data['ls']) e
group by id;

-- some aggregate filtering example
select id, array_agg(e::text::int) a
from entity, jsonb_array_elements(data['ls']) e
group by id
having data['ls'][3]::text::int = 4;

```

### Manipulating JSON data

```sql

-- set a list value (json notation, not pg array!)
update entity
set data['ls'] = '[1,2]'
where ...;

-- Append to JSON array value
update entity
set data['ls'] = data['ls'] || '[3]'
where ...;

-- add complex object
update entity
set data['blob'] = '{"list": [1,2]}'
where id='pro';

-- remove a key
update entity
set data = data - 'ls'
where id='pro';

-- remove keys with null values
update entity
set data = jsonb_strip_nulls(data);

-- remove item from array by 0-based index: in this case data['blob'][1]
update entity
set data['blob'] = data['blob'] - 1
where id='pro';

update entity
set data['blob'] = array_remove(data['blob'], '{2}')
where id='pro';

-- remove array item by value, by converting to pg array:
-- as query

-- as update
update entity set data['blob'] = (
    select array_to_json(array_remove(array_agg(e::text::int), '3'))::jsonb
    from entity, jsonb_array_elements(data['blob']) e
    where id='pro'
)
where id='pro';

```

## windowing

```sql
select
    id,
    data['tier'] tier,
    rank() over(order by data['tier'])
from entity;
```

## Built-in functions

### Series

Function to generate a series/range, can be used with many types.
E.g. with integers:

```sql
select generate_series(2, 10, 2);

 generate_series
═════════════════
               2
               4
               6
               8
              10
```

With dates:

```sql
\set start 2023-01-01

select generate_series(
    date :'start',
    date :'start' + interval '1 month' - interval '1 day',
    interval '1 day'
);

   generate_series
═════════════════════
 2023-01-01 00:00:00
 2023-01-02 00:00:00
 2023-01-03 00:00:00
 ...

```

### Dates

A more elaborate use case, extracting day of week and day from date:

```sql
\set start 2023-01-01

with d as (
    select generate_series(
        date :'start',
        date :'start' + interval '1 month' - interval '1 day',
        interval '1 day'
    ) as day
)
select
    extract(week from day) as week_of_year
  , extract(isodow from day) as day_of_week
  , extract(doy from day) as day_of_year
  , extract(day from day) as day_of_month
  from d;
```

## Schemas

```sql
-- list schemas, change owner
\dn
create role f1db login;
alter database f1db owner to f1db;
alter schema f1db owner to f1db;

-- connect to db as user
\c f1db f1db
-- determine schema search path
show search_path;
set search_path = f1db, public;
```

## Clone tables

```sql
-- copy schema, indices and constraints...
-- (does not include triggers though, nor associated functions):
CREATE TABLE <newname> (LIKE <oldname> INCLUDING ALL);
-- copy data
INSERT INTO <newname> SELECT * FROM <oldname>;
```
