///|
fn rule(
  source : String,
  line : Int,
  pattern : String,
  base? : String = "",
  negated? : Bool = false,
  directory_only? : Bool = false,
  anchored? : Bool = false,
) -> @ignorefile_matcher.IgnoreRule {
  { source, line, pattern, base, negated, directory_only, anchored }
}

///|
fn assert_true(value : Bool) -> Unit raise {
  @debug.assert_eq(value, true)
}

///|
fn assert_false(value : Bool) -> Unit raise {
  @debug.assert_eq(value, false)
}

///|
test "parse ignores blank lines and comments" {
  let text =
    #|
    #|# generated files
    #|
    #|*.log
    #|target/
    #|
  let file = @ignorefile_matcher.parse(text, source=".gitignore")
  @debug.assert_eq(file.source, ".gitignore")
  @debug.assert_eq(file.rules, [
    rule(".gitignore", 4, "*.log"),
    rule(".gitignore", 5, "target", directory_only=true),
  ])
}

///|
test "parse negation anchors and escaped comment prefixes" {
  let text =
    #|\#literal
    #|\!literal
    #|!/keep.mbt
    #|/build/cache/
  let file = @ignorefile_matcher.parse(text, source=".gitignore")
  @debug.assert_eq(file.rules, [
    rule(".gitignore", 1, "#literal"),
    rule(".gitignore", 2, "!literal"),
    rule(".gitignore", 3, "keep.mbt", negated=true, anchored=true),
    rule(".gitignore", 4, "build/cache", directory_only=true, anchored=true),
  ])
}

///|
test "parse trims crlf lines and skips empty rules" {
  let file = @ignorefile_matcher.parse(
    "!\r\n  ./build/  \r\n/\r\na\n",
    source=".gitignore",
  )
  @debug.assert_eq(file.rules, [
    rule(".gitignore", 2, "build", directory_only=true),
    rule(".gitignore", 4, "a"),
  ])
}

///|
test "floating patterns match nested files and directory descendants" {
  let matcher = @ignorefile_matcher.from_text("*.log\ntarget/\n")
  assert_true(matcher.is_ignored("app.log"))
  assert_true(matcher.is_ignored("src/app.log"))
  assert_true(matcher.is_ignored("target/main.mbt"))
  assert_true(matcher.is_ignored("src/target/main.mbt"))
  assert_false(matcher.is_ignored("target"))
  assert_true(matcher.is_ignored("target", is_dir=true))
  assert_false(matcher.is_ignored("src/main.mbt"))
}

///|
test "anchored patterns stay relative to their ignore file base" {
  let matcher = @ignorefile_matcher.from_text(
    "/generated/*.mbt\ncache/\n",
    source="src/.moonignore",
    base="src",
  )
  assert_true(matcher.is_ignored("src/generated/api.mbt"))
  assert_false(matcher.is_ignored("test/generated/api.mbt"))
  assert_true(matcher.is_ignored("src/lib/cache/data.bin"))
  assert_false(matcher.is_ignored("cache/data.bin"))
}

///|
test "candidate paths are normalized before matching" {
  let matcher = @ignorefile_matcher.from_text("/src/main.mbt\ntarget/\n")
  assert_true(matcher.is_ignored("./src/main.mbt"))
  assert_true(matcher.is_ignored("/src/main.mbt"))
  assert_true(matcher.is_ignored("target/   "))
}

///|
test "nested ignore file rules do not match the base directory itself" {
  let matcher = @ignorefile_matcher.from_text("*.mbt\n", base="src")
  assert_false(matcher.is_ignored("src", is_dir=true))
}

///|
test "negation and later rules override earlier matches" {
  let matcher = @ignorefile_matcher.from_text("*.mbt\n!main.mbt\nmain.mbt\n")
  assert_true(matcher.is_ignored("lib/util.mbt"))
  assert_true(matcher.is_ignored("main.mbt"))
  let reinclude = @ignorefile_matcher.from_text("*.mbt\n!main.mbt\n")
  assert_false(reinclude.is_ignored("main.mbt"))
  assert_true(reinclude.is_ignored("lib/util.mbt"))
}

///|
test "multiple ignore files use caller supplied precedence" {
  let root = @ignorefile_matcher.parse(
    "*.tmp\n!important.tmp\n",
    source=".gitignore",
  )
  let nested = @ignorefile_matcher.parse(
    "!*.tmp\ncache/\n",
    source="src/.gitignore",
    base="src",
  )
  let matcher = @ignorefile_matcher.build([root, nested])
  assert_true(matcher.is_ignored("build.tmp"))
  assert_false(matcher.is_ignored("important.tmp"))
  assert_false(matcher.is_ignored("src/build.tmp"))
  assert_true(matcher.is_ignored("src/cache/out.bin"))
}

///|
test "explain returns final matching rule" {
  let matcher = @ignorefile_matcher.from_text(
    "*.tmp\n!keep.tmp\n",
    source=".gitignore",
  )
  @debug.assert_eq(
    matcher.explain("keep.tmp"),
    Some({
      ignored: false,
      rule: rule(".gitignore", 2, "keep.tmp", negated=true),
    }),
  )
  @debug.assert_eq(
    matcher.explain("scratch.tmp"),
    Some({ ignored: true, rule: rule(".gitignore", 1, "*.tmp") }),
  )
  @debug.assert_eq(matcher.explain("src/main.mbt"), None)
}

///|
test "glob syntax supports question star globstar and classes" {
  let text =
    #|src/**/test?.mbt
    #|assets/*.[jp][pn]g
    #|logs/[!0-9]*.txt
  let matcher = @ignorefile_matcher.from_text(text)
  assert_true(matcher.is_ignored("src/test1.mbt"))
  assert_true(matcher.is_ignored("src/a/b/test2.mbt"))
  assert_false(matcher.is_ignored("src/a/b/test22.mbt"))
  assert_true(matcher.is_ignored("assets/icon.png"))
  assert_true(matcher.is_ignored("assets/photo.jpg"))
  assert_false(matcher.is_ignored("assets/nested/icon.png"))
  assert_true(matcher.is_ignored("logs/app.txt"))
  assert_false(matcher.is_ignored("logs/1app.txt"))
}

///|
test "glob edge cases cover descendants trailing stars and invalid classes" {
  let text =
    #|/foo
    #|src/**
    #|foo*
    #|a**b
    #|file[0-9]
    #|[
    #|[ab
    #|[]
  let matcher = @ignorefile_matcher.from_text(text)
  assert_true(matcher.is_ignored("foo/bar"))
  assert_true(matcher.is_ignored("src/a/b"))
  assert_true(matcher.is_ignored("foobar"))
  assert_true(matcher.is_ignored("ab"))
  assert_false(matcher.is_ignored("file"))
  assert_true(matcher.is_ignored("["))
  assert_true(matcher.is_ignored("[ab"))
  assert_true(matcher.is_ignored("[]"))
}

///|
test "backslashes are normalized as path separators" {
  let matcher = @ignorefile_matcher.from_text("build\\cache\\*.bin\n")
  assert_true(matcher.is_ignored("build/cache/out.bin"))
  assert_true(matcher.is_ignored("build\\cache\\out.bin"))
}
