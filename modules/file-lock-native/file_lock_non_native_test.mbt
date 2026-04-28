///|
fn[T] assert_unsupported(
  result : Result[T, @file_lock_native.LockError],
  name : String,
) -> Unit raise {
  match result {
    Err(Unsupported) => ()
    _ => fail(name + " should report Unsupported")
  }
}

///|
fn[T] assert_unsupported_error(
  result : Result[T, Error],
  name : String,
) -> Unit raise {
  match result {
    Err(@file_lock_native.Unsupported) => ()
    _ => fail(name + " should report Unsupported")
  }
}

///|
test "non-native targets report unsupported" {
  let path = "/tmp/moonbit-file-lock-native-unsupported-" +
    @env.now().to_string() +
    ".lock"
  @debug.assert_eq(@encoding/utf8.encode(path).length() > 0, true)
  let try_result : Result[
    @file_lock_native.LockGuard,
    @file_lock_native.LockError,
  ] = try? @file_lock_native.try_lock(path)
  assert_unsupported(try_result, "try_lock")
  let lock_result : Result[
    @file_lock_native.LockGuard,
    @file_lock_native.LockError,
  ] = try? @file_lock_native.lock(path)
  assert_unsupported(lock_result, "lock")
  let timeout_result : Result[
    @file_lock_native.LockGuard,
    @file_lock_native.LockError,
  ] = try? @file_lock_native.lock_timeout(path, 1)
  assert_unsupported(timeout_result, "lock_timeout")
  let scoped_result : Result[Int, Error] = try? @file_lock_native.with_lock(
    path,
    _ => 1,
  )
  assert_unsupported_error(scoped_result, "with_lock")
  let scoped_timeout_result : Result[Int, Error] = try? @file_lock_native.with_lock_timeout(
    path,
    1,
    _ => 1,
  )
  assert_unsupported_error(scoped_timeout_result, "with_lock_timeout")
}
