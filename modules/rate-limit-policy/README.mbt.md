# moonbit-community/rate_limit_policy

Deterministic rate limiting policies for callers that own their own clocks,
sleeping, and runtime integration.

```mbt check
///|
test "token bucket example" {
  let bucket = try! @rate_limit_policy.new_token_bucket(3, 1, 1000, 0)
  let first = @rate_limit_policy.allow(bucket, 0)
  let second = @rate_limit_policy.allow(first.bucket, 0, cost=2)
  let third = @rate_limit_policy.allow(second.bucket, 0)
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
    10, 3, 100, 0, 1,
  )
  let decision = @rate_limit_policy.check(bucket, 50, cost=7)
  @debug.debug_inspect(
    (decision.allowed, decision.delay_ms, decision.next_available_ms),
    content=(
      #|(false, 150, Some(200))
    ),
  )
}
```
