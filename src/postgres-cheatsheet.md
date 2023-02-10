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
