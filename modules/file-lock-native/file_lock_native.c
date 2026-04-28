#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "moonbit.h"

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#define MOONBIT_FILE_LOCK_STATUS_OK 0
#define MOONBIT_FILE_LOCK_STATUS_ALREADY_LOCKED 1
#define MOONBIT_FILE_LOCK_STATUS_TIMEOUT 2
#define MOONBIT_FILE_LOCK_STATUS_IO 3
#define MOONBIT_FILE_LOCK_STATUS_UNSUPPORTED 4

#define MOONBIT_FILE_LOCK_MODE_BLOCKING 0
#define MOONBIT_FILE_LOCK_MODE_TRY 1
#define MOONBIT_FILE_LOCK_MODE_TIMEOUT 2

#define MOONBIT_FILE_LOCK_POLL_MILLIS 10

typedef struct {
  int fd;
  int status;
  int saved_errno;
} moonbit_file_lock_t;

static void moonbit_file_lock_finalize(void *self) {
  moonbit_file_lock_t *lock = (moonbit_file_lock_t *)self;
  if (lock->fd >= 0) {
    close(lock->fd);
    lock->fd = -1;
  }
}

static moonbit_file_lock_t *moonbit_file_lock_make(int status,
                                                   int saved_errno) {
  moonbit_file_lock_t *lock = (moonbit_file_lock_t *)moonbit_make_external_object(
      moonbit_file_lock_finalize, sizeof(moonbit_file_lock_t));
  lock->fd = -1;
  lock->status = status;
  lock->saved_errno = saved_errno;
  return lock;
}

static int moonbit_file_lock_conflict_errno(int err) {
  return err == EACCES || err == EAGAIN;
}

static int moonbit_file_lock_set(int fd, int command) {
  struct flock request;
  memset(&request, 0, sizeof(request));
  request.l_type = F_WRLCK;
  request.l_whence = SEEK_SET;
  request.l_start = 0;
  request.l_len = 0;
  return fcntl(fd, command, &request);
}

static int moonbit_file_lock_unset(int fd) {
  struct flock request;
  memset(&request, 0, sizeof(request));
  request.l_type = F_UNLCK;
  request.l_whence = SEEK_SET;
  request.l_start = 0;
  request.l_len = 0;
  return fcntl(fd, F_SETLK, &request);
}

static void moonbit_file_lock_sleep_millis(int millis) {
  if (millis <= 0) {
    return;
  }
  struct timespec delay;
  delay.tv_sec = millis / 1000;
  delay.tv_nsec = (long)(millis % 1000) * 1000000L;
  while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {
  }
}

static int64_t moonbit_file_lock_now_millis(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return ((int64_t)now.tv_sec * 1000) + (now.tv_nsec / 1000000);
}

static int moonbit_file_lock_try_fd(int fd, int timeout_millis,
                                    int poll_millis) {
  int64_t deadline = moonbit_file_lock_now_millis() + timeout_millis;
  if (poll_millis <= 0) {
    poll_millis = MOONBIT_FILE_LOCK_POLL_MILLIS;
  }
  if (moonbit_file_lock_set(fd, F_SETLK) == 0) {
    return MOONBIT_FILE_LOCK_STATUS_OK;
  }
  int err = errno;
  if (!moonbit_file_lock_conflict_errno(err)) {
    errno = err;
    return MOONBIT_FILE_LOCK_STATUS_IO;
  }
  for (;;) {
    if (timeout_millis <= 0) {
      errno = err;
      return MOONBIT_FILE_LOCK_STATUS_TIMEOUT;
    }
    int64_t now = moonbit_file_lock_now_millis();
    if (now >= deadline) {
      errno = err;
      return MOONBIT_FILE_LOCK_STATUS_TIMEOUT;
    }
    int64_t remaining = deadline - now;
    int sleep_millis =
        (int64_t)poll_millis < remaining ? poll_millis : (int)remaining;
    moonbit_file_lock_sleep_millis(sleep_millis);
    if (moonbit_file_lock_now_millis() >= deadline) {
      errno = err;
      return MOONBIT_FILE_LOCK_STATUS_TIMEOUT;
    }
    if (moonbit_file_lock_set(fd, F_SETLK) == 0) {
      return MOONBIT_FILE_LOCK_STATUS_OK;
    }
    err = errno;
    if (!moonbit_file_lock_conflict_errno(err)) {
      errno = err;
      return MOONBIT_FILE_LOCK_STATUS_IO;
    }
  }
}

