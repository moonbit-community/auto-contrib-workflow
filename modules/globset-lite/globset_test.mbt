///|
test "single glob matches whole normalized paths" {
  let glob = try! @globset_lite.compile("src/**/*.mbt")
  @debug.assert_eq(@globset_lite.matches(glob, "src/main.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(glob, "src/lib/parser.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(glob, "src\\lib\\parser.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(glob, "src/main.json"), false)
  @debug.assert_eq(@globset_lite.matches(glob, "tests/main.mbt"), false)
}

///|
test "star and question stay inside one path segment" {
  let star = try! @globset_lite.compile("src/*.mbt")
  @debug.assert_eq(@globset_lite.matches(star, "src/main.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(star, "src/lib/main.mbt"), false)
  let question = try! @globset_lite.compile("file-?.txt")
  @debug.assert_eq(@globset_lite.matches(question, "file-a.txt"), true)
  @debug.assert_eq(@globset_lite.matches(question, "file-ab.txt"), false)
}

///|
test "character classes support literals ranges and negation" {
  let class = try! @globset_lite.compile("tests/[ab][0-2].json")
  @debug.assert_eq(@globset_lite.matches(class, "tests/a1.json"), true)
  @debug.assert_eq(@globset_lite.matches(class, "tests/b2.json"), true)
  @debug.assert_eq(@globset_lite.matches(class, "tests/c1.json"), false)
  @debug.assert_eq(@globset_lite.matches(class, "tests/a3.json"), false)
  let negated = try! @globset_lite.compile("logs/[!0-9].txt")
  @debug.assert_eq(@globset_lite.matches(negated, "logs/a.txt"), true)
  @debug.assert_eq(@globset_lite.matches(negated, "logs/7.txt"), false)
}

///|
test "recursive wildcard can match zero or more segments" {
  let suffix = try! @globset_lite.compile("**/*.mbt")
  @debug.assert_eq(@globset_lite.matches(suffix, "main.mbt"), true)
  @debug.assert_eq(@globset_lite.matches(suffix, "src/lib/main.mbt"), true)
  let directory = try! @globset_lite.compile("src/**")
  @debug.assert_eq(@globset_lite.matches(directory, "src"), true)
  @debug.assert_eq(@globset_lite.matches(directory, "src/lib/main.mbt"), true)
}

///|
test "glob set reports matching pattern ids" {
  let set = try! @globset_lite.compile_set([
    "src/**/*.mbt", "tests/**/*.json", "assets/**/*.[pj][np]g",
  ])
  @debug.assert_eq(
    @globset_lite.matches_any(set, "assets/icons/logo.png"),
    true,
  )
  @debug.assert_eq(@globset_lite.matches_any(set, "README.md"), false)
  @debug.assert_eq(@globset_lite.matched_ids(set, "src/lib/parser.mbt"), [0])
  @debug.assert_eq(@globset_lite.matched_ids(set, "assets/icons/logo.png"), [2])
}

///|
test "pattern text stores normalized separators" {
  let glob = try! @globset_lite.compile("src\\*.mbt")
  @debug.assert_eq(@globset_lite.pattern(glob), "src/*.mbt")
  @debug.assert_eq(@globset_lite.matches(glob, "src/main.mbt"), true)
}

///|
test "candidate paths keep empty segments significant" {
  let glob = try! @globset_lite.compile("src/*.mbt")
  @debug.assert_eq(@globset_lite.matches(glob, "/src/main.mbt"), false)
  @debug.assert_eq(@globset_lite.matches(glob, "src//main.mbt"), false)
  @debug.assert_eq(@globset_lite.matches(glob, "src/main.mbt/"), false)
  let set = try! @globset_lite.compile_set(["src/*.mbt", "src/**"])
  @debug.assert_eq(@globset_lite.matches_any(set, "src//main.mbt"), false)
  @debug.assert_eq(@globset_lite.matched_ids(set, "src/main.mbt/"), [])
}

///|
test "compile reports parse errors" {
  let empty : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "",
  )
  assert_true(empty is Err(EmptyPattern))
  let empty_segment : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "src//*.mbt",
  )
  assert_true(empty_segment is Err(EmptySegment(4)))
  let recursive : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "src/**.mbt",
  )
  assert_true(recursive is Err(InvalidRecursiveWildcard(4)))
  let unclosed : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "src/[ab.mbt",
  )
  assert_true(unclosed is Err(UnclosedClass(4)))
  let empty_class : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "src/[].mbt",
  )
  assert_true(empty_class is Err(EmptyClass(4)))
  let range : Result[@globset_lite.Glob, @globset_lite.GlobError] = try? @globset_lite.compile(
    "src/[z-a].mbt",
  )
  assert_true(range is Err(InvalidRange(5, "z-a")))
}

///|
test "compile set reports failing pattern ids" {
  let result : Result[@globset_lite.GlobSet, @globset_lite.GlobError] = try? @globset_lite.compile_set([
      "ok/*.mbt", "bad/**tail",
    ],
  )
  assert_true(
    result is Err(InvalidPattern(1, "`**` must be a complete path segment")),
  )
}

///|
test "describe error returns stable diagnostics" {
  @debug.assert_eq(@globset_lite.describe_error(EmptyPattern), "empty pattern")
  @debug.assert_eq(
    @globset_lite.describe_error(UnclosedClass(4)),
    "unclosed character class",
  )
  @debug.assert_eq(
    @globset_lite.describe_error(EmptySegment(3)),
    "empty path segment",
  )
  @debug.assert_eq(
    @globset_lite.describe_error(EmptyClass(4)),
    "empty character class",
  )
  @debug.assert_eq(
    @globset_lite.describe_error(InvalidRange(5, "z-a")),
    "invalid character class range z-a",
  )
  @debug.assert_eq(
    @globset_lite.describe_error(InvalidPattern(2, "empty pattern")),
    "empty pattern",
  )
}
