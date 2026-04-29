# moonbit-community/rate_limit_policy

Deterministic rate limiting policies for callers that own their own clocks,
sleeping, and runtime integration.

## Token buckets

A token bucket holds up to `capacity` tokens. Each completed
`refill_period_ms` adds `refill_tokens`, capped at `capacity`. The caller passes
the current millisecond timestamp to every operation, so tests can use fixed
timelines and production code can use wall-clock or monotonic time from its own
runtime.

Use `bucket.allow` when the request should consume tokens immediately on
success. Use `bucket.check` when the caller only wants to inspect the decision
and delay without mutating the token count.

```mbt check
///|
test "token bucket example" {
  let bucket = try! @rate_limit_policy.TokenBucket::new(3, 1, 1000L, 0L)
  let first = bucket.allow(0L)
  let second = first.bucket.allow(0L, cost=2)
  let third = second.bucket.allow(0L)
  @debug.debug_inspect(
    (first.allowed, second.allowed, third.allowed, third.next_available_ms),
    content=(
      #|(true, true, false, Some(1000))
    ),
  )
}
```

Store the returned `decision.bucket` after every `allow` call. Denied decisions
do not consume tokens, but they do include the refilled bucket state that should
be retained for the next attempt.

```mbt check
///|
test "reservation delay example" {
  let bucket = try! @rate_limit_policy.TokenBucket::with_tokens(
    10, 3, 100L, 0L, 1,
  )
  let decision = bucket.check(50L, cost=7)
  @debug.debug_inspect(
    (decision.allowed, decision.delay_ms, decision.next_available_ms),
    content=(
      #|(false, 150, Some(200))
    ),
  )
}
```

## Runtime integration

This package intentionally does not depend on a clock, sleep function, HTTP
framework, or async runtime. A runtime adapter should:

- read the runtime's current time as milliseconds,
- call `bucket.allow` to reserve capacity before starting work,
- sleep for `decision.delay_ms` when the request is denied,
- persist the returned bucket state in the caller's queue, map, or protected
  shared state.

For a project that already uses `moonbitlang/async`, add `moonbitlang/async` to
the consuming project and use `@async.now()` with `@async.sleep(...)`. `sleep`
accepts `Int` milliseconds, so clamp the `Int64` delay before converting it:

```mbt nocheck
import {
  "moonbitlang/async" @async
  "moonbit-community/rate_limit_policy" @rate_limit_policy
}

fn sleep_delay_ms(delay_ms : Int64) -> Int {
  if delay_ms <= 0L {
    0
  } else if delay_ms > 2_147_483_647L {
    2_147_483_647
  } else {
    delay_ms.to_int()
  }
}

async fn wait_for_slot(
  bucket : @rate_limit_policy.TokenBucket
) -> @rate_limit_policy.TokenBucket {
  let decision = bucket.allow(@async.now())
  if decision.allowed {
    decision.bucket
  } else {
    @async.sleep(sleep_delay_ms(decision.delay_ms))
    wait_for_slot(decision.bucket)
  }
}
```

Keep synchronization outside this package. For example, async applications that
share one bucket across tasks should protect the stored bucket with their own
queue, actor, mutex, or semaphore and update it with each returned state.
