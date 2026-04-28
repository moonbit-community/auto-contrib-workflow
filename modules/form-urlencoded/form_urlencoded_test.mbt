///|
fn pair(key : String, value : String) -> @urlencoded.Pair {
  { key, value }
}

///|
test "decode ordered pairs and duplicate keys" {
  let actual = try! @urlencoded.decode("a=b&tag=one&tag=two&empty=&bare")
  let expected = [
    pair("a", "b"),
    pair("tag", "one"),
    pair("tag", "two"),
    pair("empty", ""),
    pair("bare", ""),
  ]
  @debug.assert_eq(actual, expected)
}

///|
test "decode plus and percent-encoded utf8" {
  let actual = try! @urlencoded.decode(
    "name=hello+world&redirect_uri=https%3A%2F%2Fexample.com&word=caf%C3%A9",
  )
  let expected = [
    pair("name", "hello world"),
    pair("redirect_uri", "https://example.com"),
    pair("word", "café"),
  ]
  @debug.assert_eq(actual, expected)
}

///|
test "strict decode reports invalid percent escapes with byte offsets" {
  let invalid_hex : Result[Array[@urlencoded.Pair], @urlencoded.DecodeError] = try? @urlencoded.decode(
    "ok=yes&bad=%G0",
  )
  @debug.assert_eq(invalid_hex, Err(InvalidPercent(11, "%G0")))
  let short_escape : Result[Array[@urlencoded.Pair], @urlencoded.DecodeError] = try? @urlencoded.decode(
    "short=%",
  )
  @debug.assert_eq(short_escape, Err(InvalidPercent(6, "%")))
}

///|
test "strict decode rejects invalid percent-encoded utf8" {
  let leading : Result[Array[@urlencoded.Pair], @urlencoded.DecodeError] = try? @urlencoded.decode(
    "bad=%C3%28",
  )
  @debug.assert_eq(leading, Err(InvalidUtf8(4)))
  let after_prefix : Result[Array[@urlencoded.Pair], @urlencoded.DecodeError] = try? @urlencoded.decode(
    "bad=ok%C3%28",
  )
  @debug.assert_eq(after_prefix, Err(InvalidUtf8(6)))
}

///|
test "lenient decode keeps malformed escapes and replaces malformed utf8" {
  let actual = try! @urlencoded.decode(
    "bad=%G0&short=%&utf8=%C3%28",
    mode=Lenient,
  )
  @debug.assert_eq(actual, [
    pair("bad", "%G0"),
    pair("short", "%"),
    pair("utf8", "�("),
  ])
}

///|
test "encode ordered pairs using form-urlencoded rules" {
  let pairs = [
    pair("name", "hello world"),
    pair("tag", "a"),
    pair("tag", "b"),
    pair("redirect_uri", "https://example.com/a b"),
    pair("word", "café"),
  ]
  @debug.assert_eq(
    @urlencoded.encode(pairs),
    "name=hello+world&tag=a&tag=b&redirect_uri=https%3A%2F%2Fexample.com%2Fa+b&word=caf%C3%A9",
  )
}

///|
test "escape encodes one form component" {
  @debug.assert_eq(@urlencoded.escape("hello world"), "hello+world")
  @debug.assert_eq(@urlencoded.escape("x+y"), "x%2By")
  @debug.assert_eq(@urlencoded.escape("café"), "caf%C3%A9")
  @debug.assert_eq(
    @urlencoded.escape("https://example.com/a?b=c&d=e"),
    "https%3A%2F%2Fexample.com%2Fa%3Fb%3Dc%26d%3De",
  )
}

///|
test "round trip preserves observable pairs" {
  let pairs = [pair("a b", "x+y"), pair("empty", ""), pair("emoji", "☕")]
  @debug.assert_eq(try! @urlencoded.decode(@urlencoded.encode(pairs)), pairs)
}
