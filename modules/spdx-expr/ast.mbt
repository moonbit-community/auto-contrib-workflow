///|
/// A simple SPDX license expression.
pub(all) enum SimpleExpr {
  /// A single SPDX license identifier, such as `MIT` or `Apache-2.0`.
  License(String)
  /// A license identifier with the SPDX `+` or-later suffix, such as
  /// `GPL-2.0+`.
  LicenseOrLater(String)
  /// A user-defined SPDX license reference.
  ///
  /// The optional first field stores the `DocumentRef-*` id without the
  /// `DocumentRef-` prefix. The second field stores the `LicenseRef-*` id
  /// without the `LicenseRef-` prefix.
  LicenseRef(String?, String)
} derive(Eq, Debug)

///|
/// A parsed SPDX license expression.
pub(all) enum Expr {
  /// A simple license expression.
  Simple(SimpleExpr)
  /// A license identifier with an SPDX exception, such as
  /// `GPL-2.0-only WITH Classpath-exception-2.0`.
  With(SimpleExpr, String)
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
    With(_, _) | Simple(_) => 3
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
    Simple(simple) => format_simple(simple)
    With(simple, exception_id) =>
      format_simple(simple) + " WITH " + exception_id
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

///|
fn format_simple(simple : SimpleExpr) -> String {
  match simple {
    License(id) => id
    LicenseOrLater(id) => id + "+"
    LicenseRef(None, id) => "LicenseRef-" + id
    LicenseRef(Some(document_ref), id) =>
      "DocumentRef-" + document_ref + ":LicenseRef-" + id
  }
}
