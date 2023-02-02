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


-- query views

-- query relations:

select id, type, data, relation, path
from
    entity_relations
where
  source_data->'name' = 'product';


-- all descendants of product
select d.*, e.type
from descendants d
inner join entity e on e.id = d.entity_id
where d.id = 'product';


select * from entities_in_path
where source_id = 'dev';



-- moving hierarchies

--- Query: find descendant hierarchy entries
select
    *
from
    hierarchy
where
    type='multidisc'
and path <@ 'org.travel';

--- Update: update descendant hierarchy entries
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



select *, 'org.product.dev'  || CASE nlevel(hierarchy.path) > nlevel('org.product.design')
            WHEN 't' THEN
                subpath(hierarchy.path, nlevel('org.product.design'))
            ELSE ''
        END
        from hierarchy where path <@ 'org.product.design';

select * from hierarchy
     where hierarchy.path <@ ('org'::ltree || 'design'::ltree)
       and hierarchy.entity_id != 'design';



--- Finding siblings
with element as (
    select *
    from hierarchy
    where entity_id = 'dev'
)
select h.* from hierarchy h
inner join element e on h.type=e.type and h.path=e.path
where e.entity_id != h.entity_id;


-- e.g.
select * from siblings('jan') as s
inner join entity e on e.id = s.entity_id;



-- e.g. descendant entities with a field 'level'
select d.*, e.type, e.data
from descendants('design') d
join entity e on e.id=d.entity_id
where e.data?'level';


-- "function" that updates data
select entity_move('design', 'multidisc', 'org.other');
