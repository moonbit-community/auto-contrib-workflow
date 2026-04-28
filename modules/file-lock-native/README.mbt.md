# moonbit-community/file_lock_native

Linux and macOS advisory file locks for native MoonBit programs.

The module uses POSIX `fcntl` exclusive locks on the native and LLVM backends.
Locks are advisory: every cooperating process must use the same locking
discipline, and mandatory enforcement is not provided by the operating system.
Network filesystem semantics vary and are intentionally not guaranteed.

```mbt check
///|
test "try lock example" {
  try @file_lock_native.try_lock("/tmp/example-try.lock") catch {
    Unsupported => ()
    error => raise error
  } noraise {
    lock_guard => try! lock_guard.unlock()
  }
}
```

```mbt check
///|
test "blocking lock example" {
  try @file_lock_native.lock("/tmp/example-blocking.lock") catch {
    Unsupported => ()
    error => raise error
  } noraise {
    lock_guard => try! @file_lock_native.unlock(lock_guard)
  }
}
```

```mbt check
///|
test "scoped lock example" {
  try
    @file_lock_native.with_lock("/tmp/example-scoped.lock", _ => "protected")
  catch {
    @file_lock_native.Unsupported => ()
    error => raise error
  } noraise {
    result => inspect(result, content="protected")
  }
}
```

`LockGuard` has a native finalizer as a last-resort cleanup path, but explicit
`unlock` or scoped helpers should be used for deterministic release. Lock files
may remain on disk after a process exits; the operating system releases the
advisory lock with the file descriptor, not by deleting the file.
