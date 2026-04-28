///|
fn file(path : String, sql : String) -> @db_migration_lite.MigrationFile {
  { path, sql }
}

///|
fn entry(
  version : String,
  name : String,
  path : String,
) -> @db_migration_lite.JournalEntry {
  { version, name, path }
}

///|
test "discover parses fixtures and sorts by numeric version" {
  let migrations = try! @db_migration_lite.discover([
    file(
      "migrations/010_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT;",
    ),
    file(
      "migrations/001_create_users.sql", "CREATE TABLE users(id INTEGER PRIMARY KEY);",
    ),
    file(
      "migrations\\002_add_posts.sql", "CREATE TABLE posts(id INTEGER PRIMARY KEY);",
    ),
    file(
      "windows\\nested/003_add_tags.sql", "CREATE TABLE tags(id INTEGER PRIMARY KEY);",
    ),
    file(
      "unix/nested\\004_add_likes.sql", "CREATE TABLE likes(id INTEGER PRIMARY KEY);",
    ),
    file("V011__add_posts_index.sql", "CREATE INDEX idx_posts_id ON posts(id);"),
  ])
  @debug.assert_eq(
    migrations.map(migration => (migration.version, migration.name)),
    [
      ("001", "create_users"),
      ("002", "add_posts"),
      ("003", "add_tags"),
      ("004", "add_likes"),
      ("010", "add_email"),
      ("011", "add_posts_index"),
    ],
  )
}

///|
test "invalid migration file names are rejected" {
  let missing_sql : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("001_create_users.txt", ""))
  @debug.assert_eq(
    missing_sql,
    Err(
      InvalidFileName("001_create_users.txt", "expected a .sql migration file"),
    ),
  )
  let missing_name : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("001_.sql", ""))
  @debug.assert_eq(
    missing_name,
    Err(InvalidFileName("001_.sql", "expected a non-empty migration name")),
  )
  let non_numeric : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("v1_create_users.sql", ""))
  @debug.assert_eq(
    non_numeric,
    Err(InvalidFileName("v1_create_users.sql", "expected a numeric version")),
  )
  let missing_double_version : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("__create_users.sql", ""))
  @debug.assert_eq(
    missing_double_version,
    Err(
      InvalidFileName(
        "__create_users.sql", "expected a numeric version before __",
      ),
    ),
  )
  let missing_single_version : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("_create_users.sql", ""))
  @debug.assert_eq(
    missing_single_version,
    Err(
      InvalidFileName(
        "_create_users.sql", "expected a numeric version before _",
      ),
    ),
  )
  let missing_separator : Result[
    @db_migration_lite.Migration,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.parse_file(file("001.sql", ""))
  @debug.assert_eq(
    missing_separator,
    Err(
      InvalidFileName(
        "001.sql", "expected <version>_<name>.sql or V<version>__<name>.sql",
      ),
    ),
  )
}

