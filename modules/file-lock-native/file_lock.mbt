///|
/// An acquired advisory file lock.
///
/// `LockGuard` values are opaque native handles. They should be released with
/// `unlock`, `LockGuard::unlock`, or a scoped helper. The native handle also
/// has a finalizer as a last-resort cleanup path, but explicit release is the
/// deterministic API.
#external
pub(all) type LockGuard

///|
/// File locking errors.
pub(all) suberror LockError {
  /// The lock is currently held by another process.
  AlreadyLocked(String)
  /// The timeout elapsed before the lock could be acquired.
  Timeout(String)
  /// An operating-system call failed. Fields are path, operation, and errno.
  ///
  /// Unlock failures use an empty path because the native handle is opaque.
  Io(String, String, Int)
  /// The selected backend does not support native file locks.
  Unsupported
} derive(Eq, Debug)

///|
const MODE_BLOCKING = 0

///|
const MODE_TRY = 1

///|
const MODE_TIMEOUT = 2

///|
const STATUS_OK = 0

///|
const STATUS_ALREADY_LOCKED = 1

///|
const STATUS_TIMEOUT = 2

///|
const STATUS_IO = 3

///|
const STATUS_UNSUPPORTED = 4

///|
/// Acquire an exclusive advisory lock, waiting until another process releases
/// it if necessary.
///
/// The lock file is created if it does not exist.
pub fn lock(path : String) -> LockGuard raise LockError {
  acquire(path, MODE_BLOCKING, -1)
}

///|
/// Try to acquire an exclusive advisory lock without waiting.
///
/// Raises `AlreadyLocked(path)` if another process currently owns the lock.
pub fn try_lock(path : String) -> LockGuard raise LockError {
  acquire(path, MODE_TRY, 0)
}

///|
/// Acquire an exclusive advisory lock, waiting up to `timeout_millis`.
///
/// Values less than or equal to zero perform a single non-blocking attempt and
/// raise `Timeout(path)` when the lock is unavailable.
pub fn lock_timeout(
  path : String,
  timeout_millis : Int,
) -> LockGuard raise LockError {
  acquire(path, MODE_TIMEOUT, timeout_millis)
}

///|
/// Deterministically release a lock.
///
/// Calling `unlock` more than once on the same guard is a no-op.
#coverage.skip
pub fn unlock(lock_guard : LockGuard) -> Unit raise LockError {
  let status = native_unlock(lock_guard)
  if status != STATUS_OK {
    raise_status("", "unlock", status, native_errno(lock_guard))
  }
}

///|
/// Deterministically release a lock.
#coverage.skip
pub fn LockGuard::unlock(self : LockGuard) -> Unit raise LockError {
  unlock(self)
}

///|
/// Acquire a lock for the duration of `body`, then release it.
///
/// If `body` raises, this helper still attempts to release the lock and then
/// re-raises the original error.
#coverage.skip
pub fn[A] with_lock(path : String, body : (LockGuard) -> A raise) -> A raise {
  let lock_guard = lock(path)
  protect_unlock(lock_guard, body)
}

///|
/// Acquire a lock with a timeout for the duration of `body`, then release it.
#coverage.skip
pub fn[A] with_lock_timeout(
  path : String,
  timeout_millis : Int,
  body : (LockGuard) -> A raise,
) -> A raise {
  let lock_guard = lock_timeout(path, timeout_millis)
  protect_unlock(lock_guard, body)
}

///|
#coverage.skip
fn[A] protect_unlock(
  lock_guard : LockGuard,
  body : (LockGuard) -> A raise,
) -> A raise {
  try body(lock_guard) catch {
    error => {
      unlock(lock_guard) catch {
        _ => ()
      }
      raise error
    }
  } noraise {
    value => {
      unlock(lock_guard)
      value
    }
  }
}

///|
#cfg(any(target="native", target="llvm"))
#coverage.skip
fn acquire(
  path : String,
  mode : Int,
  timeout_millis : Int,
) -> LockGuard raise LockError {
  let bytes = encode_path(path)
  let native = native_acquire(bytes, mode, timeout_millis)
  let status = native_status(native)
  if status != STATUS_OK {
    raise_status(path, "lock", status, native_errno(native))
  }
  native
}

///|
#cfg(not(any(target="native", target="llvm")))
fn acquire(
  path : String,
  _mode : Int,
  _timeout_millis : Int,
) -> LockGuard raise LockError {
  ignore(@encoding/utf8.encode(path))
  raise Unsupported
}

///|
#cfg(any(target="native", target="llvm"))
#coverage.skip
fn encode_path(path : String) -> Bytes raise LockError {
  let raw = @encoding/utf8.encode(path)
  let bytes : Array[Byte] = []
  for byte in raw {
    if byte.to_int() == 0 {
      raise Io(path, "encode path", 22)
    }
    bytes.push(byte)
  }
  bytes.push(Int::to_byte(0))
  Bytes::from_array(bytes)
}

///|
#coverage.skip
fn raise_status(
  path : String,
  operation : String,
  status : Int,
  errno : Int,
) -> Unit raise LockError {
  match status {
    STATUS_ALREADY_LOCKED => raise AlreadyLocked(path)
    STATUS_TIMEOUT => raise Timeout(path)
    STATUS_UNSUPPORTED => raise Unsupported
    STATUS_IO => raise Io(path, operation, errno)
    _ => raise Io(path, operation, errno)
  }
}

///|
#cfg(any(target="native", target="llvm"))
#borrow(path)
extern "c" fn native_acquire(
  path : Bytes,
  mode : Int,
  timeout_millis : Int,
) -> LockGuard = "moonbit_file_lock_acquire"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn native_status(lock : LockGuard) -> Int = "moonbit_file_lock_status"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn native_errno(lock : LockGuard) -> Int = "moonbit_file_lock_errno"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn native_unlock(lock : LockGuard) -> Int = "moonbit_file_lock_unlock"

///|
#cfg(not(any(target="native", target="llvm")))
#coverage.skip
fn native_errno(_lock : LockGuard) -> Int {
  0
}

///|
#cfg(not(any(target="native", target="llvm")))
#coverage.skip
fn native_unlock(_lock : LockGuard) -> Int {
  STATUS_UNSUPPORTED
}
