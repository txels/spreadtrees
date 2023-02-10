-- name: get_siblings_v1?
-- Returns the list of siblings (in any hierarchy) from an entity id
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
  , p2.type      as hierarchy
  , sib.id
  , sib.type
from
    parent p1
    inner join parent p2 on p1.parent = p2.parent
    inner join entity sib on sib.id = p2.entity_id
where
    p1.entity_id = :id
    and p1.entity_id <> p2.entity_id
;

-- name: get_children?
select
    e.id
  , h.type      relation
  , h.path
  , h.entity_id related_id
  , e2.type     related_type
from
    entity e
  , lateral children(e.id) h
    inner join entity e2 on h.entity_id = e2.id
where
    e.id = :id
;

-- name: get_siblings?
-- Returns the list of siblings (in any hierarchy) from an entity id
select
    e.id
  , h.type      relation
  , h.path
  , h.entity_id related_id
  , e2.type     related_type
from
    entity e
  , lateral siblings(e.id) h
    inner join entity e2 on h.entity_id = e2.id
where
    e.id = :id
;