///|
test "duplicate versions are rejected during discovery" {
  let result : Result[
    Array[@db_migration_lite.Migration],
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.discover([
    file("001_create_users.sql", ""),
    file("1_create_posts.sql", ""),
  ])
  @debug.assert_eq(
    result,
    Err(DuplicateVersion("1", "001_create_users.sql", "1_create_posts.sql")),
  )
}

///|
test "validate_ordered rejects out of order migrations" {
  let migrations = [
    try! @db_migration_lite.parse_file(file("002_second.sql", "")),
    try! @db_migration_lite.parse_file(file("001_first.sql", "")),
  ]
  let result : Result[Unit, @db_migration_lite.MigrationError] = try? @db_migration_lite.validate_ordered(
    migrations,
  )
  @debug.assert_eq(result, Err(OutOfOrder("002", "001")))
}

///|
test "plan separates applied and pending migrations" {
  let migrations = try! @db_migration_lite.discover([
    file("001_create_users.sql", ""),
    file("002_add_email.sql", ""),
    file("003_add_posts.sql", ""),
  ])
  let journal = try! @db_migration_lite.Journal::from_entries([
    entry("001", "create_users", "001_create_users.sql"),
    entry("002", "add_email", "002_add_email.sql"),
  ])
  let migration_plan = try! @db_migration_lite.plan(migrations, journal)
  @debug.assert_eq(migration_plan.applied.map(migration => migration.version), [
    "001", "002",
  ])
  @debug.assert_eq(migration_plan.pending.map(migration => migration.version), [
    "003",
  ])
}

///|
test "journal rejects duplicates and unknown applied versions" {
  let duplicate : Result[
    @db_migration_lite.Journal,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.Journal::from_entries([
    entry("001", "create_users", "001_create_users.sql"),
    entry("1", "create_posts", "1_create_posts.sql"),
  ])
  @debug.assert_eq(duplicate, Err(DuplicateJournalVersion("1")))
  let migrations = try! @db_migration_lite.discover([
    file("001_create_users.sql", ""),
  ])
  let journal = try! @db_migration_lite.Journal::from_entries([
    entry("002", "add_email", "002_add_email.sql"),
  ])
  let unknown : Result[
    @db_migration_lite.MigrationPlan,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.plan(migrations, journal)
  @debug.assert_eq(unknown, Err(UnknownAppliedVersion("002")))
}

///|
test "apply pending records successes and repeated apply is a no-op" {
  let migrations = try! @db_migration_lite.discover([
    file("001_create_users.sql", ""),
    file("002_add_email.sql", ""),
  ])
  let first = try! @db_migration_lite.apply_pending(
    migrations,
    @db_migration_lite.Journal::new(),
    _migration => Applied,
  )
  @debug.assert_eq(first.entries(), [
    entry("001", "create_users", "001_create_users.sql"),
    entry("002", "add_email", "002_add_email.sql"),
  ])
  let second = try! @db_migration_lite.apply_pending(migrations, first, _migration => {
    Failed("should not run")
  })
  @debug.assert_eq(second.entries(), [
    entry("001", "create_users", "001_create_users.sql"),
    entry("002", "add_email", "002_add_email.sql"),
  ])
  let repeated = second.record_success(migrations[0])
  @debug.assert_eq(repeated.entries(), second.entries())
}

///|
test "failed migration is not marked applied" {
  let migrations = try! @db_migration_lite.discover([
    file("001_create_users.sql", ""),
    file("002_add_email.sql", ""),
  ])
  let mut attempts = 0
  let result : Result[
    @db_migration_lite.Journal,
    @db_migration_lite.MigrationError,
  ] = try? @db_migration_lite.apply_pending(
    migrations,
    @db_migration_lite.Journal::new(),
    migration => {
      attempts += 1
      if migration.version == "001" {
        Applied
      } else {
        Failed("syntax error")
      }
    },
  )
  @debug.assert_eq(attempts, 2)
  match result {
    Err(ApplyFailed(version, reason, partial)) => {
      @debug.assert_eq(version, "002")
      @debug.assert_eq(reason, "syntax error")
      @debug.assert_eq(partial.entries(), [
        entry("001", "create_users", "001_create_users.sql"),
      ])
      let retry_versions : Array[String] = []
      let retry = try! @db_migration_lite.apply_pending(migrations, partial, migration => {
        retry_versions.push(migration.version)
        Applied
      })
      @debug.assert_eq(retry_versions, ["002"])
      @debug.assert_eq(retry.entries(), [
        entry("001", "create_users", "001_create_users.sql"),
        entry("002", "add_email", "002_add_email.sql"),
      ])
    }
    _ => fail("apply_pending should expose the partial journal on failure")
  }
}

///|
test "journal schema sql is stable" {
  @debug.assert_eq(
    @db_migration_lite.journal_table_name, "moonbit_schema_migrations",
  )
  @debug.assert_eq(
    @db_migration_lite.journal_schema_sql(),
    "CREATE TABLE IF NOT EXISTS moonbit_schema_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);",
  )
}
