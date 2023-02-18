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
    data jsonb
    -- data hstore
);

-- convert hstore to jsonb:
-- alter table entity alter data type jsonb using data::jsonb;

-- create index if not exists entity_data_gist on entity using gist (data);
create index if not exists entity_data_gin on entity using gin (data);


create table if not exists hierarchy (
    id serial primary key,
    type text not null,
    path ltree not null,
    entity_id text not null references entity(id) on delete cascade
);

-- TODO: multi-valued hierarchies/relations? E.g one person many teams
-- add constraint for hierarchy (type, path, entity_id)
alter table hierarchy add constraint no_duplicates
unique nulls not distinct (type, path, entity_id);


create index if not exists hierarchy_path_gist_idx
    on hierarchy
    using gist (path);

create index if not exists hierarchy_path_idx
    on hierarchy
    using btree (path);


-- drop table changelog;
create table if not exists changelog (
    id serial primary key,
    ts timestamptz not null default now(),
    event text not null,
    entity_id text not null references entity(id) on delete cascade,
    change_data jsonb not null
);

create index if not exists changelog_event
    on changelog
    using btree (event);
create index if not exists changelog_entity_id
    on changelog
    using btree (entity_id);


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
    after update of path on hierarchy
    for each row
    when (NEW.path is distinct from OLD.path)
    execute procedure _update_descendants_hierarchy_path();


-- record hierarchy change (move) - (to be called by trigger)
create or replace function _record_hierarchy_change() returns trigger as
$$
-- argv[0] is text "hierarchy change type"
begin
    insert into changelog(event, entity_id, change_data)
    values(
        'hierarchy_' || TG_ARGV[0],
        coalesce(OLD.entity_id, NEW.entity_id),
        json_build_object(
            'type', coalesce(OLD.type, NEW.type),
            'from', OLD.path,
            'to', NEW.path
        )
    );
    return NEW;
end;
$$ language plpgsql;


create or replace function _bottom(path ltree) returns text as $$
    select subpath(path, -1, 1)::text;
$$ language sql;

drop trigger if exists record_hierarchy_move on hierarchy;
create trigger record_hierarchy_move
    after update on hierarchy
    for each row
    when (_bottom(NEW.path) is distinct from _bottom(OLD.path))
    execute procedure
        _record_hierarchy_change('move')
;

drop trigger if exists record_hierarchy_create on hierarchy;
create trigger record_hierarchy_create
    after insert on hierarchy
    for each row
    execute procedure
        _record_hierarchy_change('add')
;

drop trigger if exists record_hierarchy_delete on hierarchy;
create trigger record_hierarchy_delete
    after delete on hierarchy
    for each row
    execute procedure
        _record_hierarchy_change('remove')
;


create or replace function siblings(source_id text) returns setof hierarchy as $$
    with element as (
        select *
        from hierarchy
        where entity_id = source_id
    )
    select h.* from hierarchy h
    inner join element e on h.type=e.type and h.path=e.path
    where e.entity_id != h.entity_id;
$$ language sql;


create or replace function children(source_id text) returns setof hierarchy as $$
    select h.* from hierarchy h where h.path ~ ('*.' || source_id)::lquery;
$$ language sql;


create or replace function descendants(source_id text) returns setof hierarchy as $$
    select h.* from hierarchy h where h.path ~ ('*.' || source_id || '.*')::lquery;
$$ language sql;


--- views ---

-- all hierarchies where an entity with a given property occurs
-- (e.g. name = 'bob')
-- could be made simpler if we include the leaf in the path,
-- but this may make other queries more complicated
drop view if exists entity_relations;
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
drop view if exists entities_in_path;
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
drop view if exists descendants;
create view descendants as
    select
        unnest(string_to_array(ltree2text(path), '.')) as id,
        h.*
    from hierarchy h
    group by (id, h.type, h.path, h.entity_id);

-- joins hierarchy and entities as a tree of entities
drop view if exists entity_tree;
    create view entity_tree as
    select
        h.type as hierarchy_type,
        h.path,
        e.*
    from hierarchy h
    inner join entity e on e.id = h.entity_id;
