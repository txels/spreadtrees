--- queries
-- hierarchy, e.g. people for org
select
    *
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org'
;

-- hstore queries
-- data, e.g. people of level 2
select
    *
from
    entity e
where
    e.data -> 'level' = '2'
;

-- is value one of a set? (like python's "data.name in [bob, jan]")
select
    *
from
    entity
where
    data -> 'name' = any ('{bob,jan}')
;

select
    *
from
    entity
where
    data -> 'name' <> all ('{bob,jan}')
;

-- equivalient notation:
select
    *
from
    entity
where
    data -> 'name' <> all (array['bob', 'jan'])
;

-- combined, e.g. people on level 2 in org.product
--- HSTORE
select distinct
    (e.*)
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org.product'
    and e.data -> 'level' > '1'
;

-- JSONB
select distinct
    (e.*)
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org.product'
    and (e.data -> 'level')::text::integer > 1
;

--convert json text to integer
update entity
set
    data['tier'] = to_jsonb(to_number((data['tier'])::text, '999999999'))
    -- to_jsonb(cast((data['tier'])::text as integer))
where
    data -> 'tier' is not null
;

-- entities managed by bob
select
    e.*
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    h.type = 'manager'
    and h.path <@ 'bob'
;

-- group by entity, aggregate hierarchy duplicates
select
    e.*
  , array_agg(h.path) as teams
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.type = 'person'
    and h.type = 'multidisc'
    and h.path <@ 'org.product'
group by
    e.id
;

-- hierarchies lookup from entity
select
    h.type
  , h.path
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.id = 'jan'
;

-- all descendants with a given property e.g cost
select
    e.*
  , h.path
  , h.type
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.data ? 'cost'
    and h.path <@ 'org'
;

-- operation on values for all descendent properties
select
    sum(to_number(e.data -> 'cost'),'9999999999')
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.data ? 'cost'
    and h.path <@ 'org'
;

-- descendants where org is top
-- just select values for all descendent properties
select
    array_agg(e.data -> 'cost')
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.data ? 'cost'
;

deallocate aggregate_by
;

prepare aggregate_by as
select
    h.path
  , array_agg(entity_id)    id
  , array_agg(e.data -> $1) field
from
    entity e
    inner join hierarchy h on h.entity_id = e.id
where
    e.data ? $1
group by
    h.path
;

-- query views
-- query relations:
select
    id
  , type
  , data
  , relation
  , path
from
    entity_relations
where
    source_data -> 'name' = 'product'
;

-- all descendants of product
select
    d.*
  , e.type
from
    descendants d
    inner join entity e on e.id = d.entity_id
where
    d.id = 'product'
;

select
    *
from
    entities_in_path
where
    source_id = 'dev'
;

-- moving hierarchies
--- Query: find descendant hierarchy entries
select
    *
from
    hierarchy
where
type = 'multidisc'
and path <@ 'org.travel'
;

--- Update: update descendant hierarchy entries
update hierarchy
set
    path = 'org.product' || case nlevel (path) > nlevel ('org.travel')
        when 't' then subpath (path, nlevel ('org.travel'))
        else ''
    end
where
type = 'multidisc'
and path <@ 'org.travel'
;

select
    *
  , 'org.product.dev' || case nlevel (hierarchy.path) > nlevel ('org.product.design')
        when 't' then subpath (hierarchy.path, nlevel ('org.product.design'))
        else ''
    end
from
    hierarchy
where
    path <@ 'org.product.design'
;

select
    *
from
    hierarchy
where
    hierarchy.path <@ ('org'::ltree || 'design'::ltree)
    and hierarchy.entity_id != 'design'
;

--- Finding siblings
with
    element as (
        select
            *
        from
            hierarchy
        where
            entity_id = 'dev'
    )
select
    h.*
from
    hierarchy h
    inner join element e on h.type = e.type
    and h.path = e.path
where
    e.entity_id != h.entity_id
;

-- e.g.
select
    *
from
    siblings ('jan') as s
    inner join entity e on e.id = s.entity_id
;

-- e.g. descendant entities with a field 'level'
select
    d.*
  , e.type
  , e.data
from
    descendants ('design') d
    join entity e on e.id = d.entity_id
where
    e.data ? 'level'
;

-- "function" that updates data
select
    entity_move ('design', 'multidisc','org.other')
;

-- all entities in bob's ancestry
with
    bobs_tree as (
        select
            unnest(string_to_array(ltree2text (path), '.')) as id
          , path
          , h.type                                          as hie
          , e.type                                          as ent
        from
            hierarchy h
            inner join entity e on e.id = h.entity_id
        where
            e.id = 'bob'
    )
select
    *
from
    entity
where
    id = any (
        select
            id
        from
            bobs_tree
    )
    -- hierarchy, with parent field
select
    *
  , subpath (path, nlevel (path) -1) as parent
from
    hierarchy
;

-- siblings, based on parent
with
    parent as (
        select
            *
          , subpath (path, nlevel (path) -1) as parent
        from
            hierarchy
    )
select
    p1.entity_id as orig
  , p2.entity_id as sibling
  , p2.path      as sibling_type
  , sib.*
from
    parent p1
    inner join parent p2 on p1.parent = p2.parent
    inner join entity sib on sib.id = p2.entity_id
where
    p1.entity_id = 'bob'
    and p1.entity_id <> p2.entity_id
;

-- lateral to get children
select
    e.id
  , h.type      relation
  , h.path
  , h.entity_id child_id
  , e2.type     child_type
from
    entity e
  , lateral children (e.id) h
    inner join entity e2 on h.entity_id = e2.id
;

-- join hierarchy with parent
select
    hierarchy.id
  , entity_id
  , hierarchy.type as relation
  , _bottom (path) as parent_id
  , entity.type    as parent_type
  , entity.data    as parent_data
from
    hierarchy
    join entity on entity.id = _bottom (path)
;


-- catalog matches

select
    e.id, e.data->>'name' name, c.data->>'score' score
from
    entity e
    left join catalog c on e.data->>'seniority'=c.value and c.name='seniority'
where e.data?'seniority'
order by score desc;

-- aggregates by catalog values
create view seniority_value as
select
    e.id,
    e.data->>'name' as name,
    h.type,
    h.path,
    c.data as seniority_data
from
    entity e
    join hierarchy h on h.entity_id = e.id
    left join catalog c on e.data->>'seniority'=c.value and c.name='seniority'
where e.data?'seniority';


select
    type,
    path,
    sum((seniority_data->>'score')::int)
from seniority_value
group by type, path;

select
    path,
    count(*) filter(where value='F') as female,
    count(*) filter(where value='M') as male,
    count(*) filter(where not value=any('{M,F}')) as other
from fetch_property('gender')
where
    hierarchy_type = 'multidisc'
    and entity_type='person'
group by path;


create or replace view team_stats as
with genders as (
    select
        path,
        count(*) filter(where value='F') as female,
        count(*) filter(where value='M') as male,
        count(*) filter(where not value=any('{M,F}')) as other,
        array_agg(entity_id) as people
    from fetch_property('gender')
    where
        hierarchy_type = 'multidisc'
        and entity_type='person'
    group by path
)
select
    path, people, female, male,
    trunc(least(female, male) * 100 / greatest(female, male))::int as gender_balance,
    trunc(female * 100 / (female + male + other))::int as pct_female,
    trunc(male * 100 / (female + male + other))::int as pct_male
from genders;


select
    entity_id, 
    repeat( text '■', (property_data->>'score')::int) as seniority
from fetch_property('seniority');


create or replace function bar(length numeric) returns text
as $$
    select repeat( text '■', trunc(length)::int);
$$ language sql;

select
    path, 
    bar(gender_balance/10) as balance,
    bar(pct_male/10) as pct_male,
    bar(pct_female/10) as pct_female
from team_stats;

select entity_id, bar((property_data->>'score')::int) from fetch_property('seniority');
