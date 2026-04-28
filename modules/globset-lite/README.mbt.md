# moonbit-community/globset_lite

Small compiled glob matcher for tools that need to test paths without walking
the filesystem.

```mbt check
///|
test "glob example" {
  let glob = try! @globset_lite.compile("src/**/*.mbt")
  @debug.assert_eq(@globset_lite.matches(glob, "src/main.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(glob, "src/lib/parser.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(glob, "tests/parser.mbt"), false)
}
```

```mbt check
///|
test "glob set example" {
  let set = try! @globset_lite.compile_set([
    "src/**/*.mbt", "tests/**/*.json", "assets/**/*.[pj][np]g",
  ])
  @debug.assert_eq(@globset_lite.matches_any(set, "assets/icon.png"), true)
  @debug.assert_eq(@globset_lite.matched_ids(set, "tests/data/case.json"), [1])
}
```

Supported syntax is deliberately small: `*`, `?`, `**` as a full path segment,
and character classes such as `[abc]`, `[a-z]`, and `[!0-9]`. Both patterns and
candidate paths normalize `\` to `/` before matching. Candidate paths with
leading, repeated, or trailing separators do not match.
