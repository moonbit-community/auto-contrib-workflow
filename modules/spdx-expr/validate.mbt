///|
/// A structured validation error for parsed SPDX license expressions.
pub(all) suberror ValidationError {
  /// The license identifier was not present in the injected license set.
  UnknownLicense(String)
  /// The exception identifier was not present in the injected exception set.
  UnknownException(String)
} derive(Eq, Debug)

///|
/// Validates license and exception identifiers against caller-provided sets.
///
/// The parser intentionally does not bundle the SPDX License List. Pass the
/// license and exception identifiers that are accepted by your registry or
/// tooling policy.
pub fn validate(
  expr : Expr,
  license_ids : Array[String],
  exception_ids? : Array[String] = [],
) -> Unit raise ValidationError {
  validate_expr(expr, license_ids, exception_ids)
}

///|
fn validate_expr(
  expr : Expr,
  license_ids : Array[String],
  exception_ids : Array[String],
) -> Unit raise ValidationError {
  match expr {
    License(id) => validate_license_id(id, license_ids)
    With(license_id, exception_id) => {
      validate_license_id(license_id, license_ids)
      if !contains_string(exception_ids, exception_id) {
        raise UnknownException(exception_id)
      }
    }
    And(left, right) | Or(left, right) => {
      validate_expr(left, license_ids, exception_ids)
      validate_expr(right, license_ids, exception_ids)
    }
  }
}

///|
fn validate_license_id(
  license_id : String,
  license_ids : Array[String],
) -> Unit raise ValidationError {
  if !contains_string(license_ids, license_id) {
    raise UnknownLicense(license_id)
  }
}

///|
fn contains_string(values : Array[String], needle : String) -> Bool {
  let mut found = false
  for value in values {
    if value == needle {
      found = true
    }
  }
  found
}
