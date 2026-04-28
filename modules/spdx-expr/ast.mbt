///|
/// A parsed SPDX license expression.
pub(all) enum Expr {
  /// A single license identifier, such as `MIT` or `Apache-2.0`.
  License(String)
  /// A license identifier with an SPDX exception, such as
  /// `GPL-2.0-only WITH Classpath-exception-2.0`.
  With(String, String)
  /// A conjunction of two license expressions.
  And(Expr, Expr)
  /// A disjunction of two license expressions.
  Or(Expr, Expr)
} derive(Eq, Debug)

///|
fn Expr::precedence(self : Expr) -> Int {
  match self {
    Or(_, _) => 1
    And(_, _) => 2
    With(_, _) | License(_) => 3
  }
}

///|
/// Formats an SPDX license expression with normalized operator spacing and
/// minimal parentheses.
pub fn format(expr : Expr) -> String {
  format_with_precedence(expr, 0)
}

///|
fn format_with_precedence(expr : Expr, parent_precedence : Int) -> String {
  let own_precedence = expr.precedence()
  let text = match expr {
    License(id) => id
    With(license_id, exception_id) => license_id + " WITH " + exception_id
    And(left, right) =>
      format_with_precedence(left, own_precedence) +
      " AND " +
      format_with_precedence(right, own_precedence)
    Or(left, right) =>
      format_with_precedence(left, own_precedence) +
      " OR " +
      format_with_precedence(right, own_precedence)
  }
  if own_precedence < parent_precedence {
    "(" + text + ")"
  } else {
    text
  }
}
