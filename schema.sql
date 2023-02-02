--- extensions ---
create extension if not exists hstore;
create extension if not exists ltree;


--- schema clear
-- drop table hierarchy;
-- drop table entity;


--- tables ---

create table if not exists entity (
    id text not null primary key,
    type text not null,
    data hstore
);

create index if not exists entity_data_gist on entity using gist (data);
create index if not exists entity_data_gin on entity using gin (data);


create table if not exists hierarchy (
    type text not null,
    path ltree not null,
    entity_id text not null references entity(id) on delete cascade
);

-- add constraint for hierarchy (type, path, entity_id)
alter table hierarchy add constraint no_duplicates
unique nulls not distinct (type, path, entity_id);


create index if not exists hierarchy_path_gist_idx
    on hierarchy
    using gist (path);

create index if not exists hierarchy_path_idx
    on hierarchy
    using btree (path);


--- functions and triggers ---

-- update descendants (to be called by trigger)
create or replace function _update_descendants_hierarchy_path() returns trigger as
$$
begin
    update hierarchy
       set path = NEW.path || CASE nlevel(hierarchy.path) > nlevel(OLD.path)
            WHEN 't' THEN
                subpath(hierarchy.path, nlevel(OLD.path))
            ELSE ''
        END
     where NEW.type=hierarchy.type
       and hierarchy.path <@ (OLD.path || OLD.entity_id)
       and hierarchy.entity_id != NEW.entity_id;
    return NEW;
end;
$$ language plpgsql;

drop trigger if exists hierarchy_path_autoupdate on hierarchy;
create trigger hierarchy_path_autoupdate
    after update on hierarchy
    for each row
    when (NEW.path is distinct from OLD.path)
    execute procedure _update_descendants_hierarchy_path();


CREATE or replace FUNCTION siblings(source_id text) RETURNS SETOF hierarchy AS $$
    with element as (
        select *
        from hierarchy
        where entity_id = source_id
    )
    select h.* from hierarchy h
    inner join element e on h.type=e.type and h.path=e.path
    where e.entity_id != h.entity_id;
$$ LANGUAGE SQL;


CREATE or replace FUNCTION children(source_id text) RETURNS SETOF hierarchy AS $$
    select h.* from hierarchy h where h.path ~ ('*.' || source_id)::lquery;
$$ LANGUAGE SQL;


CREATE or replace FUNCTION descendants(source_id text) RETURNS SETOF hierarchy AS $$
    select h.* from hierarchy h where h.path ~ ('*.' || source_id || '.*')::lquery;
$$ LANGUAGE SQL;


--- views ---

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

-- elements that are in a tree ancestry, i.e. have descendants
drop view descendants;
create view descendants as
select
    unnest(string_to_array(ltree2text(path), '.')) as id,
    h.*
from hierarchy h
group by (id, h.type, h.path, h.entity_id);

-- joins hierarchy and entities as a tree of entities
drop view entity_tree;
create view entity_tree as
select h.type as hierarchy_type, h.path, e.* from hierarchy h
inner join entity e on e.id = h.entity_id;

