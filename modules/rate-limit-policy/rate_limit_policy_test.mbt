///|
fn full_bucket() -> @rate_limit_policy.TokenBucket {
  try! @rate_limit_policy.new_token_bucket(3, 1, 100, 0)
}

///|
test "allow consumes burst tokens and reports next available time" {
  let first = @rate_limit_policy.allow(full_bucket(), 0)
  @debug.assert_eq(first.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(first.bucket), 2)
  let second = @rate_limit_policy.allow(first.bucket, 0, cost=2)
  @debug.assert_eq(second.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(second.bucket), 0)
  let denied = @rate_limit_policy.allow(second.bucket, 0)
  @debug.assert_eq(denied.allowed, false)
  @debug.assert_eq(denied.reason, Some(InsufficientTokens(1)))
  @debug.assert_eq(denied.next_available_ms, Some(100))
  @debug.assert_eq(denied.delay_ms, 100)
  @debug.assert_eq(@rate_limit_policy.available_tokens(denied.bucket), 0)
}

///|
test "refill preserves partial periods until enough time passes" {
  let empty = try! @rate_limit_policy.new_token_bucket_with_tokens(
    5, 2, 100, 0, 0,
  )
  let partial = @rate_limit_policy.refill(empty, 99)
  @debug.assert_eq(@rate_limit_policy.available_tokens(partial), 0)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(partial), 0)
  let one_period = @rate_limit_policy.refill(partial, 100)
  @debug.assert_eq(@rate_limit_policy.available_tokens(one_period), 2)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(one_period), 100)
  let two_more = @rate_limit_policy.refill(one_period, 260)
  @debug.assert_eq(@rate_limit_policy.available_tokens(two_more), 4)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(two_more), 200)
}

///|
test "large timestamp jump caps tokens at burst capacity" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    4, 1, 100, 0, 0,
  )
  let filled = @rate_limit_policy.refill(bucket, 10_000)
  @debug.assert_eq(@rate_limit_policy.available_tokens(filled), 4)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(filled), 10_000)
}

///|
test "full bucket keeps capacity and moves refill base forward" {
  let bucket = full_bucket()
  @debug.assert_eq(@rate_limit_policy.capacity(bucket), 3)
  @debug.assert_eq(@rate_limit_policy.refill_tokens(bucket), 1)
  @debug.assert_eq(@rate_limit_policy.refill_period_ms(bucket), 100)
  let still_full = @rate_limit_policy.refill(bucket, 250)
  @debug.assert_eq(@rate_limit_policy.available_tokens(still_full), 3)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(still_full), 250)
}

///|
test "check reports availability without consuming tokens" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100, 0, 1,
  )
  let checked = @rate_limit_policy.check(bucket, 0)
  @debug.assert_eq(checked.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(checked.bucket), 1)
  let allowed = @rate_limit_policy.allow(checked.bucket, 0)
  @debug.assert_eq(allowed.allowed, true)
  @debug.assert_eq(@rate_limit_policy.available_tokens(allowed.bucket), 0)
}

///|
test "variable cost uses refill rate to compute delay" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    10, 3, 100, 0, 1,
  )
  let decision = @rate_limit_policy.check(bucket, 50, cost=7)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.reason, Some(InsufficientTokens(6)))
  @debug.assert_eq(decision.next_available_ms, Some(200))
  @debug.assert_eq(decision.delay_ms, 150)
}

///|
test "invalid request costs are structured denials" {
  let zero = @rate_limit_policy.check(full_bucket(), 0, cost=0)
  @debug.assert_eq(zero.allowed, false)
  @debug.assert_eq(zero.reason, Some(InvalidCost(0)))
  @debug.assert_eq(zero.next_available_ms, None)
  let too_large = @rate_limit_policy.check(full_bucket(), 0, cost=4)
  @debug.assert_eq(too_large.allowed, false)
  @debug.assert_eq(too_large.reason, Some(CostExceedsCapacity(4, 3)))
  @debug.assert_eq(too_large.next_available_ms, None)
}

///|
test "constructors validate bucket configuration" {
  let capacity : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(0, 1, 100, 0)
  @debug.assert_eq(capacity, Err(NonPositiveCapacity(0)))
  let refill_tokens : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(1, 0, 100, 0)
  @debug.assert_eq(refill_tokens, Err(NonPositiveRefillTokens(0)))
  let period : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket(1, 1, 0, 0)
  @debug.assert_eq(period, Err(NonPositiveRefillPeriod(0)))
  let initial : Result[
    @rate_limit_policy.TokenBucket,
    @rate_limit_policy.ConfigError,
  ] = try? @rate_limit_policy.new_token_bucket_with_tokens(2, 1, 100, 0, 3)
  @debug.assert_eq(initial, Err(InitialTokensOutOfRange(3, 2)))
}

///|
test "timestamps before the last refill do not refill" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    3, 1, 100, 500, 0,
  )
  let decision = @rate_limit_policy.check(bucket, 400)
  @debug.assert_eq(decision.allowed, false)
  @debug.assert_eq(decision.next_available_ms, Some(600))
  @debug.assert_eq(decision.delay_ms, 200)
  @debug.assert_eq(@rate_limit_policy.last_refill_ms(decision.bucket), 500)
}

///|
test "available tokens stay within bucket bounds across a timeline" {
  let mut bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    5, 2, 100, 0, 0,
  )
  for now in [0, 40, 100, 160, 200, 410, 800, 801] {
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
