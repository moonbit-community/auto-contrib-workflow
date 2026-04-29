# moonbit-community/db-migration-lite

Small migration discovery, ordering, and journal-planning utilities for
SQLite-oriented tools.

This package intentionally keeps database I/O outside the core API. Callers
provide discovered migration file contents, execute pending SQL with their own
SQLite adapter, and record successful migrations through the journal helpers.
If a later migration fails, `ApplyFailed` includes the partial journal so
callers can persist or retry from the successful prior migrations without
running them again.

```mbt check
///|
test "discover migrations" {
  let files : Array[@db_migration_lite.MigrationFile] = [
    {
      path: "migrations/010_add_index.sql",
      sql: "CREATE INDEX idx_users_email ON users(email);",
    },
    {
      path: "migrations/001_create_users.sql",
      sql: "CREATE TABLE users(id INTEGER PRIMARY KEY);",
    },
  ]
  let migrations = try! @db_migration_lite.Migration::discover(files)
  @debug.debug_inspect(
    migrations.map(migration => migration.version),
    content=(
      #|["001", "010"]
    ),
  )
}
```

```mbt check
///|
test "plan pending migrations" {
  let migrations = try! @db_migration_lite.Migration::discover([
    {
      path: "001_create_users.sql",
      sql: "CREATE TABLE users(id INTEGER PRIMARY KEY);",
    },
    {
      path: "002_add_email.sql",
      sql: "ALTER TABLE users ADD COLUMN email TEXT;",
    },
  ])
  let journal = @db_migration_lite.Journal::new().record_success(migrations[0])
  let plan = try! journal.plan(migrations)
  @debug.debug_inspect(
    plan.pending.map(migration => migration.version),
    content=(
      #|["002"]
    ),
  )
}
```

```mbt check
///|
test "apply pending migrations" {
  let migrations = try! @db_migration_lite.Migration::discover([
    {
      path: "001_create_users.sql",
      sql: "CREATE TABLE users(id INTEGER PRIMARY KEY);",
    },
  ])
  let journal = try! @db_migration_lite.Journal::new().apply_pending(
    migrations,
    _migration => Applied,
  )
  @debug.debug_inspect(
    journal.entries().map(entry => entry.version),
    content=(
      #|["001"]
    ),
  )
}
```
