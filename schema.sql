-- schema

create extension if not exists hstore;
create extension if not exists ltree;

create table if not exists entity (
    id text not null primary key,
    type text not null,
    data hstore
);

CREATE INDEX if not exists entity_data_gist ON entity USING GIST (data);
CREATE INDEX if not exists entity_data_gin ON entity USING GIN (data);


create table if not exists hierarchy (
    type text not null,
    path ltree not null,
    entity_id text not null references entity(id)
);

create index if not exists hierarchy_path_gist_idx
    on hierarchy
    using gist (path);

create index if not exists hierarchy_path_idx
    on hierarchy
    using btree (path);

--- data

truncate table entity;
-- people
insert into entity values('bob', 'person', 'name => bob, level => 1');
insert into entity values('jan', 'person', 'name => jan, level => 2');
insert into entity values('joe', 'person', 'name => joe, level => 2');
-- teams
insert into entity values('dev', 'team', 'name => dev, tier => 2');
insert into entity values('design', 'team', 'name => design, tier => 2');
insert into entity values('product', 'team', 'name => product, tier => 1');
insert into entity values('org', 'team', 'name => org, tier => 0');


truncate table hierarchy;
-- teams
insert into hierarchy values ('multidisc', 'org', 'product');
insert into hierarchy values ('multidisc', 'org.product', 'design');
insert into hierarchy values ('multidisc', 'org.product', 'dev');
-- people in teams
insert into hierarchy values ('multidisc', 'org.product.dev', 'jan');
insert into hierarchy values ('multidisc', 'org.product.dev', 'bob');
insert into hierarchy values ('multidisc', 'org.product.design', 'bob');
insert into hierarchy values ('multidisc', 'org.product.design', 'joe');

-- managers
insert into hierarchy values ('manager', 'bob', 'jan');
insert into hierarchy values ('manager', 'bob', 'joe');

insert into hierarchy values ('manager', 'bob', 'product');


--- queries

-- hierarchy, e.g. people for org
select *
from entity e
inner join hierarchy h on h.entity_id = e.id
where
        e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org';

-- data, e.g. people of level 2
select *
from entity e
where
        e.data->'level' = '2';

-- combined, e.g. people on level 2 in org.product
select distinct(e.*)
from entity e
inner join hierarchy h on h.entity_id = e.id
where
        e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org.product'
    and e.data->'level' > '1';

-- entities managed by bob
select e.*
from entity e
inner join hierarchy h on h.entity_id = e.id
where
        h.type = 'manager'
    and h.path <@ 'bob';


-- group by entity, aggregate hierarchy duplicates
select e.*, array_agg(h.path) as teams
from entity e
inner join hierarchy h on h.entity_id = e.id
where
        e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org.product'
group by e.id;


-- hierarchies lookup from entity
select h.type, h.path
from entity e
inner join hierarchy h on h.entity_id = e.id
where e.id = 'jan';

