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


