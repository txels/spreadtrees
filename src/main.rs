use std::collections::HashMap;

use tokio_postgres::{types::*, Error, NoTls, Row};

#[derive(Clone, Debug)]
struct Ltree(String);
#[derive(Clone, Debug)]
struct Lquery(String);

impl ToSql for Ltree {
    fn to_sql(
        &self,
        ty: &Type,
        out: &mut bytes::BytesMut,
    ) -> Result<IsNull, Box<dyn std::error::Error + Sync + Send>> {
        use bytes::BufMut;
        // put the ltree version as the first byte
        out.put_u8(1);
        self.0.to_sql(ty, out)
    }

    fn accepts(ty: &Type) -> bool {
        ty.name() == "ltree"
    }

    to_sql_checked!();
}

#[derive(Debug)]
struct Hierarchy {
    path: Option<String>,
    typ: Option<String>,
    entity_id: Option<String>,
}

impl From<&Row> for Hierarchy {
    fn from(row: &Row) -> Self {
        Hierarchy {
            path: row.try_get("path").ok(),
            typ: row.try_get("type").ok(),
            entity_id: row.try_get("entity_id").ok(),
        }
    }
}

#[derive(Debug)]
struct Entity {
    id: Option<String>,
    typ: Option<String>,
    data: Option<HashMap<String, Option<String>>>,
}

impl From<&Row> for Entity {
    fn from(row: &Row) -> Self {
        Entity {
            id: row.try_get("id").ok(),
            typ: row.try_get("type").ok(),
            data: row.try_get("data").ok(),
        }
    }
}

#[tokio::main] // By default, tokio_postgres uses the tokio crate as its runtime.
async fn main() -> Result<(), Error> {
    // Connect to the database.
    let (client, connection) =
        tokio_postgres::connect("host=localhost user=postgres", NoTls).await?;

    // The connection object performs the actual communication with the database,
    // so spawn it off to run on its own.
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });

    let rows = client
        .query("SELECT id, type, data from entity", &[])
        .await?;

    // And then check that we got back the same string we sent over.
    println!("{:?}", rows[0]);
    println!("{:?}", Entity::from(&rows[0]));

    let rows = client
        .query("SELECT path::text, type, entity_id from hierarchy", &[])
        .await?;

    // And then check that we got back the same string we sent over.
    for row in rows {
        let hier: Hierarchy = Hierarchy::from(&row);
        println!("{:?}", hier);
    }

    Ok(())
}