MOONBIT_FFI_EXPORT void *moonbit_file_lock_acquire(moonbit_bytes_t path,
                                                   int32_t mode,
                                                   int32_t timeout_millis) {
  int fd;
  do {
    fd = open((const char *)path, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  } while (fd < 0 && errno == EINTR);

  if (fd < 0) {
    return moonbit_file_lock_make(MOONBIT_FILE_LOCK_STATUS_IO, errno);
  }

  int status = MOONBIT_FILE_LOCK_STATUS_OK;
  int saved_errno = 0;
  if (mode == MOONBIT_FILE_LOCK_MODE_BLOCKING) {
    while (moonbit_file_lock_set(fd, F_SETLKW) != 0) {
      if (errno != EINTR) {
        status = MOONBIT_FILE_LOCK_STATUS_IO;
        saved_errno = errno;
        break;
      }
    }
  } else if (mode == MOONBIT_FILE_LOCK_MODE_TRY) {
    if (moonbit_file_lock_set(fd, F_SETLK) != 0) {
      saved_errno = errno;
      status = moonbit_file_lock_conflict_errno(saved_errno)
                   ? MOONBIT_FILE_LOCK_STATUS_ALREADY_LOCKED
                   : MOONBIT_FILE_LOCK_STATUS_IO;
    }
  } else if (mode == MOONBIT_FILE_LOCK_MODE_TIMEOUT) {
    status = moonbit_file_lock_try_fd(fd, timeout_millis,
                                      MOONBIT_FILE_LOCK_POLL_MILLIS);
    if (status != MOONBIT_FILE_LOCK_STATUS_OK) {
      saved_errno = errno;
    }
  } else {
    status = MOONBIT_FILE_LOCK_STATUS_IO;
    saved_errno = EINVAL;
  }

  moonbit_file_lock_t *lock = moonbit_file_lock_make(status, saved_errno);
  if (status == MOONBIT_FILE_LOCK_STATUS_OK) {
    lock->fd = fd;
  } else {
    close(fd);
  }
  return lock;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_status(void *self) {
  return ((moonbit_file_lock_t *)self)->status;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_errno(void *self) {
  return ((moonbit_file_lock_t *)self)->saved_errno;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_unlock(void *self) {
  moonbit_file_lock_t *lock = (moonbit_file_lock_t *)self;
  if (lock->fd < 0) {
    lock->status = MOONBIT_FILE_LOCK_STATUS_OK;
    lock->saved_errno = 0;
    return MOONBIT_FILE_LOCK_STATUS_OK;
  }
  if (moonbit_file_lock_unset(lock->fd) != 0) {
    lock->status = MOONBIT_FILE_LOCK_STATUS_IO;
    lock->saved_errno = errno;
    return lock->status;
  }
  int fd = lock->fd;
  lock->fd = -1;
  if (close(fd) != 0) {
    lock->status = MOONBIT_FILE_LOCK_STATUS_IO;
    lock->saved_errno = errno;
    return lock->status;
  }
  lock->status = MOONBIT_FILE_LOCK_STATUS_OK;
  lock->saved_errno = 0;
  return MOONBIT_FILE_LOCK_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_test_spawn_holder(
    moonbit_bytes_t path, int32_t hold_millis) {
  int pipe_fds[2];
  if (pipe(pipe_fds) != 0) {
    return -errno;
  }
  pid_t pid = fork();
  if (pid < 0) {
    int saved_errno = errno;
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return -saved_errno;
  }
  if (pid == 0) {
    close(pipe_fds[0]);
    void *raw_lock = moonbit_file_lock_acquire(
        path, MOONBIT_FILE_LOCK_MODE_BLOCKING, -1);
    moonbit_file_lock_t *lock = (moonbit_file_lock_t *)raw_lock;
    char status = lock->status == MOONBIT_FILE_LOCK_STATUS_OK ? '1' : '0';
    ssize_t ignored = write(pipe_fds[1], &status, 1);
    (void)ignored;
    close(pipe_fds[1]);
    if (status == '1') {
      moonbit_file_lock_sleep_millis(hold_millis);
      moonbit_file_lock_unlock(lock);
    }
    _exit(status == '1' ? 0 : 1);
  }

  close(pipe_fds[1]);
  char status = '0';
  ssize_t read_size;
  do {
    read_size = read(pipe_fds[0], &status, 1);
  } while (read_size < 0 && errno == EINTR);
  close(pipe_fds[0]);
  if (read_size != 1 || status != '1') {
    int child_status;
    waitpid(pid, &child_status, 0);
    return -EIO;
  }
  return (int32_t)pid;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_test_wait_holder(int32_t pid) {
  int status;
  pid_t result;
  do {
    result = waitpid((pid_t)pid, &status, 0);
  } while (result < 0 && errno == EINTR);
  if (result < 0) {
    return -errno;
  }
  return status;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_test_unlink(
    moonbit_bytes_t path) {
  if (unlink((const char *)path) == 0 || errno == ENOENT) {
    return 0;
  }
  return -errno;
}

MOONBIT_FFI_EXPORT int32_t moonbit_file_lock_test_expired_timeout_status(
    moonbit_bytes_t path, int32_t hold_millis, int32_t timeout_millis,
    int32_t poll_millis) {
  int32_t pid = moonbit_file_lock_test_spawn_holder(path, hold_millis);
  if (pid <= 0) {
    return MOONBIT_FILE_LOCK_STATUS_IO;
  }

  int fd;
  do {
    fd = open((const char *)path, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  } while (fd < 0 && errno == EINTR);

  if (fd < 0) {
    (void)moonbit_file_lock_test_wait_holder(pid);
    return MOONBIT_FILE_LOCK_STATUS_IO;
  }

  int status = moonbit_file_lock_try_fd(fd, timeout_millis, poll_millis);
  if (status == MOONBIT_FILE_LOCK_STATUS_OK) {
    moonbit_file_lock_unset(fd);
  }
  close(fd);
  (void)moonbit_file_lock_test_wait_holder(pid);
  return status;
}
