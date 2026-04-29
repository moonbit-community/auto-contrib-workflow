# moonbit-community/rate_limit_policy

Deterministic rate limiting policies for callers that own their own clocks,
sleeping, and runtime integration.

```mbt check
///|
test "token bucket example" {
  let bucket = try! @rate_limit_policy.new_token_bucket(3, 1, 1000L, 0L)
  let first = @rate_limit_policy.allow(bucket, 0L)
  let second = @rate_limit_policy.allow(first.bucket, 0L, cost=2)
  let third = @rate_limit_policy.allow(second.bucket, 0L)
  @debug.debug_inspect(
    (first.allowed, second.allowed, third.allowed, third.next_available_ms),
    content=(
      #|(true, true, false, Some(1000))
    ),
  )
}
```

```mbt check
///|
test "reservation delay example" {
  let bucket = try! @rate_limit_policy.new_token_bucket_with_tokens(
    10, 3, 100L, 0L, 1,
  )
  let decision = @rate_limit_policy.check(bucket, 50L, cost=7)
  @debug.debug_inspect(
    (decision.allowed, decision.delay_ms, decision.next_available_ms),
    content=(
      #|(false, 150, Some(200))
    ),
  )
}
```
