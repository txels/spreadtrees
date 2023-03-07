# Get started

- Postgres (via docker compose)
- Rust

Dependencies (included in Cargo.toml) were set up with:

```sh
cargo add tokio -F macros,rt-multi-thread
cargo add tokio-postgres
```

## The data model

See [Data model](./sql/README.md) for details.
