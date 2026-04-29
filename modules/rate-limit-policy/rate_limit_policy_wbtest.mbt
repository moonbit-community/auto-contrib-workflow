///|
test "ceil div rounds positive values up" {
  @debug.assert_eq(ceil_div(0, 3), 0)
  @debug.assert_eq(ceil_div(1, 3), 1)
  @debug.assert_eq(ceil_div(3, 3), 1)
  @debug.assert_eq(ceil_div(4, 3), 2)
  @debug.assert_eq(ceil_div(9, 3), 3)
  @debug.assert_eq(ceil_div(2_147_483_647, 2), 1_073_741_824)
}

///|
test "non negative delta never returns a negative delay" {
  @debug.assert_eq(non_negative_delta(10L, 3L), 7L)
  @debug.assert_eq(non_negative_delta(10L, 10L), 0L)
  @debug.assert_eq(non_negative_delta(3L, 10L), 0L)
}
