///|
/// A deterministic token bucket.
///
/// The bucket never reads the global clock and never sleeps. Callers provide
/// timestamps in milliseconds to every state transition.
pub struct TokenBucket {
  priv capacity : Int
  priv refill_tokens : Int
  priv refill_period_ms : Int64
  priv tokens : Int
  priv last_refill_ms : Int64
} derive(Eq, Debug)

///|
/// Invalid token bucket configuration.
pub(all) suberror ConfigError {
  /// The bucket capacity must be greater than zero.
  NonPositiveCapacity(Int)
  /// Each refill step must add at least one token.
  NonPositiveRefillTokens(Int)
  /// The refill period must be greater than zero milliseconds.
  NonPositiveRefillPeriod(Int64)
  /// The initial token count must be within `[0, capacity]`.
  InitialTokensOutOfRange(Int, Int)
} derive(Eq, Debug)

///|
/// Why a request cannot be admitted immediately.
pub(all) enum DenialReason {
  /// The requested cost must be greater than zero.
  InvalidCost(Int)
  /// The requested cost is larger than the bucket capacity.
  CostExceedsCapacity(Int, Int)
  /// The request needs the given number of additional tokens.
  InsufficientTokens(Int)
} derive(Eq, Debug)

///|
/// The result of checking or applying a token bucket policy.
pub(all) struct Decision {
  /// True when the request can run immediately at the supplied timestamp.
  allowed : Bool
  /// The resulting bucket state. `allow` consumes tokens on success; `check`
  /// only refills the bucket.
  bucket : TokenBucket
  /// A structured denial reason when `allowed` is false.
  reason : DenialReason?
  /// The timestamp when this request can next run, if it can ever fit.
  next_available_ms : Int64?
  /// Milliseconds until `next_available_ms`, or zero for immediate/impossible
  /// decisions.
  delay_ms : Int64
} derive(Eq, Debug)

///|
/// Creates a full token bucket at `now_ms`.
pub fn TokenBucket::new(
  capacity : Int,
  refill_tokens : Int,
  refill_period_ms : Int64,
  now_ms : Int64,
) -> TokenBucket raise ConfigError {
  TokenBucket::with_tokens(
    capacity, refill_tokens, refill_period_ms, now_ms, capacity,
  )
}

///|
/// Creates a token bucket with an explicit initial token count.
pub fn TokenBucket::with_tokens(
  capacity : Int,
  refill_tokens : Int,
  refill_period_ms : Int64,
  now_ms : Int64,
  initial_tokens : Int,
) -> TokenBucket raise ConfigError {
  validate_config(capacity, refill_tokens, refill_period_ms)
  if initial_tokens < 0 || initial_tokens > capacity {
    raise InitialTokensOutOfRange(initial_tokens, capacity)
  }
  {
    capacity,
    refill_tokens,
    refill_period_ms,
    tokens: initial_tokens,
    last_refill_ms: now_ms,
  }
}

///|
/// Returns the maximum number of tokens this bucket can hold.
pub fn TokenBucket::capacity(self : TokenBucket) -> Int {
  self.capacity
}

///|
/// Returns the number of tokens added per completed refill period.
pub fn TokenBucket::refill_tokens(self : TokenBucket) -> Int {
  self.refill_tokens
}

///|
/// Returns the refill period in milliseconds.
pub fn TokenBucket::refill_period_ms(self : TokenBucket) -> Int64 {
  self.refill_period_ms
}

///|
/// Returns the currently stored tokens without applying a refill.
pub fn TokenBucket::available_tokens(self : TokenBucket) -> Int {
  self.tokens
}

///|
/// Returns the timestamp used as the base for future refill periods.
pub fn TokenBucket::last_refill_ms(self : TokenBucket) -> Int64 {
  self.last_refill_ms
}

///|
/// Applies all completed refill periods up to `now_ms`.
///
/// If `now_ms` is earlier than the bucket's last refill timestamp, no refill is
/// applied and the original state is returned.
pub fn TokenBucket::refill(self : TokenBucket, now_ms : Int64) -> TokenBucket {
  if now_ms <= self.last_refill_ms {
    return self
  }
  let completed = completed_refill_since(
    self.last_refill_ms,
    now_ms,
    self.refill_period_ms,
  )
  if completed.periods <= 0L {
    return self
  }
  let missing = self.capacity - self.tokens
  if missing <= 0 {
    return bucket_with(self, self.capacity, completed.refilled_at)
  }
  let periods_to_full = ceil_div(missing, self.refill_tokens)
  if completed.periods >= periods_to_full.to_int64() {
    bucket_with(self, self.capacity, completed.refilled_at)
  } else {
    bucket_with(
      self,
      self.tokens + (completed.periods * self.refill_tokens.to_int64()).to_int(),
      completed.refilled_at,
    )
  }
}

///|
/// Checks whether a request of `cost` tokens can run at `now_ms`.
///
/// This function refills the returned bucket but does not consume tokens.
pub fn TokenBucket::check(
  self : TokenBucket,
  now_ms : Int64,
  cost? : Int = 1,
) -> Decision {
  decide(self, now_ms, cost, consume=false)
}

///|
/// Attempts to consume `cost` tokens at `now_ms`.
///
/// Denied requests do not consume tokens. The returned decision includes a
/// deterministic next-available timestamp when the request can eventually fit.
pub fn TokenBucket::allow(
  self : TokenBucket,
  now_ms : Int64,
  cost? : Int = 1,
) -> Decision {
  decide(self, now_ms, cost, consume=true)
}

