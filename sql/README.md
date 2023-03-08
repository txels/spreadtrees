# The data model

The simplest model uses two abstractions: one for entities and one for relations (which can be hierarchical).

Optional extensions to the model include versioning and catalogs (for property values).

`schema.sql` is the simple non-versioned model.

## Entities

Entities have an `id`, a `type` (text) and free-form `data` (jsonb).

### Schema driven by application code

Because all fields for an entity of a given type are stored in `data`, the DB application is schema-agnostic (at the moment).

This means the schema must be enforced (if needed) at the application level, which will know which fields are relevant for each entity type.

## Relations (and Hierarchies)

Relations have an `id`, a `type`, a `path` and an `entity_id` (the _target_ of the relationship).

`path` is the full hierarchical path to the _source_ entity of the relationship (although relations are not necessarily directional, so I'm using source and target rather arbitrarily here).

> DB table is called `hierarchy` (renamed as `relation` in `versioning.sql`).

The id is currently there only for simpler addressability, but maybe a preserved "identity" can emerge later if we add qualifying data/metadata to relationships. E.g. a "position" in Ourspace could be a qualified relationship between team and person objects with additional data (dates, roles...).

> Open Q: relations versus entities, do they need to be different?
> Could a relation be stored as a special entity of type `relation` and have the ids of referenced entities as fields?
> I feel that this could make versioning simpler, but at the cost of making it harder to associate special behaviour to relations (e.g. like optimised hierarchy maintenance and query).
> At this moment I don't think mixing both entities and relations up would bring more benefit than cost.

## Values and catalogs

With data in entity being just JSON, how do we encode non-primitive values that have meaning in a normalised way? E.g. we may have a "seniority" property that is a label but can convey some associated properties (like e.g. rank). Or how do we handle "enumerated" properties, where valid values are only from a well known set? We could do this fully in application code, but the data model can offer some support.

Enter catalogs.

A catalog entry contains an `id` (which might not be necessary), a (property) `name`, a `value` and data. `(name, value)` pairs are unique.

Catalogs allow us to keep a meaningful property value in the entity that can be shown to users (and thus not require to always perform a lookup), while allowing us to look up the associated data when needed (e.g. to compute things like sort by hierarchy rank/value or compute aggregated scorecards based on those within the DB - thus making the database data/app layer accessible to multiple applications in a programming language-agnostic way).

> TODO: explore how catalog entries could be encoded as `entity` with type `"catalog"` and retrievable via id being `name:value` (although that could be encoded in the data... however the concern here could be query performance and index size).

## Changelog

## Versioning

`versioning.sql`

Versioning is inspired by git but is a simpler model, intended to handle "branches" that are drafts, but within a branch there is no concept of multiple commits (ATM) as individual addressable operations. So multiple versions of an entity within a branch are not recorded ATM. They could be reconstructed by recording a linear sequence of change events that contain the individual changes.

[Versioning](./versioning.sql) includes:

- Additions to `entity` and `relation`: versioned entities now have an additional `version` (new versions generated automatically upon update using "copy on save"), and `id` is no longer unique - now it's unique on `(id, version)`.
- A `revision` as a way to name a set of versioned entities (only a `name`, an `id` and a `parent`)
- A list of entity versions for a revision in `revision_entity`

Parallels with the `git` model:

- `entity` is similar to `blob`, but unlike blobs, entities do have an identity (encoded their `id`). In git there isn't as much an "identity of a file", this is recorded as the entry of the blob (data) in the tree ([path->blob]).
- `revision` (could be renamed `branch`, `draft` or `variant`) is a combination of `tree` and `commit` and could be compared to a "squashed branch", i.e. a single commit that accumulates changes to one branch.
  - In particular, all of the entity versions linked to a revision are stored as entries in `revision_entity` (which is very similar to a git tree).

Our model is simpler because it is intended to keep a record of "patches" or "change events" applied within a revision as a separate construct.

## Known issues and limitations

### Versioning for relations

TODO: add versioning to relations (currently `hierarchy`).

Because relations are different from entities, they will require their own implementation of versioning, which is a duplication of the one for entities.

- `hierarchy_version` will have an additional `version` field.
- We'll have additional entries within a `revision` via `revision_relation`,
- The corresponding "copy on save" update triggers and utility functions
- Updates the revision creation functions (like `branch()`).
- Additionally, the hierarchical "tree update" triggers/functions would have to be rewritten to be revision-aware (update tree for all related `hierarchy` rows within the revision - which will create a new hierarchy_version)

However, references to entities in `hierarchy` (`entity_id`) don't need to be updated to include version, since the right entity should be retrieved based on matching the revision for the relation.

### 2-step update and Constraints

Updates currently work as:

- Upon update, the updated record gets a new version and updated_at set in a pre-update trigger (before save) - (this is returned and will be saved together with the updated data in a single DB write)
- After update, we make a copy of the old record verbatim

This makes implementation simpler, however at the cost of there not being for a short time a record with (oldid, oldversion) - this means we cannot create/enforce FK constraints to the (id, version) pair in the `revision_entity` table. This is not too problematic because inserts to that table are only done within DB functions and not manually. And we should not delete rows in entity (except maybe in garbage collection operations).
