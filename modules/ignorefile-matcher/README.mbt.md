# moonbit-community/ignorefile_matcher

Small ignore-file parser and matcher for MoonBit tools that need `.gitignore`,
`.npmignore`, `.moonignore`, or similar rule files without walking the
filesystem.

The supported subset includes blank lines, comments, `!` negation, leading `/`
anchors, trailing `/` directory rules, `*`, `?`, `**` as a complete path
segment, and simple character classes. It intentionally does not claim full Git
compatibility.

```mbt check
///|
test "single ignore file example" {
  let matcher = @ignorefile_matcher.from_text(
    (
      #|# generated files
      #|*.tmp
      #|target/
      #|!keep.tmp
    ),
    source=".gitignore",
  )
  @debug.assert_eq(matcher.is_ignored("build.tmp"), true)
  @debug.assert_eq(matcher.is_ignored("target/main.mbt"), true)
  @debug.assert_eq(matcher.is_ignored("keep.tmp"), false)
}
```

```mbt check
///|
test "explain example" {
  let matcher = @ignorefile_matcher.from_text("*.log\n!audit.log\n")
  @debug.assert_eq(
    matcher.explain("audit.log"),
    Some({
      ignored: false,
      rule: {
        source: "",
        line: 2,
        pattern: "audit.log",
        base: "",
        negated: true,
        directory_only: false,
        anchored: false,
      },
    }),
  )
}
```

```mbt check
///|
test "multiple ignore files example" {
  let root = @ignorefile_matcher.parse("*.tmp\n", source=".gitignore")
  let nested = @ignorefile_matcher.parse(
    "!*.tmp\ncache/\n",
    source="src/.gitignore",
    base="src",
  )
  let matcher = @ignorefile_matcher.build([root, nested])
  @debug.assert_eq(matcher.is_ignored("build.tmp"), true)
  @debug.assert_eq(matcher.is_ignored("src/build.tmp"), false)
  @debug.assert_eq(matcher.is_ignored("src/cache/out.bin"), true)
}
```
