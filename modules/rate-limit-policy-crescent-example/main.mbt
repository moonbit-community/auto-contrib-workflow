///|
fn clamp_delay_ms(delay_ms : Int64) -> Int {
  if delay_ms <= 0L {
    0
  } else if delay_ms > 2_147_483_647L {
    2_147_483_647
  } else {
    delay_ms.to_int()
  }
}

///|
fn retry_after_seconds(delay_ms : Int64) -> String {
  if delay_ms <= 0L {
    "0"
  } else {
    ((delay_ms - 1L) / 1000L + 1L).to_string()
  }
}

///|
fn token_bucket_middleware(
  bucket : Ref[@rate_limit_policy.TokenBucket],
) -> @crescent.Middleware {
  (_, next) => {
    let decision = bucket.val.allow(@async.now())
    bucket.val = decision.bucket
    if decision.allowed {
      next()
    } else {
      @crescent.HttpResponse::error(
        @crescent.StatusCode::from_int(429),
        "rate limit exceeded",
      ).header("Retry-After", retry_after_seconds(decision.delay_ms))
    }
  }
}

///|
fn build_app() -> @crescent.App {
  let app = @crescent.App()
  let bucket = Ref::Ref(
    try! @rate_limit_policy.TokenBucket::new(1, 1, 60_000L, @async.now()),
  )
  app.use_middleware(token_bucket_middleware(bucket), base_path="/api")
  app.get("/api/search", _ => "search accepted")
  app
}

///|
async fn wait_for_slot(
  bucket : @rate_limit_policy.TokenBucket,
) -> @rate_limit_policy.TokenBucket {
  let decision = bucket.allow(@async.now())
  if decision.allowed {
    decision.bucket
  } else {
    @async.sleep(clamp_delay_ms(decision.delay_ms))
    wait_for_slot(decision.bucket)
  }
}

///|
async test "crescent middleware returns retry-after on rate limit" {
  let app = build_app()
  let first = app.dispatch("GET", "/api/search", {}, b"")
  assert_eq(first.0, @crescent.StatusCode::from_int(200))
  let second = app.dispatch("GET", "/api/search", {}, b"")
  assert_eq(second.0, @crescent.StatusCode::from_int(429))
  guard second.1.get("Retry-After") is Some(retry_after) else {
    fail("expected Retry-After header")
  }
  assert_true(retry_after.length() > 0)
  let ready = try! @rate_limit_policy.TokenBucket::new(1, 1, 100L, @async.now())
  let waited = wait_for_slot(ready)
  assert_eq(waited.available_tokens(), 0)
  let blocked = try! @rate_limit_policy.TokenBucket::with_tokens(
    1,
    1,
    1L,
    @async.now() + 1L,
    0,
  )
  let resumed = wait_for_slot(blocked)
  assert_eq(resumed.available_tokens(), 0)
}

///|
test "retry-after and sleep conversion helpers handle boundaries" {
  assert_eq(retry_after_seconds(0L), "0")
  assert_eq(retry_after_seconds(1L), "1")
  assert_eq(retry_after_seconds(1000L), "1")
  assert_eq(retry_after_seconds(1001L), "2")
  assert_eq(clamp_delay_ms(-1L), 0)
  assert_eq(clamp_delay_ms(25L), 25)
  assert_eq(clamp_delay_ms(2_147_483_648L), 2_147_483_647)
}
