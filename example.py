import asyncio
import json
import os

import asyncpg

DBURL = os.environ.get('DATABASE_URL', 'postgresql://postgres@localhost/postgres')


async def main():
    # Establish a connection to an existing database named "test"
    # as a "postgres" user.
    conn = await asyncpg.connect(DBURL)

    # field mappings
    # - ltree into list of strings
    await conn.set_type_codec(
        'ltree',
        encoder=lambda x: '.'.join(x),
        decoder=lambda x: x.split('.'),
        #schema='pg_catalog'
    )
    # - jsonb into dict
    await conn.set_type_codec(
        'jsonb',
        encoder=json.dumps,
        decoder=json.loads,
        schema='pg_catalog'
    )
    await conn.set_builtin_type_codec('hstore', codec_name='pg_contrib.hstore')

    # example with ltree conversion
    stmt = await conn.prepare("""
    select
        h.type hierarchy_type,
        h.path,
        array_agg(e.id) entity_ids,
        $1 field,
        array_agg(e.data->>$1) values
    from
        entity e
    inner join
        hierarchy h on h.entity_id = e.id
    where
        e.data?$1
        group by h.path, h.type
    """)
    rows = await stmt.fetch('name')
    print(json.dumps([{k: v for (k, v) in list(r.items())} for r in rows], indent=2))

    # example with ltree jsonb conversion
    stmt = await conn.prepare("""
    select
        id, type, path, data
    from
        entity_tree
    """)
    rows = await stmt.fetch()
    print(json.dumps([{k: v for (k, v) in list(r.items())} for r in rows], indent=2))

    # rows = await conn.fetch("""
    # select * from entity e
    # inner join hierarchy h on h.entity_id = e.id
    # """)
    # # import pdb; pdb.set_trace()
    # print(json.dumps([{k: v for (k, v) in list(r.items())} for r in rows], indent=2))
    # Close the connection.
    await conn.close()

asyncio.run(main())
