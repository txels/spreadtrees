--- extensions ---
create extension if not exists ltree;


-- entities (versioned)

drop table if exists entity;
create table if not exists entity (
    id text not null,
    version uuid not null default gen_random_uuid(),
    updated_at timestamp not null default now(),
    type text not null,
    data jsonb,
    constraint entity_unique_id_version unique (id, version)
);

create index if not exists entity_id
    on entity
    using btree(id);

create index if not exists entity_updated
    on entity
    using btree(updated_at desc);

create index if not exists entity_data
    on entity
    using gin(data);


-- relations (versioned)

drop table if exists relation;
create table if not exists relation (
    id serial,
    version uuid not null default gen_random_uuid(),
    updated_at timestamp not null default now(),
    type text not null,
    path ltree not null,
    -- entity_id reference check should be done on a before insert trigger
    entity_id text not null, -- references entity(id) on delete cascade,
    constraint relation_unique_id_version unique nulls not distinct (id, version),
    constraint relation_no_duplicates unique nulls not distinct (type, path, entity_id)
);

create index if not exists relation_path_idx
    on relation
    using btree(path);

-- specialised index for tree operations:
create index if not exists relation_path_gist_idx
    on relation
    using gist(path);


-- revisions (i.e. sets of related entity versions)

drop table if exists revision;
create table if not exists revision (
    id uuid primary key not null default gen_random_uuid(),
    parent uuid references revision(id),
    name text
);

drop table if exists revision_entity;
create table if not exists revision_entity (
    revision_id uuid not null references revision(id) on delete cascade,
    -- entity_id reference check should be done on a before insert trigger
    -- FK constraint to entity(id, version) cannot ATM be enforced due to how
    -- we create new versions in pre-update triggers, where it temporarily
    -- fails - even deferrable foreign keys won't work unless we figure out how
    -- to do versioning in only the pre-trigger step.
    entity_id text not null,
    entity_version uuid not null,
    -- foreign key (entity_id, entity_version) references (id, version) deferrable
    constraint revision_entity_unique unique (revision_id, entity_id)
);


--- functions and triggers ---

-- create new version (to be called by trigger)
-- generic, will work for both entity and relation
create or replace function set_new_version_id() returns trigger
as $$
begin
    -- do not allow updating version directly
    if OLD.version != NEW.version then
        raise exception 'must not manually set version.';
        return null;
    end if;

    NEW.version = gen_random_uuid();
    NEW.updated_at = now();
    return NEW;
end;
$$ language plpgsql;

create or replace function keep_old_version() returns trigger
as $$
begin
    execute
        'INSERT INTO '
        || quote_ident(TG_TABLE_NAME)
        || ' values ($1.*)'
        USING OLD;
    -- execute format('insert into %I values %s', TG_TABLE_NAME, OLD.*);
    -- insert into TG_TABLE_NAME values (OLD.*);
    return NEW;
end;
$$ language plpgsql;


drop trigger if exists pre_versioning on entity;
create trigger pre_versioning
    before update on entity
    for each row
    when (NEW.* is distinct from OLD.*)
    execute function set_new_version_id();

drop trigger if exists post_versioning on entity;
create trigger post_versioning
    after update on entity
    for each row
    when (NEW.version is distinct from OLD.version)
    execute function keep_old_version();


drop trigger if exists pre_versioning on relation;
create trigger pre_versioning
    before update on relation
    for each row
    when (NEW.* is distinct from OLD.*)
    execute function set_new_version_id();

drop trigger if exists post_versioning on relation;
create trigger post_versioning
    after update on relation
    for each row
    when (NEW.version is distinct from OLD.version)
    execute function keep_old_version();



create or replace function latest_entity(source_id text)
returns setof entity
as $$
    select * from entity
    where id = source_id
    order by updated_at desc
    limit 1;
$$ language sql;

create or replace function latest_entities()
returns setof entity
as $$
    select
        distinct on (id)
        *
    from entity
    order by id, updated_at desc;
$$ language sql;


create or replace function branch(parent_id uuid)
returns uuid
as $$
    declare new_id uuid;

    begin
       with revision as (
            insert into revision (parent)
            values(parent_id)
            returning id
        ) select id from revision into new_id;

        insert into revision_entity (revision_id, entity_id, entity_version)
        (select new_id, ev.entity_id, ev.entity_version from revision_entity ev where revision_id = parent_id);

        return new_id;
    end
$$ language plpgsql;


create or replace function revision_entities(branch_revision uuid)
returns setof entity
as $$
    select e.*
    from entity e
    join revision_entity re
        on re.entity_id = e.id
        and re.entity_version = e.version
    where re.revision_id = branch_revision;
$$ language sql;


create or replace function set_field_in_revision(
    branch_id uuid,
    source_entity_id text,
    field text,
    value jsonb
)
returns setof revision_entity
as $$
    with old_version as (
        select * from revision_entity
        where revision_id = branch_id
        and entity_id = source_entity_id
    ),
    new_version as (
        update entity
        set data[field]=value
        where (id, version) in (
            select entity_id, entity_version from old_version
        )
        returning id, version
    )
    update revision_entity
    set entity_version = (select version from new_version)
    where (revision_id, entity_id) = (select revision_id, entity_id from old_version)
    returning revision_entity.*;
$$ language sql;




--- Example queries/updates

-- updates that will create new versions:

update entity
set data['mastery']= '"some"'
where
    id='me'
    and version='6e1fd667-a6ac-43ec-a670-3a563fec80d5'
returning id, version;

-- use new version in a follow-up statement via a CTE:

with
    updates as (
        update entity
        set
            data['hello'] = '"dolly"'
        where
            id = 'bob'
        returning
            id, version
    )
select
    *
from
    updates
;


-- latest versions for all entities

select
    distinct on (id)
    id, version, updated_at, data
from entity
order by id, updated_at desc;


--- create initial "main" revision with current latest versions

insert into revision (name) values ('main');

with
entities as (
    select id, version from latest_entities()
),
main_branch as (
    select id as revision_id from revision where name = 'main'
)
insert into revision_entity (revision_id, entity_id, entity_version)
select revision_id, id, version from entities, main_branch;


-- update an object in a revision

with old_version as (
    select * from revision_entity
    where revision_id = 'e023b52c-2ae1-4311-b03a-710250b693ba'
    and entity_id = 'bob'
),
new_version as (
    update entity_version
    set data['critical']='false'
    where (id, version) in (
        select entity_id, entity_version from old_version
    )
    returning id, version
)
update revision_entity
set entity_version = (select version from new_version)
where (revision_id, entity_id) = (select revision_id, entity_id from old_version);


-- query revisions

select * from revision_entities('98f18a8c-085b-4163-bc3e-798ce66dfc78') order by id;
