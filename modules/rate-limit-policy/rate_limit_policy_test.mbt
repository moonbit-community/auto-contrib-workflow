///|
fn full_bucket() -> @rate_limit_policy.TokenBucket {
  try! @rate_limit_policy.new_token_bucket(3, 1, 100L, 0L)
}

///|
test "allow consumes burst tokens and reports next available time" {
  let first = @rate_limit_policy.allow(full_bucket(), 0L)
  @debug.assert_eq(first.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(first.bucket), 2)
  let second = @rate_limit_policy.allow(first.bucket, 0L, cost=2)
  @debug.assert_eq(second.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(second.bucket), 0)
  let denied = @rate_limit_policy.allow(second.bucket, 0L)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.reason, Some(InsufficientTokens(1)))
  @debug.assert_eq(denied.next_available_ms, Some(100L))
  @debug.assert_eq(denied.delay_ms, 100L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(denied.bucket), 0)
}

///|
test "refill preserves partial periods until enough time passes" {
  let empty = try! @rate_limit_policy.new_token_bucket_with_tokens(
    5, 2, 100L, 0L, 0,
  )
  let partial = @rate_limit_policy.refill(empty, 99L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(partial), 0)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(partial), 0L)
  let one_period = @rate_limit_policy.refill(partial, 100L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(one_period), 2)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(one_period), 100L)
  let two_more = @rate_limit_policy.refill(one_period, 260L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(two_more), 4)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(two_more), 200L)
}

///|
test "large timestamp jump caps tokens at burst capacity" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    4, 1, 100L, 0L, 0,
  )
  let filled = @rate_limit_policy.refill(bucket, 10_000L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(filled), 4)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(filled), 10_000L)
}

///|
test "full bucket keeps capacity and preserves partial refill period" {
  let bucket = full_bucket()
  @debug.assert_eq(@rate_limit_policy.capacity(bucket), 3)
  @debug.assert_eq(@rate_limit_policy.refill_tokens(bucket), 1)
  @debug.assert_eq(@rate_limit_policy.refill_period_ms(bucket), 100L)
  let still_full = @rate_limit_policy.refill(bucket, 250L)
  @debug.assert_eq(@rate_limit_policy.available_tokens(still_full), 3)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(still_full), 200L)
  let consumed = @rate_limit_policy.allow(still_full, 260L, cost=3)
  @debug.assert_eq(consumed.allowed, true)
  let denied = @rate_limit_policy.check(consumed.bucket, 260L)
  @debug.assert_eq(denied.next_available_ms, Some(300L))
  @debug.assert_eq(denied.delay_ms, 40L)
}

///|
test "check reports availability without consuming tokens" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100L, 0L, 1,
  )
  let checked = @rate_limit_policy.check(bucket, 0L)
  @debug.assert_eq(checked.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(checked.bucket), 1)
  let allowed = @rate_limit_policy.allow(checked.bucket, 0L)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(allowed.bucket), 0)
}

///|
test "variable cost uses refill rate to compute delay" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    10, 3, 100L, 0L, 1,
  )
  let decision = @rate_limit_policy.check(bucket, 50L, cost=7)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.reason, Some(InsufficientTokens(6)))
  @debug.assert_eq(decision.next_available_ms, Some(200L))
  @debug.assert_eq(decision.delay_ms, 150L)
}

///|
test "invalid request costs are structured denials" {
  let zero = @rate_limit_policy.check(full_bucket(), 0L, cost=0)
  @debug.assert_eq(zero.allowed, false)
  @debug.assert_eq(zero.reason, Some(InvalidCost(0)))
  @debug.assert_eq(zero.next_available_ms, None)
  let too_large = @rate_limit_policy.check(full_bucket(), 0L, cost=4)
  @debug.assert_eq(too_large.allowed, false)
  @debug.assert_eq(too_large.reason, Some(CostExceedsCapacity(4, 3)))
  @debug.assert_eq(too_large.next_available_ms, None)
}

///|
test "constructors validate bucket configuration" {
  let capacity : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(0, 1, 100L, 0L)
  @debug.assert_eq(capacity, Err(NonPositiveCapacity(0)))
  let refill_tokens : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(1, 0, 100L, 0L)
  @debug.assert_eq(refill_tokens, Err(NonPositiveRefillTokens(0)))
  let period : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(1, 1, 0L, 0L)
  @debug.assert_eq(period, Err(NonPositiveRefillPeriod(0L)))
  let initial : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket_with_tokens(2, 1, 100L, 0L, 3)
  @debug.assert_eq(initial, Err(InitialTokensOutOfRange(3, 2)))
}

///|
test "timestamps before the last refill do not refill" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100L, 500L, 0,
  )
  let decision = @rate_limit_policy.check(bucket, 400L)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(600L))
  @debug.assert_eq(decision.delay_ms, 200L)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(decision.bucket), 500L)
}

///|
test "epoch scale millisecond timestamps remain ordered" {
  let epoch_ms = 1_761_715_200_000L
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100L, epoch_ms, 0,
  )
  let decision = @rate_limit_policy.check(bucket, epoch_ms + 50L, cost=2)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(epoch_ms + 200L))
  @debug.assert_eq(decision.delay_ms, 150L)
}

///|
test "long running monotonic timestamps can exceed Int range" {
  let day_30_ms = 2_592_000_000L
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100L, day_30_ms, 0,
  )
  let allowed = @rate_limit_policy.allow(bucket, day_30_ms + 250L, cost=2)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(allowed.bucket), 0)
  @debug.assert_eq(
    @rate_limit_policy.last_refill_ms(allowed.bucket),
    day_30_ms + 200L,
  )
  let denied = @rate_limit_policy.check(allowed.bucket, day_30_ms + 260L)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.next_available_ms, Some(day_30_ms + 300L))
  @debug.assert_eq(denied.delay_ms, 40L)
}

///|
test "large token counts compute delay without ceil overflow" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    2_147_483_647, 2, 1L, 0L, 0,
  )
  let decision = @rate_limit_policy.check(bucket, 0L, cost=2_147_483_647)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(1_073_741_824L))
  @debug.assert_eq(decision.delay_ms, 1_073_741_824L)
}

///|
test "available tokens stay within bucket bounds across a timeline" {
  let mut bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    5, 2, 100L, 0L, 0,
  )
  let timeline : Array[Int64] = [0L, 40L, 100L, 160L, 200L, 410L, 800L, 801L]
  for now in timeline {
    let checked = @rate_limit_policy.check(bucket, now, cost=3)
    let tokens = @rate_limit_policy.available_tokens(checked.bucket)
    assert_true(tokens >= 0)
    assert_true(tokens <= @rate_limit_policy.capacity(checked.bucket))
    let allowed = @rate_limit_policy.allow(checked.bucket, now, cost=1)
    let next_tokens = @rate_limit_policy.available_tokens(allowed.bucket)
    assert_true(next_tokens >= 0)
    assert_true(next_tokens <= @rate_limit_policy.capacity(allowed.bucket))
    bucket = allowed.bucket
  }
}
