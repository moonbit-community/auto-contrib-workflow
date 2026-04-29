///|
/// A caller-supplied migration file.
pub(all) struct MigrationFile {
  /// The migration path or file name.
  path : String
  /// SQL text to execute when this migration is pending.
  sql : String
} derive(Eq, Debug)

///|
/// A parsed migration.
pub(all) struct Migration {
  /// Numeric migration version parsed from the file name.
  version : String
  /// Human-readable migration name parsed from the file name.
  name : String
  /// Original migration path.
  path : String
  /// SQL text to execute when this migration is pending.
  sql : String
} derive(Eq, Debug)

///|
/// A migration recorded in the schema journal.
pub(all) struct JournalEntry {
  /// Applied migration version.
  version : String
  /// Applied migration name.
  name : String
  /// Original migration path.
  path : String
} derive(Eq, Debug)

///|
/// A validated schema journal.
pub struct Journal {
  entries : Array[JournalEntry]
} derive(Eq, Debug)

///|
/// Pending and already-applied migrations for a journal.
pub(all) struct MigrationPlan {
  /// Migrations whose versions are already present in the journal.
  applied : Array[Migration]
  /// Migrations that still need to be executed.
  pending : Array[Migration]
} derive(Eq, Debug)

///|
/// Result returned by an application callback.
pub(all) enum ApplyResult {
  /// The migration executed successfully and can be recorded.
  Applied
  /// The migration failed and must not be recorded.
  Failed(String)
} derive(Eq, Debug)

///|
/// Migration discovery, ordering, or journal failure.
pub(all) suberror MigrationError {
  /// A migration file name does not match a supported format.
  InvalidFileName(String, String)
  /// Two migrations use the same logical version.
  DuplicateVersion(String, String, String)
  /// Migrations were supplied in descending or duplicate version order.
  OutOfOrder(String, String)
  /// The journal contains the same logical version more than once.
  DuplicateJournalVersion(String)
  /// The journal references a migration version that is not in the migration set.
  UnknownAppliedVersion(String)
  /// A pending migration failed while being applied.
  ///
  /// Fields are failed version, reason, and the journal containing successful
  /// migrations recorded before the failure.
  ApplyFailed(String, String, Journal)
} derive(Eq, Debug)

///|
/// Name of the default schema journal table.
pub let journal_table_name : String = "moonbit_schema_migrations"

///|
/// SQL for creating the default schema journal table.
///
/// The statement does not interpolate migration data; callers should use their
/// database adapter's parameter binding when inserting journal rows.
pub fn journal_schema_sql() -> String {
  "CREATE TABLE IF NOT EXISTS moonbit_schema_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);"
}

///|
/// Parses one migration file.
///
/// Supported file name forms are `<digits>_<name>.sql`,
/// `<digits>__<name>.sql`, and `V<digits>__<name>.sql`.
pub fn parse_file(file : MigrationFile) -> Migration raise MigrationError {
  let base = base_name(file.path)
  if !base.has_suffix(".sql") {
    raise InvalidFileName(file.path, "expected a .sql migration file")
  }
  let stem = string_from_view(base[:base.length() - 4])
  let (version, name) = split_stem(stem, file.path)
  validate_version(version, file.path)
  validate_name(name, file.path)
  { version, name, path: file.path, sql: file.sql }
}

///|
/// Parses, sorts, and validates migration files.
pub fn discover(
  files : Array[MigrationFile],
) -> Array[Migration] raise MigrationError {
  let migrations : Array[Migration] = []
  for file in files {
    migrations.push(parse_file(file))
  }
  migrations
  .mut_view()
  .sort_by((left, right) => compare_versions(left.version, right.version))
  validate_ordered(migrations)
  migrations
}

///|
/// Validates that migrations are in strict ascending version order.
pub fn validate_ordered(
  migrations : Array[Migration],
) -> Unit raise MigrationError {
  for index in 1..<migrations.length() {
    let previous = migrations[index - 1]
    let current = migrations[index]
    let ordering = compare_versions(previous.version, current.version)
    if ordering == 0 {
      raise DuplicateVersion(current.version, previous.path, current.path)
    } else if ordering > 0 {
      raise OutOfOrder(previous.version, current.version)
    }
  }
}

///|
/// Creates an empty journal.
pub fn Journal::new() -> Journal {
  { entries: [] }
}

///|
/// Creates a journal from existing rows and rejects duplicate versions.
pub fn Journal::from_entries(
  entries : Array[JournalEntry],
) -> Journal raise MigrationError {
  validate_journal_entries(entries)
  { entries: entries.copy() }
}

///|
/// Returns a copy of the journal entries.
pub fn Journal::entries(self : Journal) -> Array[JournalEntry] {
  self.entries.copy()
}

///|
/// Tests whether a version is already present in the journal.
pub fn Journal::contains(self : Journal, version : String) -> Bool {
  journal_contains(self.entries, version)
}

///|
/// Records a successfully applied migration.
///
/// Recording a migration whose version is already present is a no-op.
pub fn Journal::record_success(
  self : Journal,
  migration : Migration,
) -> Journal {
  if self.contains(migration.version) {
    self
  } else {
    let entries = self.entries.copy()
    entries.push({
      version: migration.version,
      name: migration.name,
      path: migration.path,
    })
    { entries, }
  }
}

