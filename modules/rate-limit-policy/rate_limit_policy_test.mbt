///|
fn full_bucket() -> @rate_limit_policy.TokenBucket {
  try! @rate_limit_policy.TokenBucket::new(3, 1, 100L, 0L)
}

///|
test "allow consumes burst tokens and reports next available time" {
  let first = full_bucket().allow(0L)
  @debug.assert_eq(first.allowed, true)
  @debug.assert_eq(first.bucket.available_tokens(), 2)
  let second = first.bucket.allow(0L, cost=2)
  @debug.assert_eq(second.allowed, true)
  @debug.assert_eq(second.bucket.available_tokens(), 0)
  let denied = second.bucket.allow(0L)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.reason, Some(InsufficientTokens(1)))
  @debug.assert_eq(denied.next_available_ms, Some(100L))
  @debug.assert_eq(denied.delay_ms, 100L)
  @debug.assert_eq(denied.bucket.available_tokens(), 0)
}

///|
test "refill preserves partial periods until enough time passes" {
  let empty = try! @rate_limit_policy.TokenBucket::with_tokens(
    5, 2, 100L, 0L, 0,
  )
  let partial = empty.refill(99L)
  @debug.assert_eq(partial.available_tokens(), 0)
  @debug.assert_eq(partial.last_refill_ms(), 0L)
  let one_period = partial.refill(100L)
  @debug.assert_eq(one_period.available_tokens(), 2)
  @debug.assert_eq(one_period.last_refill_ms(), 100L)
  let two_more = one_period.refill(260L)
  @debug.assert_eq(two_more.available_tokens(), 4)
  @debug.assert_eq(two_more.last_refill_ms(), 200L)
}

///|
test "large timestamp jump caps tokens at burst capacity" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    4, 1, 100L, 0L, 0,
  )
  let filled = bucket.refill(10_000L)
  @debug.assert_eq(filled.available_tokens(), 4)
  @debug.assert_eq(filled.last_refill_ms(), 10_000L)
}

///|
test "full bucket keeps capacity and preserves partial refill period" {
  let bucket = full_bucket()
  @debug.assert_eq(bucket.capacity(), 3)
  @debug.assert_eq(bucket.refill_tokens(), 1)
  @debug.assert_eq(bucket.refill_period_ms(), 100L)
  let still_full = bucket.refill(250L)
  @debug.assert_eq(still_full.available_tokens(), 3)
  @debug.assert_eq(still_full.last_refill_ms(), 200L)
  let consumed = still_full.allow(260L, cost=3)
  @debug.assert_eq(consumed.allowed, true)
  let denied = consumed.bucket.check(260L)
  @debug.assert_eq(denied.next_available_ms, Some(300L))
  @debug.assert_eq(denied.delay_ms, 40L)
}

///|
test "check reports availability without consuming tokens" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    3, 1, 100L, 0L, 1,
  )
  let checked = bucket.check(0L)
  @debug.assert_eq(checked.allowed, true)
  @debug.assert_eq(checked.bucket.available_tokens(), 1)
  let allowed = checked.bucket.allow(0L)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(allowed.bucket.available_tokens(), 0)
}

///|
test "variable cost uses refill rate to compute delay" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    10, 3, 100L, 0L, 1,
  )
  let decision = bucket.check(50L, cost=7)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.reason, Some(InsufficientTokens(6)))
  @debug.assert_eq(decision.next_available_ms, Some(200L))
  @debug.assert_eq(decision.delay_ms, 150L)
}

///|
test "invalid request costs are structured denials" {
  let zero = full_bucket().check(0L, cost=0)
  @debug.assert_eq(zero.allowed, false)
  @debug.assert_eq(zero.reason, Some(InvalidCost(0)))
  @debug.assert_eq(zero.next_available_ms, None)
  let too_large = full_bucket().check(0L, cost=4)
  @debug.assert_eq(too_large.allowed, false)
  @debug.assert_eq(too_large.reason, Some(CostExceedsCapacity(4, 3)))
  @debug.assert_eq(too_large.next_available_ms, None)
}

///|
test "constructors validate bucket configuration" {
  let capacity : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.TokenBucket::new(0, 1, 100L, 0L)
  @debug.assert_eq(capacity, Err(NonPositiveCapacity(0)))
  let refill_tokens : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.TokenBucket::new(1, 0, 100L, 0L)
  @debug.assert_eq(refill_tokens, Err(NonPositiveRefillTokens(0)))
  let period : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.TokenBucket::new(1, 1, 0L, 0L)
  @debug.assert_eq(period, Err(NonPositiveRefillPeriod(0L)))
  let initial : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.TokenBucket::with_tokens(2, 1, 100L, 0L, 3)
  @debug.assert_eq(initial, Err(InitialTokensOutOfRange(3, 2)))
}

