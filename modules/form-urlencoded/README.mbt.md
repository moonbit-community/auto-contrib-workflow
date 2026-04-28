# moonbit-community/urlencoded

Small `application/x-www-form-urlencoded` encoder and decoder for ordered form
pairs.

```mbt check
///|
test "decode example" {
  let pairs = try! @urlencoded.decode(
    "name=hello+world&tag=a&tag=b&redirect_uri=https%3A%2F%2Fexample.com",
  )
  @debug.debug_inspect(
    pairs,
    content=(
      #|[
      #|  { key: "name", value: "hello world" },
      #|  { key: "tag", value: "a" },
      #|  { key: "tag", value: "b" },
      #|  { key: "redirect_uri", value: "https://example.com" },
      #|]
    ),
  )
}
```

```mbt check
///|
test "encode example" {
  let pairs : Array[@urlencoded.Pair] = [
    { key: "name", value: "hello world" },
    { key: "word", value: "café" },
  ]
  let encoded = @urlencoded.encode(pairs)
  @debug.debug_inspect(
    encoded,
    content=(
      #|"name=hello+world&word=caf%C3%A9"
    ),
  )
}
```

```mbt check
///|
test "escape example" {
  @debug.debug_inspect(
    @urlencoded.escape("https://example.com/a b?x=y"),
    content=(
      #|"https%3A%2F%2Fexample.com%2Fa+b%3Fx%3Dy"
    ),
  )
}
```