///|
/// Builds a plan from ordered migrations and a journal.
pub fn plan(
  migrations : Array[Migration],
  journal : Journal,
) -> MigrationPlan raise MigrationError {
  validate_ordered(migrations)
  validate_journal_known(migrations, journal.entries)
  let applied : Array[Migration] = []
  let pending : Array[Migration] = []
  for migration in migrations {
    if journal.contains(migration.version) {
      applied.push(migration)
    } else {
      pending.push(migration)
    }
  }
  { applied, pending }
}

///|
/// Applies pending migrations in version order and records only successes.
///
/// The callback is responsible for executing SQL with the caller's database
/// adapter. If it returns `Failed`, that migration is not recorded, later
/// migrations are not attempted, and `ApplyFailed` exposes the journal with
/// prior successful migrations.
pub fn apply_pending(
  migrations : Array[Migration],
  journal : Journal,
  apply : (Migration) -> ApplyResult,
) -> Journal raise MigrationError {
  let migration_plan = plan(migrations, journal)
  let mut current = journal
  for migration in migration_plan.pending {
    match apply(migration) {
      Applied => current = current.record_success(migration)
      Failed(reason) => raise ApplyFailed(migration.version, reason, current)
    }
  }
  current
}

///|
fn split_stem(
  stem : String,
  path : String,
) -> (String, String) raise MigrationError {
  if stem.has_prefix("V") {
    match stem.find("__") {
      Some(separator) => {
        let version_start = 1
        if separator <= version_start {
          raise InvalidFileName(path, "expected a numeric version before __")
        }
        let version = string_from_view(stem[version_start:separator])
        let name = string_from_view(stem[separator + 2:])
        return (version, name)
      }
      None => ()
    }
  }
  match stem.find("_") {
    Some(separator) => {
      if separator == 0 {
        if stem.has_prefix("__") {
          raise InvalidFileName(path, "expected a numeric version before __")
        }
        raise InvalidFileName(path, "expected a numeric version before _")
      }
      let version = string_from_view(stem[:separator])
      let name_start = if separator + 1 < stem.length() &&
        string_from_view(stem[separator + 1:]).has_prefix("_") {
        separator + 2
      } else {
        separator + 1
      }
      let name = string_from_view(stem[name_start:])
      (version, name)
    }
    None =>
      raise InvalidFileName(
        path, "expected <version>_<name>.sql or V<version>__<name>.sql",
      )
  }
}

///|
fn validate_version(
  version : String,
  path : String,
) -> Unit raise MigrationError {
  let bytes = @encoding/utf8.encode(version)
  for byte in bytes {
    if !is_ascii_digit(byte) {
      raise InvalidFileName(path, "expected a numeric version")
    }
  }
}

///|
fn validate_name(name : String, path : String) -> Unit raise MigrationError {
  if name.trim().is_empty() {
    raise InvalidFileName(path, "expected a non-empty migration name")
  }
}

///|
fn validate_journal_entries(
  entries : Array[JournalEntry],
) -> Unit raise MigrationError {
  for index in 0..<entries.length() {
    for other in (index + 1)..<entries.length() {
      if compare_versions(entries[index].version, entries[other].version) == 0 {
        raise DuplicateJournalVersion(entries[other].version)
      }
    }
  }
}

///|
fn validate_journal_known(
  migrations : Array[Migration],
  entries : Array[JournalEntry],
) -> Unit raise MigrationError {
  for entry in entries {
    if !migration_set_contains(migrations, entry.version) {
      raise UnknownAppliedVersion(entry.version)
    }
  }
}

///|
fn migration_set_contains(
  migrations : Array[Migration],
  version : String,
) -> Bool {
  for migration in migrations {
    if compare_versions(migration.version, version) == 0 {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn journal_contains(entries : Array[JournalEntry], version : String) -> Bool {
  for entry in entries {
    if compare_versions(entry.version, version) == 0 {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn base_name(path : String) -> String {
  let slash = path.rev_find("/")
  let backslash = path.rev_find("\\")
  let start = match (slash, backslash) {
    (Some(left), Some(right)) => max_int(left, right) + 1
    (Some(left), None) => left + 1
    (None, Some(right)) => right + 1
    (None, None) => 0
  }
  string_from_view(path[start:])
}

///|
fn compare_versions(left : String, right : String) -> Int {
  let normalized_left = trim_leading_zeroes(left)
  let normalized_right = trim_leading_zeroes(right)
  if normalized_left.length() != normalized_right.length() {
    normalized_left.length() - normalized_right.length()
  } else {
    normalized_left.lexical_compare(normalized_right)
  }
}

///|
fn trim_leading_zeroes(version : String) -> String {
  let bytes = @encoding/utf8.encode(version)
  let mut index = 0
  while index + 1 < bytes.length() && byte_is(bytes[index], 48) {
    index += 1
  }
  string_from_view(version[index:])
}

///|
fn string_from_view(view : StringView) -> String {
  String::from_array(view.to_array())
}

///|
fn is_ascii_digit(byte : Byte) -> Bool {
  byte.to_int() >= 48 && byte.to_int() <= 57
}

///|
fn byte_is(byte : Byte, value : Int) -> Bool {
  byte.to_int() == value
}

///|
fn max_int(left : Int, right : Int) -> Int {
  if left > right {
    left
  } else {
    right
  }
}
