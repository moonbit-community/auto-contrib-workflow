# moonbit-community/spdx-expr

Parser, formatter, and validator for SPDX license expressions.

```mbt check
///|
test "parse and format expression" {
  let expr = try! @spdx_expr.parse("(MIT OR Apache-2.0) AND BSD-3-Clause")
  @debug.debug_inspect(
    @spdx_expr.format(expr),
    content=(
      #|"(MIT OR Apache-2.0) AND BSD-3-Clause"
    ),
  )
}
```

```mbt check
///|
test "validate with injected license sets" {
  let expr = try! @spdx_expr.parse("GPL-2.0-only WITH Classpath-exception-2.0")
  try! @spdx_expr.validate(expr, ["GPL-2.0-only"], exception_ids=[
    "Classpath-exception-2.0",
  ])
}
```

```mbt check
///|
test "inspect validation error" {
  let result : Result[Unit, @spdx_expr.ValidationError] = try? @spdx_expr.validate(
    try! @spdx_expr.parse("Unknown-1.0"),
    ["MIT"],
  )
  @debug.debug_inspect(
    result,
    content=(
      #|Err(UnknownLicense("Unknown-1.0"))
    ),
  )
}
```
