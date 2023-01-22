-- schema


create extension if not exists hstore;
create extension if not exists ltree;

drop table hierarchy;
drop table entity;

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
    entity_id text not null references entity(id) on delete cascade
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
insert into entity values('dev', 'team', 'name => dev, tier => 2, cost=>12');
insert into entity values('design', 'team', 'name => design, tier => 2, cost=>23');
insert into entity values('product', 'team', 'name => product, tier => 1');
insert into entity values('other', 'team', 'name => other, tier => 1');
insert into entity values('org', 'team', 'name => org, tier => 0');


truncate table hierarchy;
-- teams
insert into hierarchy values ('multidisc', 'org', 'product');
insert into hierarchy values ('multidisc', 'org', 'other');
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

-- all descendants with a given property e.g cost
select e.*, h.path, h.type
from entity e
inner join hierarchy h on h.entity_id = e.id
where
    e.data?'cost'
and h.path <@ 'org';

-- operation on values for all descendent properties
select sum(to_number(e.data->'cost'), '9999999999')
from entity e
inner join hierarchy h on h.entity_id = e.id
where
    e.data?'cost'
and h.path <@ 'org';  -- descendants where org is top


-- just select values for all descendent properties
select array_agg(e.data->'cost')
from entity e
inner join hierarchy h on h.entity_id = e.id
where
    e.data?'cost';

-- all hierarchies where an entity with a given property occurs
-- (e.g. name = 'bob')
-- could be made simpler if we include the leaf in the path,
-- but this may make other queries more complicated

drop view entity_relations;
create view entity_relations as
select
    e.*,
    h.type as relation,
    h.path,
    source.id as source_id,
    source.data as source_data,
    source.type as source_type
from
    entity e
        inner join hierarchy h on h.entity_id = e.id,
    entity source
where
   (
    h.path ~ ('*.' || source.id || '.*')::lquery  -- within the tree
    or
    h.entity_id = source.id -- at the leaf
   );

-- query relations:

select id, type, data, relation, path
from
    entity_relations
where
  source_data->'name' = 'product';


-- all entities in a path

drop view entities_in_path;
create view entities_in_path as
select e.*, source.id as source_id
from entity e, entity source
where e.id in
(
    -- in tree
    select
        unnest(string_to_array(ltree2text(path), '.')) as id
    from hierarchy
    where entity_id=source.id

    union
    select
        source.id as id
);

select * from entities_in_path
where source_id = 'dev';

-- find elements that are in a tree ancestry, i.e. have descendants
drop view descendants;
create view descendants as
select
    unnest(string_to_array(ltree2text(path), '.')) as id,
    h.*
from hierarchy h
group by (id, h.type, h.path, h.entity_id);

-- all descendants of product
select d.*, e.type
from descendants d
inner join entity e on e.id = d.entity_id
where d.id = 'product';


-- moving hierarchies

--- find descendant hierarchy entries
select
    *
from
    hierarchy
where
    type='multidisc'
and path <@ 'org.travel';

--- update descendant hierarchy entries
update
    hierarchy
set
    path = 'org.product' || CASE nlevel(path) > nlevel('org.travel')
        WHEN 't' THEN
            subpath(path, nlevel('org.travel'))
        ELSE ''
    END
where
    type='multidisc'
and path <@ 'org.travel';



create or replace function hierarchy_move(hierarchy_type text, old_path ltree, new_path ltree)
returns integer
language plpgsql as $$
declare
    updated_rows integer;
begin
    update
        hierarchy
    set
        path = new_path || CASE nlevel(path) > nlevel(old_path)
            WHEN 't' THEN
                subpath(path, nlevel(old_path))
            ELSE ''
        END
    where
        type=hierarchy_type
    and path <@ old_path;
    GET DIAGNOSTICS updated_rows := ROW_COUNT;
    return updated_rows;
end
$$;

create or replace function entity_move(entity_id text, hierarchy_type text, new_path ltree)
returns integer
language plpgsql as $$
declare
    updated_rows integer;
    old_path ltree;
    source_id text := entity_id;
begin
    old_path := (
        select path from hierarchy h
        where
            type = hierarchy_type
        and h.entity_id = source_id
    );
    -- update direct record
    update hierarchy h
        set path = new_path
        where
            type = hierarchy_type
        and h.entity_id = source_id;
    -- update all descendants
    updated_rows := (
        select hierarchy_move(
            hierarchy_type,
            old_path||source_id,
            new_path||source_id)
    );
    return updated_rows + 1; -- +1 being the direct record update
end
$$;

-- e.g. select entity_move('design', 'multidisc', 'org.other');