///|
test "timestamps before the last refill do not refill" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    3, 1, 100L, 500L, 0,
  )
  let decision = bucket.check(400L)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(600L))
  @debug.assert_eq(decision.delay_ms, 200L)
  @debug.assert_eq(decision.bucket.last_refill_ms(), 500L)
}

///|
test "epoch scale millisecond timestamps remain ordered" {
  let epoch_ms = 1_761_715_200_000L
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    3, 1, 100L, epoch_ms, 0,
  )
  let decision = bucket.check(epoch_ms + 50L, cost=2)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(epoch_ms + 200L))
  @debug.assert_eq(decision.delay_ms, 150L)
}

///|
test "long running monotonic timestamps can exceed Int range" {
  let day_30_ms = 2_592_000_000L
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    3, 1, 100L, day_30_ms, 0,
  )
  let allowed = bucket.allow(day_30_ms + 250L, cost=2)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(allowed.bucket.available_tokens(), 0)
  @debug.assert_eq(allowed.bucket.last_refill_ms(), day_30_ms + 200L)
  let denied = allowed.bucket.check(day_30_ms + 260L)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.next_available_ms, Some(day_30_ms + 300L))
  @debug.assert_eq(denied.delay_ms, 40L)
}

///|
test "large token counts compute delay without ceil overflow" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    2_147_483_647, 2, 1L, 0L, 0,
  )
  let decision = bucket.check(0L, cost=2_147_483_647)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(1_073_741_824L))
  @debug.assert_eq(decision.delay_ms, 1_073_741_824L)
}

///|
test "unrepresentable wait multiplication saturates next available time" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    2, 1, 9_223_372_036_854_775_000L, 0L, 0,
  )
  let decision = bucket.check(0L, cost=2)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.reason, Some(InsufficientTokens(2)))
  @debug.assert_eq(decision.next_available_ms, Some(9_223_372_036_854_775_807L))
  @debug.assert_eq(decision.delay_ms, 9_223_372_036_854_775_807L)
}

///|
test "unrepresentable ready timestamp addition saturates delay" {
  let near_max_ms = 9_223_372_036_854_775_757L
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    1, 1, 100L, near_max_ms, 0,
  )
  let decision = bucket.check(near_max_ms)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.reason, Some(InsufficientTokens(1)))
  @debug.assert_eq(decision.next_available_ms, Some(9_223_372_036_854_775_807L))
  @debug.assert_eq(decision.delay_ms, 50L)
}

///|
test "elapsed time across Int64 signs refills without overflow" {
  let min_ms = -9_223_372_036_854_775_807L - 1L
  let now_ms = 9_223_372_036_854_775_700L
  let refilled_at = 9_223_372_036_854_775_692L
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    3, 1, 100L, min_ms, 0,
  )
  let filled = bucket.refill(now_ms)
  @debug.assert_eq(filled.available_tokens(), 3)
  @debug.assert_eq(filled.last_refill_ms(), refilled_at)
  let allowed = bucket.allow(now_ms, cost=3)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(allowed.bucket.available_tokens(), 0)
  @debug.assert_eq(allowed.bucket.last_refill_ms(), refilled_at)
  let denied = allowed.bucket.check(now_ms)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.next_available_ms, Some(refilled_at + 100L))
  @debug.assert_eq(denied.delay_ms, 92L)
}

///|
test "available tokens stay within bucket bounds across a timeline" {
  let mut bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    5, 2, 100L, 0L, 0,
  )
  let timeline : Array[Int64] = [0L, 40L, 100L, 160L, 200L, 410L, 800L, 801L]
  for now in timeline {
    let checked = bucket.check(now, cost=3)
    let tokens = checked.bucket.available_tokens()
    assert_true(tokens >= 0)
    assert_true(tokens <= checked.bucket.capacity())
    let allowed = checked.bucket.allow(now, cost=1)
    let next_tokens = allowed.bucket.available_tokens()
    assert_true(next_tokens >= 0)
    assert_true(next_tokens <= allowed.bucket.capacity())
    bucket = allowed.bucket
  }
}