///|
fn validate_config(
  capacity : Int,
  refill_tokens : Int,
  refill_period_ms : Int64,
) -> Unit raise ConfigError {
  if capacity <= 0 {
    raise NonPositiveCapacity(capacity)
  }
  if refill_tokens <= 0 {
    raise NonPositiveRefillTokens(refill_tokens)
  }
  if refill_period_ms <= 0 {
    raise NonPositiveRefillPeriod(refill_period_ms)
  }
}

///|
fn decide(
  bucket : TokenBucket,
  now_ms : Int64,
  cost : Int,
  consume~ : Bool,
) -> Decision {
  let current = bucket.refill(now_ms)
  if cost <= 0 {
    decision(false, current, Some(InvalidCost(cost)), None, 0)
  } else if cost > current.capacity {
    decision(
      false,
      current,
      Some(CostExceedsCapacity(cost, current.capacity)),
      None,
      0,
    )
  } else if current.tokens >= cost {
    let next_bucket = if consume {
      bucket_with(current, current.tokens - cost, current.last_refill_ms)
    } else {
      current
    }
    decision(true, next_bucket, None, Some(now_ms), 0)
  } else {
    let missing = cost - current.tokens
    let ready_at = saturating_ready_at(
      current.last_refill_ms,
      ceil_div(missing, current.refill_tokens),
      current.refill_period_ms,
    )
    decision(
      false,
      current,
      Some(InsufficientTokens(missing)),
      Some(ready_at),
      non_negative_delta(ready_at, now_ms),
    )
  }
}

///|
fn decision(
  allowed : Bool,
  bucket : TokenBucket,
  reason : DenialReason?,
  next_available_ms : Int64?,
  delay_ms : Int64,
) -> Decision {
  { allowed, bucket, reason, next_available_ms, delay_ms }
}

///|
fn bucket_with(
  bucket : TokenBucket,
  tokens : Int,
  last_refill_ms : Int64,
) -> TokenBucket {
  {
    capacity: bucket.capacity,
    refill_tokens: bucket.refill_tokens,
    refill_period_ms: bucket.refill_period_ms,
    tokens,
    last_refill_ms,
  }
}

///|
fn ceil_div(value : Int, divisor : Int) -> Int {
  if value <= 0 {
    0
  } else {
    (value - 1) / divisor + 1
  }
}

///|
priv struct CompletedRefill {
  periods : Int64
  refilled_at : Int64
}

///|
fn completed_refill_since(
  last_refill_ms : Int64,
  now_ms : Int64,
  refill_period_ms : Int64,
) -> CompletedRefill {
  let periods = completed_periods_since(
    last_refill_ms, now_ms, refill_period_ms,
  )
  let remainder = elapsed_remainder(last_refill_ms, now_ms, refill_period_ms)
  { periods, refilled_at: now_ms - remainder }
}

///|
fn completed_periods_since(
  last_refill_ms : Int64,
  now_ms : Int64,
  refill_period_ms : Int64,
) -> Int64 {
  if now_ms <= last_refill_ms {
    0L
  } else if last_refill_ms >= 0L || now_ms < 0L {
    (now_ms - last_refill_ms) / refill_period_ms
  } else {
    completed_periods_across_zero(last_refill_ms, now_ms, refill_period_ms)
  }
}

///|
fn completed_periods_across_zero(
  last_refill_ms : Int64,
  now_ms : Int64,
  refill_period_ms : Int64,
) -> Int64 {
  let left = -(last_refill_ms + 1L)
  let right = now_ms
  let left_periods = left / refill_period_ms
  let right_periods = right / refill_period_ms
  let left_remainder = left % refill_period_ms
  let right_remainder = right % refill_period_ms
  let carry = if right_remainder >= refill_period_ms - 1L - left_remainder {
    1L
  } else {
    0L
  }
  saturating_add_non_negative(
    saturating_add_non_negative(left_periods, right_periods),
    carry,
  )
}

///|
fn elapsed_remainder(
  last_refill_ms : Int64,
  now_ms : Int64,
  refill_period_ms : Int64,
) -> Int64 {
  let now_remainder = positive_mod(now_ms, refill_period_ms)
  let last_remainder = positive_mod(last_refill_ms, refill_period_ms)
  if now_remainder >= last_remainder {
    now_remainder - last_remainder
  } else {
    refill_period_ms - (last_remainder - now_remainder)
  }
}

///|
fn positive_mod(value : Int64, divisor : Int64) -> Int64 {
  let remainder = value % divisor
  if remainder < 0L {
    remainder + divisor
  } else {
    remainder
  }
}

///|
fn saturating_ready_at(
  last_refill_ms : Int64,
  periods_needed : Int,
  refill_period_ms : Int64,
) -> Int64 {
  let max = max_int64()
  let periods = periods_needed.to_int64()
  if periods <= 0L {
    last_refill_ms
  } else if refill_period_ms > max / periods {
    max
  } else {
    saturating_add_positive(last_refill_ms, periods * refill_period_ms)
  }
}

///|
fn saturating_add_non_negative(left : Int64, right : Int64) -> Int64 {
  let max = max_int64()
  if right <= 0L {
    left
  } else if left > max - right {
    max
  } else {
    left + right
  }
}

///|
fn saturating_add_positive(base : Int64, offset : Int64) -> Int64 {
  let max = max_int64()
  if offset <= 0L {
    base
  } else if base > max - offset {
    max
  } else {
    base + offset
  }
}

///|
fn non_negative_delta(future : Int64, now : Int64) -> Int64 {
  if future > now {
    let max = max_int64()
    if now < 0L && future > max + now {
      max
    } else {
      future - now
    }
  } else {
    0
  }
}

///|
fn max_int64() -> Int64 {
  9_223_372_036_854_775_807L
}
