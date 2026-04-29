///|
test "ceil div rounds positive values up" {
  @debug.assert_eq(ceil_div(1, 3), 1)
  @debug.assert_eq(ceil_div(3, 3), 1)
  @debug.assert_eq(ceil_div(4, 3), 2)
  @debug.assert_eq(ceil_div(9, 3), 3)
}

///|
test "non negative delta never returns a negative delay" {
  @debug.assert_eq(non_negative_delta(10, 3), 7)
  @debug.assert_eq(non_negative_delta(10, 10), 0)
  @debug.assert_eq(non_negative_delta(3, 10), 0)
}
