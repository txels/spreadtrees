create table if not exists entity_version (
    id text not null,
    version uuid not null default gen_random_uuid(),
    updated_at timestamp not null default now(),
    type text not null,
    data jsonb,
    constraint entity_unique_id_version unique (id, version)
);

create index if not exists entity_version_updated
    on entity_version
    using btree(updated_at desc);

create index if not exists entity_version_data
    on entity_version
    using gin(data);

create table if not exists revision (
    id uuid primary key not null default gen_random_uuid(),
    parent uuid references revision(id),
    name text,
);

create table if not exists revision_entity (
    revision_id uuid not null references revision(id) on delete cascade,
    entity_id text not null,
    entity_version uuid not null
);


--- functions and triggers ---

-- create new version (to be called by trigger)
create or replace function generate_new_version_id() returns trigger
as $$
begin
    -- do not allow updating version directly
    IF OLD.version != NEW.version THEN
        RAISE EXCEPTION 'Must not manually update version.';
        RETURN NULL;
    END IF;

    NEW.version = gen_random_uuid();
    NEW.updated_at = now();
    return NEW;
end;
$$ language plpgsql;

create or replace function keep_old_version() returns trigger
as $$
begin
    insert into entity_version values (OLD.*);
    return NEW;
end;
$$ language plpgsql;

drop trigger if exists pre_versioning on entity_version;
create trigger pre_versioning
    before update on entity_version
    for each row
    when (NEW.* is distinct from OLD.*)
    execute function generate_new_version_id();

drop trigger if exists post_versioning on entity_version;
create trigger post_versioning
    after update on entity_version
    for each row
    when (NEW.version is distinct from OLD.version)
    execute function keep_old_version();

create or replace function latest_entity_version(source_id text)
returns setof entity_version
as $$
    select * from entity_version
    where id = source_id
    order by updated_at desc
    limit 1;
$$ language sql;

create or replace function latest_entity_versions()
returns setof entity_version
as $$
select
    distinct on (id)
    *
from entity_version
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
returns setof entity_version
as $$
    select e.*
    from entity_version e
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
        update entity_version
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

-- populate versioned from non-versioned entities

insert into entity_version (id, type, data)
select id, type, data from entity;

-- updates that will create new versions:

update entity_version
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
from entity_version
order by id, updated_at desc;


--- create initial "main" revision with current latest versions

insert into revision (id) values (gen_random_uuid());

with
entities as (
    select id, version from latest_entity_versions()
)
insert into revision_entity (revision_id, entity_id, entity_version)
select '98f18a8c-085b-4163-bc3e-798ce66dfc78', id, version from entities;


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
