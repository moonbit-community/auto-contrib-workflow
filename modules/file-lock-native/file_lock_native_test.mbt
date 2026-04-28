///|
fn test_path(name : String) -> String {
  "/tmp/moonbit-file-lock-native-" +
  @env.now().to_string() +
  "-" +
  name +
  ".lock"
}

///|
fn cleanup(path : String) -> Unit {
  ignore(unlink_test_path(native_path(path)))
}

///|
fn native_path(path : String) -> Bytes {
  let raw = @encoding/utf8.encode(path)
  let bytes : Array[Byte] = []
  for byte in raw {
    bytes.push(byte)
  }
  bytes.push(Int::to_byte(0))
  Bytes::from_array(bytes)
}

///|
const TEST_STATUS_TIMEOUT = 2

///|
#borrow(path)
extern "c" fn spawn_holder(path : Bytes, hold_millis : Int) -> Int = "moonbit_file_lock_test_spawn_holder"

///|
extern "c" fn wait_holder(pid : Int) -> Int = "moonbit_file_lock_test_wait_holder"

///|
#borrow(path)
extern "c" fn unlink_test_path(path : Bytes) -> Int = "moonbit_file_lock_test_unlink"

///|
#borrow(path)
extern "c" fn expired_timeout_status(
  path : Bytes,
  hold_millis : Int,
  timeout_millis : Int,
  poll_millis : Int,
) -> Int = "moonbit_file_lock_test_expired_timeout_status"

///|
test "same process lock unlock and reacquire" {
  let path = test_path("reacquire")
  let lock_guard = try! @file_lock_native.lock(path)
  try! lock_guard.unlock()
  try! lock_guard.unlock()
  let second = try! @file_lock_native.lock(path)
  try! @file_lock_native.unlock(second)
  cleanup(path)
}

///|
test "scoped helper releases the guard" {
  let path = test_path("scoped")
  let value = try! @file_lock_native.with_lock(path, _ => 42)
  @debug.assert_eq(value, 42)
  let second = try! @file_lock_native.try_lock(path)
  try! second.unlock()
  cleanup(path)
}

///|
test "two process try_lock contention" {
  let path = test_path("try-contention")
  let pid = spawn_holder(native_path(path), 200)
  guard pid > 0 else {
    cleanup(path)
    fail("failed to spawn holder")
  }
  let blocked : Result[@file_lock_native.LockGuard, @file_lock_native.LockError] = try? @file_lock_native.try_lock(
    path,
  )
  match blocked {
    Err(AlreadyLocked(actual_path)) => @debug.assert_eq(actual_path, path)
    _ => fail("try_lock should report AlreadyLocked")
  }
  ignore(wait_holder(pid))
  let lock_guard = try! @file_lock_native.try_lock(path)
  try! lock_guard.unlock()
  cleanup(path)
}

///|
test "two process timeout contention" {
  let path = test_path("timeout-contention")
  let pid = spawn_holder(native_path(path), 180)
  guard pid > 0 else {
    cleanup(path)
    fail("failed to spawn holder")
  }
  let blocked : Result[@file_lock_native.LockGuard, @file_lock_native.LockError] = try? @file_lock_native.lock_timeout(
    path, 30,
  )
  match blocked {
    Err(Timeout(actual_path)) => @debug.assert_eq(actual_path, path)
    _ => fail("lock_timeout should report Timeout")
  }
  ignore(wait_holder(pid))
  let lock_guard = try! @file_lock_native.lock_timeout(path, 200)
  try! lock_guard.unlock()
  cleanup(path)
}

///|
test "timeout does not acquire after expired deadline" {
  let path = test_path("expired-timeout")
  let status = expired_timeout_status(native_path(path), 50, 20, 80)
  @debug.assert_eq(status, TEST_STATUS_TIMEOUT)
  let lock_guard = try! @file_lock_native.try_lock(path)
  try! lock_guard.unlock()
  cleanup(path)
}

///|
test "lock is released when holder process exits" {
  let path = test_path("process-exit")
  let pid = spawn_holder(native_path(path), 20)
  guard pid > 0 else {
    cleanup(path)
    fail("failed to spawn holder")
  }
  ignore(wait_holder(pid))
  let lock_guard = try! @file_lock_native.lock_timeout(path, 200)
  try! lock_guard.unlock()
  cleanup(path)
}

///|
test "path with nul byte is rejected before native calls" {
  let invalid : Result[@file_lock_native.LockGuard, @file_lock_native.LockError] = try? @file_lock_native.lock(
    "bad\u{0000}path",
  )
  match invalid {
    Err(Io(path, operation, errno)) => {
      @debug.assert_eq(path, "bad\u{0000}path")
      @debug.assert_eq(operation, "encode path")
      @debug.assert_eq(errno, 22)
    }
    _ => fail("nul byte should report path encoding failure")
  }
}
