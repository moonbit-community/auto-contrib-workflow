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
test "saturating ready time caps unrepresentable timestamps" {
  let max = max_int64()
  @debug.assert_eq(saturating_ready_at(0L, 2, 100L), 200L)
  @debug.assert_eq(saturating_ready_at(5L, 0, 100L), 5L)
  @debug.assert_eq(saturating_ready_at(0L, 2, max), max)
  @debug.assert_eq(saturating_ready_at(max - 50L, 1, 100L), max)
  @debug.assert_eq(saturating_add_positive(5L, 0L), 5L)
}

///|
test "non negative delta never returns a negative delay" {
  @debug.assert_eq(non_negative_delta(10L, 3L), 7L)
  @debug.assert_eq(non_negative_delta(10L, 10L), 0L)
  @debug.assert_eq(non_negative_delta(3L, 10L), 0L)
  @debug.assert_eq(non_negative_delta(max_int64(), -1L), max_int64())
}

///|
test "elapsed refill helpers handle signed Int64 boundaries" {
  let min = -9_223_372_036_854_775_807L - 1L
  let near_max = 9_223_372_036_854_775_700L
  let completed = completed_refill_since(min, near_max, 100L)
  @debug.assert_eq(completed.refilled_at, 9_223_372_036_854_775_692L)
  @debug.assert_eq(elapsed_remainder(min, max_int64(), 100L), 15L)
  @debug.assert_eq(positive_mod(-1L, 100L), 99L)
  @debug.assert_eq(completed_periods_since(10L, 10L, 100L), 0L)
  @debug.assert_eq(completed_periods_since(min, max_int64(), 1L), max_int64())
  @debug.assert_eq(saturating_add_non_negative(max_int64(), 1L), max_int64())
}
