///|
fn common_licenses() -> Array[String] {
  ["MIT", "Apache-2.0", "BSD-3-Clause", "GPL-2.0", "GPL-2.0-only", "0BSD"]
}

///|
fn common_exceptions() -> Array[String] {
  ["Classpath-exception-2.0", "LLVM-exception", "Bison-exception-2.2"]
}

///|
test "parse and format simple license expression" {
  let expr = try! @spdx_expr.parse("MIT OR Apache-2.0")
  @debug.assert_eq(
    expr,
    Or(Simple(License("MIT")), Simple(License("Apache-2.0"))),
  )
  @debug.assert_eq(@spdx_expr.format(expr), "MIT OR Apache-2.0")
}

///|
test "parse SPDX WITH exception" {
  let expr = try! @spdx_expr.parse("GPL-2.0-only WITH Classpath-exception-2.0")
  @debug.assert_eq(
    expr,
    With(License("GPL-2.0-only"), "Classpath-exception-2.0"),
  )
  try! @spdx_expr.validate(
    expr,
    common_licenses(),
    exception_ids=common_exceptions(),
  )
  @debug.assert_eq(
    @spdx_expr.format(expr),
    "GPL-2.0-only WITH Classpath-exception-2.0",
  )
}

///|
test "parser respects parentheses and operator precedence" {
  let grouped = try! @spdx_expr.parse("(MIT OR Apache-2.0) AND BSD-3-Clause")
  @debug.assert_eq(
    @spdx_expr.format(grouped),
    "(MIT OR Apache-2.0) AND BSD-3-Clause",
  )

  let precedence = try! @spdx_expr.parse("MIT OR Apache-2.0 AND BSD-3-Clause")
  @debug.assert_eq(
    @spdx_expr.format(precedence),
    "MIT OR Apache-2.0 AND BSD-3-Clause",
  )
  @debug.assert_eq(
    precedence,
    Or(
      Simple(License("MIT")),
      And(Simple(License("Apache-2.0")), Simple(License("BSD-3-Clause"))),
    ),
  )
}

///|
test "parse SPDX license references" {
  let local_ref = try! @spdx_expr.parse("LicenseRef-MIT-Style-1")
  @debug.assert_eq(local_ref, Simple(LicenseRef(None, "MIT-Style-1")))
  @debug.assert_eq(@spdx_expr.format(local_ref), "LicenseRef-MIT-Style-1")
  try! @spdx_expr.validate(local_ref, common_licenses())

  let document_ref = try! @spdx_expr.parse(
    "DocumentRef-spdx-tool-1.2:LicenseRef-MIT-Style-2",
  )
  @debug.assert_eq(
    document_ref,
    Simple(LicenseRef(Some("spdx-tool-1.2"), "MIT-Style-2")),
  )
  @debug.assert_eq(
    @spdx_expr.format(document_ref),
    "DocumentRef-spdx-tool-1.2:LicenseRef-MIT-Style-2",
  )
  try! @spdx_expr.validate(document_ref, common_licenses())
}

///|
test "parse and validate SPDX or-later suffix" {
  let expr = try! @spdx_expr.parse("GPL-2.0+ OR MIT")
  @debug.assert_eq(
    expr,
    Or(Simple(LicenseOrLater("GPL-2.0")), Simple(License("MIT"))),
  )
  @debug.assert_eq(@spdx_expr.format(expr), "GPL-2.0+ OR MIT")
  try! @spdx_expr.validate(expr, common_licenses())
}

///|
test "validation matches license and exception ids case insensitively" {
  let expr = try! @spdx_expr.parse("mit WITH classpath-EXCEPTION-2.0")
  try! @spdx_expr.validate(expr, ["MIT"], exception_ids=[
    "Classpath-exception-2.0",
  ])
}

///|
test "round trip parse format parse" {
  let input = "MIT OR (Apache-2.0 AND BSD-3-Clause)"
  let first = try! @spdx_expr.parse(input)
  let formatted = @spdx_expr.format(first)
  let second = try! @spdx_expr.parse(formatted)
  @debug.assert_eq(second, first)
}

///|
test "validation reports unknown licenses and exceptions" {
  try! @spdx_expr.validate(
    try! @spdx_expr.parse("MIT OR Apache-2.0"),
    common_licenses(),
    exception_ids=common_exceptions(),
  )

  let unknown_license : Result[Unit, @spdx_expr.ValidationError] = try? @spdx_expr.validate(
    try! @spdx_expr.parse("MPL-2.0"),
    common_licenses(),
    exception_ids=common_exceptions(),
  )
  @debug.assert_eq(unknown_license, Err(UnknownLicense("MPL-2.0")))

  let unknown_exception : Result[Unit, @spdx_expr.ValidationError] = try? @spdx_expr.validate(
    try! @spdx_expr.parse("MIT WITH Unknown-exception"),
    common_licenses(),
    exception_ids=common_exceptions(),
  )
  @debug.assert_eq(
    unknown_exception,
    Err(UnknownException("Unknown-exception")),
  )
}

///|
test "parser reports invalid expressions" {
  let empty : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "",
  )
  @debug.assert_eq(empty, Err(ExpectedExpression(0)))

  let missing_rhs : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT AND",
  )
  @debug.assert_eq(missing_rhs, Err(ExpectedExpression(7)))

  let unclosed : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "(MIT OR Apache-2.0",
  )
  @debug.assert_eq(unclosed, Err(UnclosedParen(0)))

  let trailing_word : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT Apache-2.0",
  )
  @debug.assert_eq(trailing_word, Err(UnexpectedToken(4, "Apache-2.0")))

  let trailing_paren : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT )",
  )
  @debug.assert_eq(trailing_paren, Err(UnexpectedToken(4, ")")))

  let starts_with_operator : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "OR MIT",
  )
  @debug.assert_eq(starts_with_operator, Err(ExpectedExpression(0)))

  let invalid_start : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "#MIT",
  )
  @debug.assert_eq(invalid_start, Err(ExpectedIdentifier(0)))

  let missing_exception : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT WITH AND",
  )
  @debug.assert_eq(missing_exception, Err(ExpectedIdentifier(9)))

  let repeated_plus : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT++",
  )
  @debug.assert_eq(repeated_plus, Err(UnexpectedToken(3, "++")))

  let embedded_plus : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "MIT+foo",
  )
  @debug.assert_eq(embedded_plus, Err(UnexpectedToken(3, "+foo")))

  let license_ref_plus : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "LicenseRef-local+",
  )
  @debug.assert_eq(license_ref_plus, Err(UnexpectedToken(16, "+")))

  let document_ref_missing_colon : Result[
    @spdx_expr.Expr,
    @spdx_expr.ParseError,
  ] = try? @spdx_expr.parse("DocumentRef-doc")
  @debug.assert_eq(document_ref_missing_colon, Err(UnexpectedToken(15, "")))

  let document_ref_missing_license_ref : Result[
    @spdx_expr.Expr,
    @spdx_expr.ParseError,
  ] = try? @spdx_expr.parse("DocumentRef-doc:NotLicenseRef-x")
  @debug.assert_eq(
    document_ref_missing_license_ref,
    Err(ExpectedIdentifier(16)),
  )
}

///|
test "WITH only applies to a license identifier" {
  let compound : Result[@spdx_expr.Expr, @spdx_expr.ParseError] = try? @spdx_expr.parse(
    "(MIT OR Apache-2.0) WITH Classpath-exception-2.0",
  )
  @debug.assert_eq(compound, Err(InvalidWithTarget(20)))
}
