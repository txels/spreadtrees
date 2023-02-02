

--- Possibly obsolete functions, with the above trigger in place

-- move a hierarchy, i.e. replace a path with another
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


-- move an entity and all its descendants
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
